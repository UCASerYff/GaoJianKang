import Foundation
import SQLite3
import CryptoKit

struct BackupEnvelope: Codable {
    var version = 1
    var appVersion = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.7"
    var createdAt = Date()
    var payload: Data
    var sha256: String
}
/// Storage layout: one core JSON blob (island, preferences, ledgers, templates…)
/// plus row-per-entry `records` / `events` tables so daily writes stay incremental.
/// PRAGMA user_version 0 = legacy single-blob layout, 1 = split layout.
final class HealthDatabase {
    static let groupID = "5G96498KGJ.com.gaoseries.GaoJianKang"
    let directory: URL
    private var db: OpaquePointer?
    static func location() throws -> URL {
        if let override = ProcessInfo.processInfo.environment["GAOJIANKANG_TEST_DIRECTORY"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        guard let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier:groupID) else { throw HealthError("无法访问共享容器，请重新安装已签名版本 / Shared container unavailable") }
        return group.appendingPathComponent("Health",isDirectory:true)
    }
    init(directory: URL? = nil) throws {
        self.directory = try directory ?? Self.location()
        try FileManager.default.createDirectory(at:self.directory,withIntermediateDirectories:true)
        let url = self.directory.appendingPathComponent("health.sqlite")
        guard sqlite3_open_v2(url.path,&db,SQLITE_OPEN_CREATE|SQLITE_OPEN_READWRITE|SQLITE_OPEN_FULLMUTEX,nil)==SQLITE_OK else { throw HealthError("无法打开本地数据库 / Cannot open database") }
        sqlite3_busy_timeout(db,5000)
        try execute("PRAGMA journal_mode=WAL")
        try execute("PRAGMA synchronous=FULL")
        try execute("CREATE TABLE IF NOT EXISTS state (id INTEGER PRIMARY KEY CHECK(id=1), json BLOB NOT NULL)")
        try execute("CREATE TABLE IF NOT EXISTS records (id TEXT PRIMARY KEY, kind TEXT NOT NULL, occurred_at REAL NOT NULL, json BLOB NOT NULL)")
        try execute("CREATE TABLE IF NOT EXISTS events (id TEXT PRIMARY KEY, type_id TEXT NOT NULL, occurred_at REAL NOT NULL, json BLOB NOT NULL)")
        try execute("BEGIN IMMEDIATE")
        do {
            var st: OpaquePointer?
            guard sqlite3_prepare_v2(db,"SELECT count(*) FROM state",-1,&st,nil)==SQLITE_OK else { throw error() }
            let count = sqlite3_step(st)==SQLITE_ROW ? sqlite3_column_int(st,0) : -1
            sqlite3_finalize(st)
            if count == 0 {
                try write(HealthState())
                try execute("PRAGMA user_version = 1")
            } else if count != 1 { throw error() }
            else if try intPragma("user_version") == 0 {
                // Legacy single-blob layout: split records/events into their tables once; never touch attachment folders.
                let legacy = try decodeState(readBlob())
                try syncRecords(old:[],new:legacy.records)
                try syncEvents(old:[],new:legacy.events)
                try writeBlob(core(legacy))
                try execute("PRAGMA user_version = 1")
            } else {
                try writeBlob(core(decodeState(readBlob()))) // Normalize any older core JSON in place.
            }
            try execute("COMMIT")
        } catch { try? execute("ROLLBACK"); throw error }
    }
    deinit { sqlite3_close(db) }
    private func error() -> HealthError { HealthError("数据库操作失败 / Database error: \(String(cString:sqlite3_errmsg(db)))") }
    private func execute(_ sql: String) throws { guard sqlite3_exec(db,sql,nil,nil,nil)==SQLITE_OK else { throw error() } }
    private func intPragma(_ name: String) throws -> Int {
        var st: OpaquePointer?
        guard sqlite3_prepare_v2(db,"PRAGMA \(name)",-1,&st,nil)==SQLITE_OK else { throw error() }
        defer { sqlite3_finalize(st) }
        return sqlite3_step(st)==SQLITE_ROW ? Int(sqlite3_column_int(st,0)) : 0
    }
    /// Core state = everything except the row-based collections.
    private func core(_ state: HealthState) -> HealthState { var c = state; c.records = []; c.events = []; return c }
    private func decodeState(_ data: Data) throws -> HealthState {
        do { return try JSONDecoder().decode(HealthState.self,from:data) }
        catch { throw HealthError("存档读取失败，原文件已保留。请从备份恢复。 / Save unreadable; original retained. Restore a backup.\n\(error.localizedDescription)") }
    }
    private func readBlob() throws -> Data {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db,"SELECT json FROM state WHERE id=1",-1,&statement,nil)==SQLITE_OK else { throw error() }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement)==SQLITE_ROW, let ptr = sqlite3_column_blob(statement,0) else { throw error() }
        return Data(bytes:ptr,count:Int(sqlite3_column_bytes(statement,0)))
    }
    private func writeBlob(_ state: HealthState) throws {
        let data = try JSONEncoder().encode(state)
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db,"INSERT OR REPLACE INTO state(id,json) VALUES(1,?)",-1,&statement,nil)==SQLITE_OK else { throw error() }
        defer { sqlite3_finalize(statement) }
        let rc = data.withUnsafeBytes { sqlite3_bind_blob(statement,1,$0.baseAddress,Int32(data.count),unsafeBitCast(-1,to:sqlite3_destructor_type.self)) }
        guard rc==SQLITE_OK && sqlite3_step(statement)==SQLITE_DONE else { throw error() }
    }
    private func bind(_ statement: OpaquePointer?, _ index: Int32, _ text: String) { sqlite3_bind_text(statement,index,text,-1,unsafeBitCast(-1,to:sqlite3_destructor_type.self)) }
    private func bind(_ statement: OpaquePointer?, _ index: Int32, _ blob: Data) {
        _ = blob.withUnsafeBytes { sqlite3_bind_blob(statement,index,$0.baseAddress,Int32(blob.count),unsafeBitCast(-1,to:sqlite3_destructor_type.self)) }
    }
    private func loadRows(_ table: String) throws -> [Data] {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db,"SELECT json FROM \(table)",-1,&statement,nil)==SQLITE_OK else { throw error() }
        defer { sqlite3_finalize(statement) }
        var rows: [Data] = []
        while sqlite3_step(statement)==SQLITE_ROW {
            guard let ptr = sqlite3_column_blob(statement,0) else { throw error() }
            rows.append(Data(bytes:ptr,count:Int(sqlite3_column_bytes(statement,0))))
        }
        return rows
    }
    private func upsertRow(_ table: String, id: String, owner: String, occurredAt: Date, json: Data) throws {
        var statement: OpaquePointer?
        let ownerColumn = table == "records" ? "kind" : "type_id"
        guard sqlite3_prepare_v2(db,"INSERT OR REPLACE INTO \(table)(id,\(ownerColumn),occurred_at,json) VALUES(?,?,?,?)",-1,&statement,nil)==SQLITE_OK else { throw error() }
        defer { sqlite3_finalize(statement) }
        bind(statement,1,id); bind(statement,2,owner)
        sqlite3_bind_double(statement,3,occurredAt.timeIntervalSince1970)
        bind(statement,4,json)
        guard sqlite3_step(statement)==SQLITE_DONE else { throw error() }
    }
    private func deleteRow(_ table: String, id: String) throws {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db,"DELETE FROM \(table) WHERE id=?",-1,&statement,nil)==SQLITE_OK else { throw error() }
        defer { sqlite3_finalize(statement) }
        bind(statement,1,id)
        guard sqlite3_step(statement)==SQLITE_DONE else { throw error() }
    }
    private func syncRecords(old: [HealthRecord], new: [HealthRecord]) throws {
        let oldStamps = Dictionary(old.map { ($0.id,$0.updatedAt) }, uniquingKeysWith: { a,_ in a })
        let newIDs = Set(new.map(\.id))
        for record in new where oldStamps[record.id] != record.updatedAt {
            try upsertRow("records",id:record.id.uuidString,owner:record.kind.rawValue,occurredAt:record.occurredAt,json:JSONEncoder().encode(record))
        }
        for record in old where !newIDs.contains(record.id) { try deleteRow("records",id:record.id.uuidString) }
    }
    private func syncEvents(old: [HealthEvent], new: [HealthEvent]) throws {
        let oldData = Dictionary(old.map { ($0.id,(try? JSONEncoder().encode($0)) ?? Data()) }, uniquingKeysWith: { a,_ in a })
        let newIDs = Set(new.map(\.id))
        for event in new {
            let data = try JSONEncoder().encode(event)
            if oldData[event.id] != data { try upsertRow("events",id:event.id.uuidString,owner:event.typeID.uuidString,occurredAt:event.occurredAt,json:data) }
        }
        for event in old where !newIDs.contains(event.id) { try deleteRow("events",id:event.id.uuidString) }
    }
    func read() throws -> HealthState {
        var state = try decodeState(readBlob())
        do {
            state.records = try loadRows("records").map { try JSONDecoder().decode(HealthRecord.self,from:$0) }
            state.events = try loadRows("events").map { try JSONDecoder().decode(HealthEvent.self,from:$0) }
            try Engine.validate(state); return state
        } catch {
            throw HealthError("存档读取失败，原文件已保留。请从备份恢复。 / Save unreadable; original retained. Restore a backup.\n\(error.localizedDescription)")
        }
    }
    private func write(_ state: HealthState, previous: HealthState? = nil) throws {
        try writeBlob(core(state))
        if previous == nil { try execute("DELETE FROM records"); try execute("DELETE FROM events") }
        try syncRecords(old:previous?.records ?? [],new:state.records)
        try syncEvents(old:previous?.events ?? [],new:state.events)
    }
    @discardableResult func transaction(request: String? = nil,now: Date = Date(),_ operation: (inout HealthState) throws -> Void) throws -> HealthState {
        try execute("BEGIN IMMEDIATE")
        do {
            var state = try read()
            let previous = state
            if let request, state.requests.contains(request) { try execute("COMMIT"); return state }
            try operation(&state)
            if let request { state.requests.insert(request) }
            try Engine.validate(state)
            state.updatedAt = now
            try write(state,previous:previous); try execute("COMMIT"); return state
        } catch { try? execute("ROLLBACK"); throw error }
    }
    func backupData(_ state: HealthState) throws -> Data {
        let payload = try JSONEncoder().encode(state)
        let hash = SHA256.hash(data:payload).map { String(format:"%02x",$0) }.joined()
        return try JSONEncoder().encode(BackupEnvelope(payload:payload,sha256:hash))
    }
    static func decodeBackup(_ data: Data) throws -> (HealthState,Date) {
        guard data.count<100_000_000 else { throw HealthError("备份文件过大 / Backup too large") }
        let backup = try JSONDecoder().decode(BackupEnvelope.self,from:data)
        let hash = SHA256.hash(data:backup.payload).map { String(format:"%02x",$0) }.joined()
        guard backup.version==1 && backup.sha256==hash else { throw HealthError("备份版本或校验不匹配 / Backup checksum or version mismatch") }
        let state = try JSONDecoder().decode(HealthState.self,from:backup.payload)
        try Engine.validate(state)
        return (state,backup.createdAt)
    }
    func automaticBackup() throws {
        // A consistent read snapshot; a failed backup never changes health records.
        let state = try read(); let day = Engine.day(Date(),state)
        let folder = directory.appendingPathComponent("Backups")
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        let target = folder.appendingPathComponent("daily-\(day).healthbackup")
        guard !FileManager.default.fileExists(atPath:target.path) else { return }
        try backupData(state).write(to:target,options:.atomic)
        let daily = try FileManager.default.contentsOfDirectory(at:folder,includingPropertiesForKeys:nil).filter { $0.lastPathComponent.hasPrefix("daily-") }.sorted { $0.lastPathComponent > $1.lastPathComponent }
        for file in daily.dropFirst(7) { try FileManager.default.removeItem(at:file) }
    }
    func restore(_ state: HealthState) throws {
        try Engine.validate(state)
        try execute("BEGIN IMMEDIATE")
        do {
            // Preserve the original database even if its JSON cannot be decoded.
            let rescue = directory.appendingPathComponent("Backups",isDirectory:true)
            try FileManager.default.createDirectory(at:rescue,withIntermediateDirectories:true)
            if let current = try? read() {
                try backupData(current).write(to:rescue.appendingPathComponent("before-restore-\(UUID().uuidString).healthbackup"),options:.atomic)
            } else {
                let target = rescue.appendingPathComponent("unreadable-\(UUID().uuidString).sqlite")
                var destination: OpaquePointer?
                guard sqlite3_open(target.path,&destination)==SQLITE_OK else { throw error() }
                defer { sqlite3_close(destination) }
                guard let backup = sqlite3_backup_init(destination,"main",db,"main") else { throw error() }
                let code = sqlite3_backup_step(backup,-1); sqlite3_backup_finish(backup)
                guard code==SQLITE_DONE else { throw error() }
            }
            try write(state,previous:try? read()); try execute("COMMIT")
        } catch { try? execute("ROLLBACK"); throw error }
    }
    func erase() throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try writeBlob(core(HealthState()))
            try execute("DELETE FROM records"); try execute("DELETE FROM events")
            try execute("COMMIT")
        } catch { try? execute("ROLLBACK"); throw error }
        let backups = directory.appendingPathComponent("Backups")
        if FileManager.default.fileExists(atPath:backups.path) { try FileManager.default.removeItem(at:backups) }
        try execute("PRAGMA wal_checkpoint(TRUNCATE)")
        try execute("VACUUM")
    }
}

