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
  let fm=FileManager.default,root=fm.temporaryDirectory.appendingPathComponent("gq-backup-test-"+UUID().uuidString)
  let app=root.appendingPathComponent("App"),group=root.appendingPathComponent("Group")
  for p in [app,group] { try fm.createDirectory(at:p,withIntermediateDirectories:true) }
  setenv("TEST_APP",app.path,1);setenv("TEST_GROUP",group.path,1);setenv("GQNS_RESTORE_ROOT",root.appendingPathComponent("Jobs").path,1)
  let doc=Data("PDF and Word test payload".utf8)
  try doc.write(to:app.appendingPathComponent("paper.pdf"));try doc.write(to:app.appendingPathComponent("paper.docx"))
  var db:OpaquePointer?;assert(sqlite3_open(group.appendingPathComponent("test.sqlite").path,&db)==SQLITE_OK)
  assert(sqlite3_exec(db,"PRAGMA journal_mode=WAL;CREATE TABLE t (v TEXT);INSERT INTO t VALUES('committed WAL data');",nil,nil,nil)==SQLITE_OK)
  let archive=root.appendingPathComponent("backup.zip")
  print("Export stage");fflush(stdout)
  _ = try AppBackupExport.export(appSupport:app,group:group,destination:archive)
  print("Prepare stage");fflush(stdout)
  let (staged,m)=try AppBackupRestore.prepare(archive);assert(m.files.count==4)
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
}
