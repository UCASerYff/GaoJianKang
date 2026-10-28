import Foundation
import SQLite3

/// The Host uses the same decoder and game validation as the live database.
/// Archive checks are read-only and never migrate or initialize a missing save.
public enum HealthArchiveValidation {
    public static func validate(directory: URL) throws {
        _ = try HealthDatabase(directory: directory, access: .readOnlyExisting).readVersioned()
        var database: OpaquePointer?
        let file = directory.appendingPathComponent("health.sqlite")
        guard sqlite3_open_v2(file.path, &database, SQLITE_OPEN_READONLY | SQLITE_OPEN_FULLMUTEX, nil) == SQLITE_OK,
              let database else {
            if let database { sqlite3_close(database) }
            throw HealthError("备份健康资料库无法读取 / Cannot read archived health database")
        }
        defer { sqlite3_close(database) }
        sqlite3_busy_timeout(database, 5000)
        func rows(_ sql: String, _ inspect: (OpaquePointer) throws -> Void) throws {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
                throw HealthError("备份健康资料结构无效 / Invalid archived health schema")
            }
            defer { sqlite3_finalize(statement) }
            var result = sqlite3_step(statement)
            while result == SQLITE_ROW { try inspect(statement); result = sqlite3_step(statement) }
            guard result == SQLITE_DONE else { throw HealthError("备份健康资料读取失败 / Archived health read failed") }
        }
        func text(_ statement: OpaquePointer, _ column: Int32) throws -> String {
            guard sqlite3_column_type(statement, column) == SQLITE_TEXT,
                  let value = sqlite3_column_text(statement, column) else { throw HealthError("备份记录索引无效 / Invalid archived record index") }
            let data = Data(bytes: value, count: Int(sqlite3_column_bytes(statement, column)))
            guard let decoded = String(data: data, encoding: .utf8), !decoded.contains("\0") else {
                throw HealthError("备份记录索引编码无效 / Invalid archived record index encoding")
            }
            return decoded
        }
        func blob(_ statement: OpaquePointer, _ column: Int32) throws -> Data {
            guard let value = sqlite3_column_blob(statement, column) else { throw HealthError("备份记录内容缺失 / Missing archived record") }
            return Data(bytes: value, count: Int(sqlite3_column_bytes(statement, column)))
        }
        var checks = 0
        try rows("PRAGMA integrity_check") { statement in
            guard try text(statement, 0) == "ok" else { throw HealthError("备份健康资料库损坏 / Corrupt archived health database") }
            checks += 1
        }
        guard checks == 1 else { throw HealthError("备份健康资料库校验失败 / Archived health integrity check failed") }
        var version = -1
        try rows("PRAGMA user_version") { version = Int(sqlite3_column_int($0, 0)) }
        var coreCount = 0
        try rows("SELECT id,json FROM state") { statement in
            guard sqlite3_column_type(statement, 0) == SQLITE_INTEGER, sqlite3_column_int64(statement, 0) == 1 else {
                throw HealthError("备份健康主记录无效 / Invalid archived health core")
            }
            let state = try JSONDecoder().decode(HealthState.self, from: blob(statement, 1))
            if version == 1 {
                guard state.records.isEmpty && state.events.isEmpty else { throw HealthError("备份包含冲突的记录布局 / Conflicting archived record layout") }
            }
            coreCount += 1
        }
        guard coreCount == 1 else { throw HealthError("备份健康主记录缺失 / Missing archived health core") }
        if version == 1 {
            try rows("SELECT id,kind,occurred_at,json FROM records") { statement in
                let record = try JSONDecoder().decode(HealthRecord.self, from: blob(statement, 3))
                let timeType = sqlite3_column_type(statement, 2)
                guard try text(statement, 0) == record.id.uuidString,
                      try text(statement, 1) == record.kind.rawValue,
                      timeType == SQLITE_FLOAT || timeType == SQLITE_INTEGER,
                      abs(sqlite3_column_double(statement, 2) - record.occurredAt.timeIntervalSince1970) <= 0.000001 else {
                    throw HealthError("备份健康记录索引与内容不一致 / Archived health record index mismatch")
                }
            }
            try rows("SELECT id,type_id,occurred_at,json FROM events") { statement in
                let event = try JSONDecoder().decode(HealthEvent.self, from: blob(statement, 3))
                let timeType = sqlite3_column_type(statement, 2)
                guard try text(statement, 0) == event.id.uuidString,
                      try text(statement, 1) == event.typeID.uuidString,
                      timeType == SQLITE_FLOAT || timeType == SQLITE_INTEGER,
                      abs(sqlite3_column_double(statement, 2) - event.occurredAt.timeIntervalSince1970) <= 0.000001 else {
                    throw HealthError("备份事项索引与内容不一致 / Archived event index mismatch")
                }
            }
        }
    }
}
