import Foundation
import SQLite3

/// The widget reads the existing schema-1 journal without opening its writable
/// initializer. It never imports a peer library or writes/deletes shared sleep.
enum HealthSleepRewardSync {
    private enum NoChange: Error { case alreadySettled }

    @discardableResult static func synchronize(directory: URL, now: Date = Date(), sharedDirectory: URL? = nil) throws -> Bool {
        let source = sharedDirectory ?? ProcessInfo.processInfo.environment["GAOSERIES_SLEEP_TEST_DIRECTORY"].map { URL(fileURLWithPath:$0,isDirectory:true) }
            ?? directory.deletingLastPathComponent().appendingPathComponent("SharedSleep",isDirectory:true)
        let rewards = try readRewards(directory:source)
        let snapshot = try HealthDatabase(directory:directory,access:.readOnlyExisting).read()
        guard !Engine.eligibleSleep(snapshot,records:rewards,now:now).isEmpty else { return false }
        let database = try HealthDatabase(directory:directory,access:.readWriteExisting)
        do {
            try database.transaction(now:now) { state in
                guard !Engine.eligibleSleep(state,records:rewards,now:now).isEmpty else { throw NoChange.alreadySettled }
                Engine.rewardSleep(&state,records:rewards,now:now)
            }
            return true
        } catch NoChange.alreadySettled { return false }
    }

    static func readRewards(directory: URL) throws -> [Engine.SleepReward] {
        let url = directory.appendingPathComponent("sleep-records.sqlite")
        let fm = FileManager.default
        do {
            guard try fm.attributesOfItem(atPath:url.path)[.type] as? FileAttributeType == .typeRegular else { throw HealthError("共享睡眠路径无效 / Invalid shared sleep path") }
        } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
            // Only genuine absence means no first journal yet. Permission/I/O
            // failures propagate, and any surviving sidecar/marker is lost data.
            do {
                guard try fm.attributesOfItem(atPath:directory.path)[.type] as? FileAttributeType == .typeDirectory,
                      try fm.contentsOfDirectory(atPath:directory.path).isEmpty else {
                    throw HealthError("共享睡眠库缺失，原健康资料保留 / Shared sleep database missing; Health data retained")
                }
            } catch let error as CocoaError where error.code == .fileReadNoSuchFile || error.code == .fileNoSuchFile {
                _ = try fm.contentsOfDirectory(atPath:directory.deletingLastPathComponent().path)
            }
            return []
        }
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path,&db,SQLITE_OPEN_READONLY|SQLITE_OPEN_FULLMUTEX,nil)==SQLITE_OK else {
            sqlite3_close(db); throw HealthError("无法读取共享睡眠 / Shared sleep unavailable")
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db,5000)
        func prepare(_ sql: String) throws -> OpaquePointer {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db,sql,-1,&statement,nil)==SQLITE_OK, let statement else { throw HealthError("共享睡眠存档不可读 / Shared sleep journal unreadable") }
            return statement
        }
        guard sqlite3_exec(db,"BEGIN DEFERRED",nil,nil,nil)==SQLITE_OK else { throw HealthError("共享睡眠读取繁忙 / Shared sleep busy") }
        defer { sqlite3_exec(db,"ROLLBACK",nil,nil,nil) }
        let integrity = try prepare("PRAGMA quick_check")
        defer { sqlite3_finalize(integrity) }
        guard sqlite3_step(integrity)==SQLITE_ROW, let status=sqlite3_column_text(integrity,0), String(cString:status)=="ok", sqlite3_step(integrity)==SQLITE_DONE else { throw HealthError("共享睡眠完整性校验失败 / Shared sleep integrity check failed") }
        let schema = try prepare("SELECT version FROM sleep_metadata WHERE id=1")
        defer { sqlite3_finalize(schema) }
        guard sqlite3_step(schema)==SQLITE_ROW, sqlite3_column_type(schema,0)==SQLITE_INTEGER, sqlite3_column_int(schema,0)==1, sqlite3_step(schema)==SQLITE_DONE else { throw HealthError("不支持此共享睡眠版本 / Unsupported shared sleep version") }
        let statement = try prepare("SELECT id,payload,deleted FROM sleep_records ORDER BY id")
        defer { sqlite3_finalize(statement) }
        var results: [Engine.SleepReward] = []
        var ids = Set<String>()
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW, sqlite3_column_type(statement,0)==SQLITE_TEXT,
                  let idBytes=sqlite3_column_text(statement,0), sqlite3_column_type(statement,2)==SQLITE_INTEGER else { throw HealthError("共享睡眠记录不可读 / Shared sleep row unreadable") }
            let id = String(cString:idBytes), deleted = sqlite3_column_int(statement,2)
            guard !id.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty, ids.insert(id).inserted, deleted==0 || deleted==1 else { throw HealthError("共享睡眠标记无效 / Invalid shared sleep identity or tombstone") }
            if deleted==1 { continue }
            guard let bytes=sqlite3_column_blob(statement,1), sqlite3_column_bytes(statement,1)>0 else { throw HealthError("共享睡眠内容缺失 / Shared sleep payload missing") }
            let entry = try JSONDecoder().decode(SharedSleepEntry.self,from:Data(bytes:bytes,count:Int(sqlite3_column_bytes(statement,1))))
            guard entry.id==id, !entry.id.contains("\0"), entry.startedAt.timeIntervalSince1970.isFinite,
                  entry.endedAt.timeIntervalSince1970.isFinite, entry.endedAt>=entry.startedAt,
                  entry.durationSeconds.isFinite, entry.durationSeconds>=0, (0...100).contains(entry.score), entry.pastureYield>=0,
                  [entry.healthGrowthCreditedSeconds,entry.manualGrowthCreditedSeconds].compactMap({$0}).allSatisfy({$0.isFinite && $0>=0}),
                  [entry.healthProductionCreditedCycles,entry.manualProductionCreditedCycles].compactMap({$0}).allSatisfy({$0>=0}) else { throw HealthError("共享睡眠内容无效 / Invalid shared sleep payload") }
            results.append(.init(id:id,endedAt:entry.endedAt,durationSeconds:entry.durationSeconds))
        }
        return results
    }
}
