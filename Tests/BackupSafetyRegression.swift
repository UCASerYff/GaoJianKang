import Foundation
import SQLite3

#if !BACKUP_SAFETY_TEST
#error("Run scripts/test_backup.sh to use the isolated test app and fixture defaults.")
#endif

/// This module-local type shadows Foundation.UserDefaults in the compiled Host
/// sources. All fixture settings remain in memory, including the module domain.
final class UserDefaults {
    static let standard = UserDefaults()
    private var domains: [String: [String: Any]] = [:]
    private(set) var readCount = 0
    private(set) var writeCount = 0
    var failNextSynchronization = false

    func persistentDomain(forName name: String) -> [String: Any]? {
        check(name)
        readCount += 1
        return domains[name]
    }

    func setPersistentDomain(_ domain: [String: Any], forName name: String) {
        check(name)
        writeCount += 1
        domains[name] = domain
    }
    func removePersistentDomain(forName name: String) { check(name); writeCount += 1; domains.removeValue(forKey:name) }
    func synchronize() -> Bool {
        if failNextSynchronization { failNextSynchronization = false; return false }
        return true
    }

    private func check(_ name: String) {
        precondition(name == "com.gao.health.tests.backup-safety" ||
                     name == "com.gaoseries.GaoJianKang.Health",
                     "Unexpected fixture defaults domain")
    }
}