enum HealthCSV {
    static func cell(_ value: String) -> String {
        var v = value
        if let first = v.trimmingCharacters(in:.whitespacesAndNewlines).first, "=+-@".contains(first) { v = "'" + v }
        return "\"" + v.replacingOccurrences(of:"\"",with:"\"\"") + "\""
    }
    static func export(_ kind: RecordKind,_ records: [HealthRecord]) -> String {
        var rows = [["id","occurred_at","timezone","type","name","amount","unit","kcal","protein_g","carbs_g","fat_g","meal_slot","note","source","meal_source","fullness_percent"]]
        let formatter = ISO8601DateFormatter()
        func value(_ n: Double?) -> String { n.map { String($0) } ?? "" }
        for r in records.filter({ $0.kind==kind }).sorted(by:{ $0.occurredAt<$1.occurredAt }) {
            rows.append([r.id.uuidString,formatter.string(from:r.occurredAt),r.timezone,r.kind.rawValue,r.title,String(r.amount),r.kind == .meal ? r.foodUnit : r.kind.unit,value(r.calories),value(r.protein),value(r.carbs),value(r.fat),r.kind == .meal ? String(r.slot) : "",r.note,r.source,r.mealSource?.rawValue ?? "",r.fullnessPercent.map(String.init) ?? ""])
        }
        return "\u{FEFF}" + rows.map { $0.map(cell).joined(separator:",") }.joined(separator:"\r\n")
    }
    /// Minimal CSV reader for our own export format: BOM tolerant, quoted cells, escaped quotes, LF/CRLF.
    static func parse(_ text: String) -> [[String]] {
        var rows: [[String]] = []
        var row: [String] = []
        var field = ""
        var quoted = false
        var i = text.startIndex
        if i < text.endIndex && text[i] == "\u{FEFF}" { i = text.index(after:i) }
        func endField() { row.append(field); field = "" }
        func endRow() { endField(); rows.append(row); row = [] }
        while i < text.endIndex {
            let ch = text[i]
            if quoted {
                if ch == "\"" {
                    let next = text.index(after:i)
                    if next < text.endIndex && text[next] == "\"" { field.append("\""); i = next } else { quoted = false }
                } else { field.append(ch) }
            } else if ch == "\"" && field.isEmpty { quoted = true }
            else if ch == "," { endField() }
            else if ch == "\r\n" { endRow() } // CRLF is one grapheme cluster in Swift
            else if ch == "\r" { /* swallow; LF ends the row */ }
            else if ch == "\n" { endRow() }
            else { field.append(ch) }
            i = text.index(after:i)
        }
        if !field.isEmpty || !row.isEmpty { endRow() }
        return rows
    }
    /// Import one exported kind file. Rows failing validation are skipped; imported entries never grant rewards.
    static func `import`(_ kind: RecordKind,_ text: String) -> [HealthRecord] {
        let rows = parse(text)
        guard let header = rows.first, let idIndex = header.firstIndex(of:"id") else { return [] }
        func column(_ name: String) -> Int? { header.firstIndex(of:name) }
        let formatter = ISO8601DateFormatter()
        var imported: [HealthRecord] = []
        for row in rows.dropFirst() where row.count > idIndex {
            guard let id = UUID(uuidString:row[idIndex]) else { continue }
            var record = HealthRecord(kind:kind)
            record.id = id
            if let i = column("occurred_at"), i < row.count, let date = formatter.date(from:row[i]) { record.occurredAt = date }
            if let i = column("timezone"), i < row.count, TimeZone(identifier:row[i]) != nil { record.timezone = row[i] }
            if let i = column("name"), i < row.count { record.title = row[i] }
            if let i = column("amount"), i < row.count, let amount = Double(row[i]) { record.amount = amount }
            if let i = column("unit"), i < row.count, kind == .meal, ["serving","g"].contains(row[i]) { record.foodUnit = row[i] }
            func number(_ name: String) -> Double? { guard let i = column(name), i < row.count, !row[i].isEmpty else { return nil }; return Double(row[i]) }
            record.calories = number("kcal"); record.protein = number("protein_g"); record.carbs = number("carbs_g"); record.fat = number("fat_g")
            if let i = column("meal_slot"), i < row.count, let slot = Int(row[i]), kind == .meal { record.slot = slot }
            if let i = column("meal_source"), i < row.count, kind == .meal { record.mealSource = MealSource(rawValue: row[i]) }
            if let i = column("fullness_percent"), i < row.count, kind == .meal { record.fullnessPercent = Int(row[i]) }
            if let i = column("note"), i < row.count { record.note = row[i] }
            record.source = "import"
            record.rewardEligible = false
            guard (try? Engine.validateRecord(record,now:Date())) != nil else { continue }
            imported.append(record)
        }
        return imported
    }
    static func importEvents(_ text: String,state: HealthState) -> [HealthEvent] {
        let rows = parse(text)
        guard let header = rows.first, let idIndex = header.firstIndex(of:"id") else { return [] }
        func column(_ name: String) -> Int? { header.firstIndex(of:name) }
        let formatter = ISO8601DateFormatter()
        var imported: [HealthEvent] = []
        for row in rows.dropFirst() where row.count > idIndex {
            guard let id = UUID(uuidString:row[idIndex]) else { continue }
            var typeID: UUID?
            if let i = column("type_id"), i < row.count, let candidate = UUID(uuidString:row[i]), state.eventTypes.contains(where: { $0.id == candidate }) { typeID = candidate }
            if typeID == nil, let i = column("name"), i < row.count, let match = state.eventTypes.first(where: { $0.name == row[i] || $0.englishName == row[i] }) { typeID = match.id }
            guard let resolved = typeID else { continue }
            var event = HealthEvent(typeID:resolved)
            event.id = id
            if let i = column("occurred_at"), i < row.count, let date = formatter.date(from:row[i]) { event.occurredAt = date }
            if let i = column("count"), i < row.count, let count = Int(row[i]), (1...999).contains(count) { event.count = count }
            if let i = column("note"), i < row.count { event.note = row[i] }
            event.source = "import"
            imported.append(event)
        }
        return imported
    }
}