enum AppDataLocations {
 static var appSupport:URL? { URL(fileURLWithPath:ProcessInfo.processInfo.environment["TEST_APP"]!) }
 static var groupContainer:URL? { URL(fileURLWithPath:ProcessInfo.processInfo.environment["TEST_GROUP"]!) }
}
@main struct BackupSafetyRegression {
 static func main() throws {
  if CommandLine.arguments.count == 3 && CommandLine.arguments[1] == "--validate-only" {
   let source=URL(fileURLWithPath:CommandLine.arguments[2],isDirectory:true),fm=FileManager.default
   let before=try BackupIntegrity.manifest(source)
   let copy=fm.temporaryDirectory.appendingPathComponent("archive-validation-"+UUID().uuidString+".noindex")
   defer {try? fm.removeItem(at:copy)}
   // A WAL-mode SQLite reader may need scratch SHM even for a consistent DB.
   // Copy the real archive bytes so validation never writes inside its backup.
   try fm.createDirectory(at:copy,withIntermediateDirectories:true)
   for file in try BackupIntegrity.files(source) {
    let relative=String(file.path.dropFirst(source.path.count+1))
    let destination=copy.appendingPathComponent(relative)
    try fm.createDirectory(at:destination.deletingLastPathComponent(),withIntermediateDirectories:true)
    try Data(contentsOf:file).write(to:destination)
   }
   try check(BackupIntegrity.manifest(copy)==before)
   // Apple's read-only SQLite connection cannot initialize absent WAL sidecars
   // for these upgrade snapshots. A query-only writer creates scratch locks on
   // the disposable byte copy; it never mutates the source or business rows.
   var scratch:OpaquePointer?
   guard sqlite3_open_v2(copy.appendingPathComponent("health.sqlite").path,&scratch,SQLITE_OPEN_READWRITE,nil)==SQLITE_OK,let scratch else {
    throw CocoaError(.fileReadCorruptFile)
   }
   defer {sqlite3_close(scratch)}
   guard sqlite3_exec(scratch,"PRAGMA query_only=ON; SELECT count(*) FROM sqlite_master",nil,nil,nil)==SQLITE_OK else {
    throw CocoaError(.fileReadCorruptFile)
   }
   try HealthArchiveValidation.validate(directory:copy)
   try check(BackupIntegrity.manifest(source)==before)
   print("PASS Read-only archive compatibility: real backup copy; original file hashes unchanged; no restore")
   return
  }
  let fm=FileManager.default,root=fm.temporaryDirectory.appendingPathComponent("gq-backup-test-"+UUID().uuidString)
  let app=root.appendingPathComponent("App"),group=root.appendingPathComponent("Group")
  for p in [app,group] { try fm.createDirectory(at:p,withIntermediateDirectories:true) }
  setenv("TEST_APP",app.path,1);setenv("TEST_GROUP",group.path,1);setenv("GQNS_RESTORE_ROOT",root.appendingPathComponent("Jobs").path,1)
  setenv("GAOJIANKANG_TEST_DIRECTORY",group.appendingPathComponent("Health").path,1)
  setenv("GAOSERIES_SLEEP_TEST_DIRECTORY",root.appendingPathComponent("unused-shared").path,1)
  try createHealth(group.appendingPathComponent("Health"))
  let doc=Data("PDF and Word test payload".utf8)
  try doc.write(to:app.appendingPathComponent("paper.pdf"));try doc.write(to:app.appendingPathComponent("paper.docx"))
  var db:OpaquePointer?;assert(sqlite3_open(group.appendingPathComponent("test.sqlite").path,&db)==SQLITE_OK)
  assert(sqlite3_exec(db,"PRAGMA journal_mode=WAL;CREATE TABLE t (v TEXT);INSERT INTO t VALUES('committed WAL data');",nil,nil,nil)==SQLITE_OK)
  let archive=root.appendingPathComponent("backup.zip")
  print("Export stage");fflush(stdout)
  _ = try AppBackupExport.export(appSupport:app,group:group,destination:archive)
  print("Prepare stage");fflush(stdout)
  let (staged,m)=try AppBackupRestore.prepare(archive);assert(m.files.count==5)
  sqlite3_close(db)
  try Data("new current data".utf8).write(to:app.appendingPathComponent("paper.pdf"))
  try AppBackupRestore.schedule(staged);try AppBackupRestore.applyPending()
  let restored=try Data(contentsOf:app.appendingPathComponent("paper.pdf"));assert(restored==doc)
  assert(DailyBackup.integrityCheck(group.appendingPathComponent("test.sqlite"))=="ok")
  // Restoring a pre-sync backup must not erase newly introduced shared sleep data.
  let shared=group.appendingPathComponent("SharedSleep",isDirectory:true)
  try fm.createDirectory(at:shared,withIntermediateDirectories:true)
  var sleepDB:OpaquePointer?;assert(sqlite3_open(shared.appendingPathComponent("sleep-records.sqlite").path,&sleepDB)==SQLITE_OK)
  assert(sqlite3_exec(sleepDB,"CREATE TABLE sleep_records(id TEXT PRIMARY KEY,payload BLOB,deleted INTEGER);INSERT INTO sleep_records VALUES('deleted',NULL,1);",nil,nil,nil)==SQLITE_OK)
  sqlite3_close(sleepDB)
  try Data("SharedSleep schema 1\n".utf8).write(to:shared.appendingPathComponent(".initialized"))
  try Data("shared current".utf8).write(to:shared.appendingPathComponent("sleep-fixture.txt"))
  let (legacyStage,_)=try AppBackupRestore.prepare(archive)
  try AppBackupRestore.schedule(legacyStage);try AppBackupRestore.applyPending()
  let retained=try Data(contentsOf:shared.appendingPathComponent("sleep-fixture.txt"));assert(retained==Data("shared current".utf8))
  let sharedArchive=root.appendingPathComponent("shared-backup.zip")
  _ = try AppBackupExport.export(appSupport:app,group:group,destination:sharedArchive)
  let (sharedStage,_)=try AppBackupRestore.prepare(sharedArchive)
  setenv("TEST_SLEEP_PEER_RUNNING","1",1)
  do { try AppBackupRestore.schedule(sharedStage);assertionFailure("accepted running sleep peer") } catch {}
  unsetenv("TEST_SLEEP_PEER_RUNNING")
  try Data("changed shared".utf8).write(to:shared.appendingPathComponent("sleep-fixture.txt"))
  try AppBackupRestore.schedule(sharedStage);try AppBackupRestore.applyPending()
  let restoredSleep=try Data(contentsOf:shared.appendingPathComponent("sleep-fixture.txt"));assert(restoredSleep==Data("shared current".utf8))
  try restoreSafetyCases(root:root,app:app,group:group,archive:sharedArchive)
  let previousHash=try BackupIntegrity.hash(archive)
  // Corrupt source databases cannot replace a known-good existing archive.
  try Data("not sqlite".utf8).write(to:group.appendingPathComponent("broken.sqlite"))
  do { _ = try AppBackupExport.export(appSupport:app,group:group,destination:archive);assertionFailure("accepted corrupt db") } catch {}
  let afterHash=try BackupIntegrity.hash(archive);assert(previousHash==afterHash)
  let (bad,_)=try AppBackupRestore.prepare(archive)
  try Data("tampered".utf8).write(to:bad.appendingPathComponent("ApplicationSupport-Health/paper.pdf"))
  do { _ = try BackupIntegrity.verify(bad);assertionFailure("accepted corrupt attachment") } catch {}
  // A lost canonical journal must never replace a known-good archive with emptiness.
  try fm.removeItem(at:shared.appendingPathComponent("sleep-records.sqlite"))
  do { _ = try AppBackupExport.export(appSupport:app,group:group,destination:archive);assertionFailure("accepted missing shared journal") } catch {}
  let missingJournalHash=try BackupIntegrity.hash(archive);assert(previousHash==missingJournalHash)
  print("PASS Backup: WAL-consistent snapshot; SHA-256 attachments; export/preview/restore roundtrip; original preserved on export failure; shared journal and tombstones retained; legacy shared sleep preserved; active peer and lost journal rejected; tampering rejected; safety copy retained")
  try fm.removeItem(at:root)
 }
 static func createHealth(_ directory:URL) throws {
  let db=try HealthDatabase(directory:directory)
  _ = try db.read()
 }
 static func executeSQL(_ file:URL,_ sql:String) throws {
  var db:OpaquePointer?
  guard sqlite3_open_v2(file.path,&db,SQLITE_OPEN_READWRITE,nil)==SQLITE_OK,let db else { throw CocoaError(.fileReadCorruptFile) }
  defer {sqlite3_close(db)}
  guard sqlite3_exec(db,sql,nil,nil,nil)==SQLITE_OK else {throw CocoaError(.fileWriteUnknown)}
 }
 static func replaceCore(_ file:URL,_ change:(inout [String:Any])->Void) throws {
  var db:OpaquePointer?
  guard sqlite3_open_v2(file.path,&db,SQLITE_OPEN_READWRITE,nil)==SQLITE_OK,let db else {throw CocoaError(.fileReadCorruptFile)}
  defer {sqlite3_close(db)}
  var st:OpaquePointer?
  guard sqlite3_prepare_v2(db,"SELECT json FROM state WHERE id=1",-1,&st,nil)==SQLITE_OK,
        sqlite3_step(st)==SQLITE_ROW,let bytes=sqlite3_column_blob(st,0) else {throw CocoaError(.fileReadCorruptFile)}
  var core=try JSONSerialization.jsonObject(with:Data(bytes:bytes,count:Int(sqlite3_column_bytes(st,0)))) as! [String:Any]
  sqlite3_finalize(st);change(&core)
  let data=try JSONSerialization.data(withJSONObject:core)
  guard sqlite3_prepare_v2(db,"UPDATE state SET json=? WHERE id=1",-1,&st,nil)==SQLITE_OK else {throw CocoaError(.fileReadCorruptFile)}
  defer {sqlite3_finalize(st)}
  _=data.withUnsafeBytes {sqlite3_bind_blob(st,1,$0.baseAddress,Int32($0.count),unsafeBitCast(-1,to:sqlite3_destructor_type.self))}
  guard sqlite3_step(st)==SQLITE_DONE else {throw CocoaError(.fileWriteUnknown)}
 }
 static func restoreSafetyCases(root:URL,app:URL,group:URL,archive:URL) throws {
  let fm=FileManager.default,standard=Bundle.main.bundleIdentifier!,module="com.gaoseries.GaoJianKang.Health"
  let original=try BackupIntegrity.manifest(group)
  // Both supported legacy JSON versions remain readable without migration.
  for jsonVersion in [1,2] {
   let legacy=root.appendingPathComponent("legacy-health-\(jsonVersion)")
   try fm.copyItem(at:group.appendingPathComponent("Health"),to:legacy)
   let file=legacy.appendingPathComponent("health.sqlite")
   var state=HealthState(),record=HealthRecord(kind:.water);record.amount=125
   state.records=[record]
   var json=try JSONSerialization.jsonObject(with:JSONEncoder().encode(state)) as! [String:Any]
   json["schemaVersion"]=jsonVersion
   if jsonVersion==1 {json.removeValue(forKey:"events");json.removeValue(forKey:"eventTypes")}
   let encoded=try JSONSerialization.data(withJSONObject:json).map {String(format:"%02x",$0)}.joined()
   try executeSQL(file,"DROP TABLE records;DROP TABLE events;PRAGMA user_version=0;UPDATE state SET json=x'\(encoded)'")
   let before=try BackupIntegrity.manifest(legacy)
   try HealthArchiveValidation.validate(directory:legacy)
   try check(BackupIntegrity.manifest(legacy)==before)
  }
  UserDefaults.standard.setPersistentDomain(["keep":"current-standard"],forName:standard)
  UserDefaults.standard.setPersistentDomain(["keep":"current-module"],forName:module)
  for defect in ["missing-health","future-sql","future-json","bad-json","invalid-game","invalid-record","invalid-event","index-mismatch","index-lowercase","index-nul"] {
   let invalid=root.appendingPathComponent("invalid-"+defect)
   try fm.copyItem(at:group,to:invalid)
   let file=invalid.appendingPathComponent("Health/health.sqlite")
   switch defect {
   case "missing-health":try fm.removeItem(at:file)
   case "future-sql":try executeSQL(file,"PRAGMA user_version=999")
   case "future-json":try replaceCore(file){$0["schemaVersion"]=999}
   case "bad-json":try executeSQL(file,"UPDATE state SET json=x'7b'")
   case "invalid-game":try replaceCore(file){var island=$0["island"] as! [String:Any];island["energy"] = -1;$0["island"]=island}
   case "invalid-record":try executeSQL(file,"INSERT INTO records VALUES('invalid','water',1,x'7b')")
   case "invalid-event":try executeSQL(file,"INSERT INTO events VALUES('invalid','invalid',1,x'7b')")
   default:
    var record=HealthRecord(kind:.water);record.amount=250
    let json=try JSONEncoder().encode(record).map {String(format:"%02x",$0)}.joined()
    let id = defect == "index-lowercase" ? "'\(record.id.uuidString.lowercased())'" :
             defect == "index-nul" ? "'\(record.id.uuidString)' || char(0) || 'junk'" : "'\(record.id.uuidString)'"
    let kind = defect == "index-mismatch" ? "weight" : "water"
    try executeSQL(file,"INSERT INTO records VALUES(\(id),'\(kind)',\(record.occurredAt.timeIntervalSince1970),x'\(json)')")
   }
   let damaged=try BackupIntegrity.manifest(invalid)
   let zip=root.appendingPathComponent(defect+".zip")
   _ = try AppBackupExport.export(appSupport:app,group:invalid,destination:zip)
   do {_ = try AppBackupRestore.prepare(zip);assertionFailure("accepted \(defect)")} catch {}
   try check(BackupIntegrity.manifest(group)==original)
   try check(BackupIntegrity.manifest(invalid)==damaged)
   assert(UserDefaults.standard.persistentDomain(forName:standard)?["keep"] as? String == "current-standard")
   assert(UserDefaults.standard.persistentDomain(forName:module)?["keep"] as? String == "current-module")
  }
  // A source can change after prepare; apply must reject it before moving live data.
  let (late,_)=try AppBackupRestore.prepare(archive)
  try fm.removeItem(at:late.appendingPathComponent("AppGroupContainer/Health/health.sqlite"))
  try reseal(late)
  try AppBackupRestore.schedule(late)
  do {try AppBackupRestore.applyPending();assertionFailure("accepted missing health at apply")} catch {}
  try check(BackupIntegrity.manifest(group)==original)
  try fm.removeItem(at:AppBackupRestore.pending)
  // Failure after the first preference write restores both current domains and files.
  let (failed,_)=try AppBackupRestore.prepare(archive)
  try AppBackupRestore.schedule(failed)
  UserDefaults.standard.failNextSynchronization=true
  do {try AppBackupRestore.applyPending();assertionFailure("accepted failed preference persistence")} catch {}
  try check(BackupIntegrity.manifest(group)==original)
  assert(UserDefaults.standard.persistentDomain(forName:standard)?["keep"] as? String == "current-standard")
  assert(UserDefaults.standard.persistentDomain(forName:module)?["keep"] as? String == "current-module")
  assert(!fm.fileExists(atPath:AppBackupRestore.pending.path))
  UserDefaults.standard.removePersistentDomain(forName:module)
  let (absent,_)=try AppBackupRestore.prepare(archive)
  try AppBackupRestore.schedule(absent)
  UserDefaults.standard.failNextSynchronization=true
  do {try AppBackupRestore.applyPending();assertionFailure("accepted failed absent-domain rollback")} catch {}
  assert(UserDefaults.standard.persistentDomain(forName:module)==nil)
  assert(UserDefaults.standard.persistentDomain(forName:standard)?["keep"] as? String == "current-standard")
  UserDefaults.standard.setPersistentDomain(["keep":"current-module"],forName:module)
  // Invalid archive preference types are rejected before applying any files.
  let (badPreferences,_)=try AppBackupRestore.prepare(archive)
  try PropertyListSerialization.data(fromPropertyList:["standard":"invalid"],format:.binary,options:0).write(to:badPreferences.appendingPathComponent("preferences.plist"))
  try reseal(badPreferences);try AppBackupRestore.schedule(badPreferences)
  do {try AppBackupRestore.applyPending();assertionFailure("accepted malformed preferences")} catch {}
  try check(BackupIntegrity.manifest(group)==original)
  assert(UserDefaults.standard.persistentDomain(forName:standard)?["keep"] as? String == "current-standard")
  try fm.removeItem(at:AppBackupRestore.pending)
  // Missing archive preferences are preserved, rather than decoded as empty domains.
  let (legacy,_)=try AppBackupRestore.prepare(archive)
  try fm.removeItem(at:legacy.appendingPathComponent("preferences.plist"));try reseal(legacy)
  try AppBackupRestore.schedule(legacy);try AppBackupRestore.applyPending()
  assert(UserDefaults.standard.persistentDomain(forName:standard)?["keep"] as? String == "current-standard")
  // A durable receipt supports recovery after process interruption, not just
  // rollback within the same function invocation.
  let (interrupted,_)=try AppBackupRestore.prepare(archive)
  try AppBackupRestore.schedule(interrupted)
  var interruptedJob=try JSONDecoder().decode(AppBackupRestore.Job.self,from:Data(contentsOf:AppBackupRestore.pending))
  try fm.createDirectory(at:interruptedJob.safety,withIntermediateDirectories:true)
  let receipt=interruptedJob.safety.appendingPathComponent("original-preferences.json")
  try RestorePreferences.capture(to:receipt)
  interruptedJob.originalPreferences=receipt;interruptedJob.applying=true
  try JSONEncoder().encode(interruptedJob).write(to:AppBackupRestore.pending)
  UserDefaults.standard.setPersistentDomain(["interrupted":true],forName:standard)
  do {try AppBackupRestore.applyPending();assertionFailure("interrupted restore must report rollback")} catch {}
  assert(UserDefaults.standard.persistentDomain(forName:standard)?["keep"] as? String == "current-standard")
  assert(!fm.fileExists(atPath:AppBackupRestore.pending.path))
  // Interrupted older jobs without a preference receipt cannot guess a rollback.
  let (old,_)=try AppBackupRestore.prepare(archive)
  try AppBackupRestore.schedule(old)
  var job=try JSONDecoder().decode(AppBackupRestore.Job.self,from:Data(contentsOf:AppBackupRestore.pending))
  job.applying=true
  try JSONEncoder().encode(job).write(to:AppBackupRestore.pending)
  let pending=try Data(contentsOf:AppBackupRestore.pending)
  do {try AppBackupRestore.applyPending();assertionFailure("accepted old incomplete preference receipt")} catch {}
  try check(Data(contentsOf:AppBackupRestore.pending)==pending)
  try check(BackupIntegrity.manifest(group)==original)
  try fm.removeItem(at:AppBackupRestore.pending)
  print("PASS Restore guard: real Health decoder/schema/rows; missing/corrupt/future save refusal; unchanged originals; durable preference rollback; legacy absent preferences; interrupted legacy job retained")
 }
 static func check(_ value: @autoclosure () throws -> Bool) throws { let result=try value();assert(result) }
 static func reseal(_ staged:URL) throws {
  let file=staged.appendingPathComponent("gqns-manifest.json")
  var manifest=try JSONDecoder().decode(BackupIntegrity.Manifest.self,from:Data(contentsOf:file))
  manifest.files=try BackupIntegrity.manifest(staged)
  try JSONEncoder().encode(manifest).write(to:file)
 }
}
