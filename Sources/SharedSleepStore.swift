import Foundation
import SQLite3
import Darwin

/// Wire format shared by the two independent applications. Keep this file identical in both repos.
/// Reward bookkeeping belongs to Rhythm and survives edits made by Health.
struct SharedSleepEntry: Codable, Equatable, Identifiable {
    var id: String
    var startedAt: Date
    var endedAt: Date
    var durationSeconds: TimeInterval
    var score: Int
    var pastureYield: Int
    var healthSource: String? = nil
    var healthGrowthCreditedSeconds: TimeInterval? = nil
    var healthProductionCreditedCycles: Int? = nil
    var manualEntry: Bool? = nil
    var manualGrowthCreditedSeconds: TimeInterval? = nil
    var manualProductionCreditedCycles: Int? = nil
    var origin: String? = nil
}

enum SharedSleepError: LocalizedError {
    case storage(String)
    case invalidRecord(String)
    case duplicate
    case deleted
    case missing

    var errorDescription: String? {
        switch self {
        case .storage(let reason): return "睡眠同步存档无法读取，原数据已保留 / Sleep sync unavailable; original data retained.\n\(reason)"
        case .invalidRecord(let reason): return "睡眠记录无效 / Invalid sleep record: \(reason)"
        case .duplicate: return "已有相同时间的睡眠记录 / This sleep interval is already recorded."
        case .deleted: return "这条睡眠记录已删除，请刷新列表 / This sleep record was deleted; refresh the list."
        case .missing: return "未找到这条睡眠记录，请刷新列表 / This sleep record is missing; refresh the list."
        }
    }
}

/// One canonical journal, independent of each app's game save. SQL transactions serialize writes
/// across processes; tombstones stop an older app snapshot from re-importing a deleted record.
final class SharedSleepStore {
    static let groupID = "5G96498KGJ.com.gaoseries.GaoJianKang"
    static let changedNotification = Notification.Name("GaoSeries.sleep.changed")
    static let fileName = "sleep-records.sqlite"
    static let legacyMigrationKey = "rhythm-library-v1"
    let directory: URL
    private var db: OpaquePointer?
    private let connectionLock = NSRecursiveLock()

    static func location() throws -> URL {
        if let override = ProcessInfo.processInfo.environment["GAOSERIES_SLEEP_TEST_DIRECTORY"] {
            guard !override.isEmpty else { throw SharedSleepError.storage("Empty test directory") }
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        guard let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupID) else {
            throw SharedSleepError.storage("无法访问共享容器，请使用已签名版本 / Signed shared container unavailable")
        }
        return group.appendingPathComponent("SharedSleep", isDirectory: true)
    }

    init(directory: URL? = nil) throws {
        self.directory = try directory ?? Self.location()
        let fm = FileManager.default
        try fm.createDirectory(at: self.directory, withIntermediateDirectories: true)
        // This lock only protects first initialization; SQLite handles all record transactions.
        // It also prevents a second launch from mistaking an in-progress new DB for corruption.
        let lockURL = self.directory.appendingPathComponent(".initialization.lock")
        let lockFD = Darwin.open(lockURL.path, O_CREAT | O_RDWR | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard lockFD >= 0 else { throw SharedSleepError.storage("Cannot lock shared sleep directory") }
        defer { _ = flock(lockFD, LOCK_UN); _ = Darwin.close(lockFD) }
        guard flock(lockFD, LOCK_EX) == 0 else { throw SharedSleepError.storage("Cannot lock shared sleep directory") }

        let url = self.directory.appendingPathComponent(Self.fileName)
        let marker = self.directory.appendingPathComponent(".initialized")
        let exists = fm.fileExists(atPath: url.path)
        if !exists {
            guard !fm.fileExists(atPath: marker.path),
                  !fm.fileExists(atPath: url.path + "-wal"),
                  !fm.fileExists(atPath: url.path + "-shm") else {
                throw SharedSleepError.storage("Shared sleep database is missing; restore the existing backup")
            }
        } else {
            let attributes = try fm.attributesOfItem(atPath: url.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                  (attributes[.size] as? NSNumber)?.intValue ?? 0 > 0,
                  fm.isReadableFile(atPath: url.path) else {
                throw SharedSleepError.storage("Existing shared sleep database is empty, unreadable, or not a regular file")
            }
        }

        let flags = SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX | (exists ? 0 : SQLITE_OPEN_CREATE)
        guard sqlite3_open_v2(url.path, &db, flags, nil) == SQLITE_OK else {
            let failure = sqlError()
            sqlite3_close(db); db = nil
            throw failure
        }
        do {
            guard sqlite3_busy_timeout(db, 10_000) == SQLITE_OK else { throw sqlError() }
            if exists {
                // Do not CREATE TABLE IF NOT EXISTS over a malformed or unrelated existing DB.
                try verifySchema()
                _ = try readRows()
            } else {
                try transaction {
                    try execute("CREATE TABLE sleep_metadata (id INTEGER PRIMARY KEY CHECK(id=1), version INTEGER NOT NULL)")
                    try execute("INSERT INTO sleep_metadata(id,version) VALUES(1,1)")
                    try execute("CREATE TABLE sleep_records (id TEXT PRIMARY KEY NOT NULL, payload BLOB, deleted INTEGER NOT NULL CHECK(deleted IN (0,1)), CHECK(deleted=1 OR payload IS NOT NULL))")
                    try execute("PRAGMA user_version=1")
                }
            }
            // A schema-1 journal from an earlier build may predate migration receipts.
            // Existing records were validated above; this additive table cannot replace them.
            try execute("CREATE TABLE IF NOT EXISTS sleep_migrations (key TEXT PRIMARY KEY NOT NULL)")
            try execute("PRAGMA journal_mode=WAL")
            try execute("PRAGMA synchronous=FULL")
            if !fm.fileExists(atPath: marker.path) {
                try Data("SharedSleep schema 1\n".utf8).write(to: marker, options: .atomic)
            }
        } catch {
            sqlite3_close(db); db = nil
            throw error
        }
    }

    deinit { sqlite3_close(db) }

    func records() throws -> [SharedSleepEntry] {
        connectionLock.lock(); defer { connectionLock.unlock() }
        return try readRows().compactMap { $0.value }.sorted {
            $0.endedAt == $1.endedAt ? $0.id < $1.id : $0.endedAt > $1.endedAt
        }
    }

    func hasLegacyMigration(_ key: String) throws -> Bool {
        connectionLock.lock(); defer { connectionLock.unlock() }
        return try migrationExists(key)
    }

    /// Both applications use the same source key. Only the first verified historical snapshot
    /// receives the lossless import exception; subsequent new records must pass strict upsert.
    /// A caller with a missing/unreadable source must not mark migration as complete.
    func seedLegacyOnce(_ entries: [SharedSleepEntry], key: String) throws {
        var changed = false
        connectionLock.lock()
        do {
            try transaction {
                guard try !migrationExists(key) else { return }
                var rows = try readRows()
                for entry in entries {
                    try validate(entry, preventFuture: false)
                    guard rows[entry.id] == nil else { continue }
                    try write(entry)
                    rows[entry.id] = .some(entry)
                }
                let statement = try prepare("INSERT INTO sleep_migrations(key) VALUES(?)")
                defer { sqlite3_finalize(statement) }
                try bind(key, to: statement, at: 1)
                guard sqlite3_step(statement) == SQLITE_DONE else { throw sqlError() }
                changed = true
            }
        } catch { connectionLock.unlock(); throw error }
        connectionLock.unlock()
        if changed { postChange() }
    }

    /// Lossless legacy import: preserve distinct historical IDs even if their times overlap.
    /// Existing canonical values and deletion tombstones always win over a legacy app snapshot.
    func seed(_ entries: [SharedSleepEntry]) throws {
        var changed = false
        connectionLock.lock()
        do {
            try transaction {
                var rows = try readRows()
                for entry in entries {
                    try validate(entry, preventFuture: false)
                    guard rows[entry.id] == nil else { continue }
                    try write(entry)
                    rows[entry.id] = .some(entry)
                    changed = true
                }
            }
        } catch { connectionLock.unlock(); throw error }
        connectionLock.unlock()
        if changed { postChange() }
    }

    /// Existing credit counters cannot decrease when an app saves a stale record copy.
    func upsert(_ entry: SharedSleepEntry) throws {
        try validate(entry, preventFuture: true)
        var changed = false
        connectionLock.lock()
        do {
            try transaction {
                let rows = try readRows()
                var updated = entry
                if let stored = rows[entry.id] {
                    guard let existing = stored else { throw SharedSleepError.deleted }
                    updated = mergeCredits(from: existing, into: entry)
                    if updated.healthSource == nil { updated.healthSource = existing.healthSource }
                    if updated.manualEntry == nil { updated.manualEntry = existing.manualEntry }
                    if updated.origin == nil { updated.origin = existing.origin }
                    guard updated != existing else { return }
                } else if rows.values.compactMap({ $0 }).contains(where: {
                    abs($0.startedAt.timeIntervalSince(entry.startedAt)) <= 60 &&
                    abs($0.endedAt.timeIntervalSince(entry.endedAt)) <= 60
                }) {
                    throw SharedSleepError.duplicate
                }
                try write(updated)
                changed = true
            }
        } catch { connectionLock.unlock(); throw error }
        connectionLock.unlock()
        if changed { postChange() }
    }

    /// A settlement must not overwrite a concurrent edit or resurrect a concurrently deleted row.
    func updateRhythmSettlement(_ entry: SharedSleepEntry) throws {
        try validate(entry, preventFuture: false)
        var changed = false
        connectionLock.lock()
        do {
            try transaction {
                let rows = try readRows()
                guard let stored = rows[entry.id] else { throw SharedSleepError.missing }
                guard let existing = stored else { throw SharedSleepError.deleted }
                let updated = mergeCredits(from: entry, into: existing)
                guard updated != existing else { return }
                try write(updated)
                changed = true
            }
        } catch { connectionLock.unlock(); throw error }
        connectionLock.unlock()
        if changed { postChange() }
    }

    /// Reconcile a locally persisted record that has not yet reached the shared journal.
    /// Duplicate lookup, receipt transfer and alias tombstone must be one transaction: a peer
    /// deletion between separate lookup/write calls could otherwise resurrect the alias.
    /// `settlement` may additionally describe timer rewards already earned in real time;
    /// these extra manual receipts are applied only when aliasing an existing record.
    func reconcilePending(_ entry: SharedSleepEntry, settlement: SharedSleepEntry) throws {
        try validate(entry, preventFuture: false)
        try validate(settlement, preventFuture: false)
        guard entry.id == settlement.id else { throw SharedSleepError.invalidRecord("Settlement ID must match pending record") }
        var changed = false
        connectionLock.lock()
        do {
            try transaction {
                let rows = try readRows()
                // Both active records and tombstones beat an older local snapshot.
                guard rows[entry.id] == nil else { return }
                if let existing = rows.values.compactMap({ $0 }).sorted(by: { $0.id < $1.id }).first(where: {
                    abs($0.startedAt.timeIntervalSince(entry.startedAt)) <= 60 &&
                    abs($0.endedAt.timeIntervalSince(entry.endedAt)) <= 60
                }) {
                    let updated = mergeCredits(from: settlement, into: existing)
                    if updated != existing { try write(updated) }
                    // A future stale local backup of this identity can never recreate it,
                    // even after the canonical record has subsequently been deleted.
                    try writeTombstone(entry.id)
                } else {
                    try validate(entry, preventFuture: true)
                    try write(entry)
                }
                changed = true
            }
        } catch { connectionLock.unlock(); throw error }
        connectionLock.unlock()
        if changed { postChange() }
    }

    func remove(_ id: String) throws {
        guard !id.isEmpty, !id.contains("\0") else { throw SharedSleepError.invalidRecord("Empty record ID") }
        var changed = false
        connectionLock.lock()
        do {
            try transaction {
                let rows = try readRows()
                if let stored = rows[id], stored == nil { return }
                try writeTombstone(id)
                changed = true
            }
        } catch { connectionLock.unlock(); throw error }
        connectionLock.unlock()
        if changed { postChange() }
    }

    private func mergeCredits(from source: SharedSleepEntry, into target: SharedSleepEntry) -> SharedSleepEntry {
        var result = target
        result.pastureYield = max(source.pastureYield, target.pastureYield)
        result.healthGrowthCreditedSeconds = maximum(source.healthGrowthCreditedSeconds, target.healthGrowthCreditedSeconds)
        result.healthProductionCreditedCycles = maximum(source.healthProductionCreditedCycles, target.healthProductionCreditedCycles)
        result.manualGrowthCreditedSeconds = maximum(source.manualGrowthCreditedSeconds, target.manualGrowthCreditedSeconds)
        result.manualProductionCreditedCycles = maximum(source.manualProductionCreditedCycles, target.manualProductionCreditedCycles)
        return result
    }

    private func maximum<T: Comparable>(_ a: T?, _ b: T?) -> T? {
        switch (a, b) { case (.some(let x), .some(let y)): return max(x,y); case (.some(let x), nil): return x; case (nil, .some(let y)): return y; case (nil,nil): return nil }
    }

    private func validate(_ entry: SharedSleepEntry, preventFuture: Bool) throws {
        guard !entry.id.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !entry.id.contains("\0"),
              entry.startedAt.timeIntervalSince1970.isFinite, entry.endedAt.timeIntervalSince1970.isFinite,
              entry.endedAt >= entry.startedAt, entry.durationSeconds.isFinite, entry.durationSeconds >= 0,
              entry.pastureYield >= 0, (0...100).contains(entry.score) else {
            throw SharedSleepError.invalidRecord("Invalid ID, times, duration, score, or yield")
        }
        for seconds in [entry.healthGrowthCreditedSeconds, entry.manualGrowthCreditedSeconds].compactMap({ $0 }) {
            guard seconds.isFinite, seconds >= 0 else { throw SharedSleepError.invalidRecord("Invalid reward duration") }
        }
        for cycles in [entry.healthProductionCreditedCycles, entry.manualProductionCreditedCycles].compactMap({ $0 }) {
            guard cycles >= 0 else { throw SharedSleepError.invalidRecord("Invalid reward cycles") }
        }
        if preventFuture, entry.endedAt > Date().addingTimeInterval(1) {
            throw SharedSleepError.invalidRecord("起床时间不能在未来 / Wake time cannot be in the future")
        }
    }

    /// The optional value represents a tombstone; presence of its key still prevents reseeding.
    private func readRows() throws -> [String: SharedSleepEntry?] {
        let statement = try prepare("SELECT id,payload,deleted FROM sleep_records")
        defer { sqlite3_finalize(statement) }
        var rows: [String: SharedSleepEntry?] = [:]
        while true {
            let result = sqlite3_step(statement)
            if result == SQLITE_DONE { break }
            guard result == SQLITE_ROW else { throw sqlError() }
            guard sqlite3_column_type(statement, 0) == SQLITE_TEXT,
                  let idBytes = sqlite3_column_text(statement, 0),
                  let id = String(data: Data(bytes: idBytes, count: Int(sqlite3_column_bytes(statement, 0))), encoding: .utf8),
                  !id.isEmpty, !id.contains("\0"), sqlite3_column_type(statement, 2) == SQLITE_INTEGER else {
                throw SharedSleepError.storage("Malformed sleep row identity")
            }
            let deleted = sqlite3_column_int(statement, 2)
            guard deleted == 0 || deleted == 1, rows[id] == nil else { throw SharedSleepError.storage("Malformed or duplicate sleep row") }
            if deleted == 1 {
                rows[id] = .some(nil)
                continue
            }
            guard sqlite3_column_type(statement, 1) == SQLITE_BLOB,
                  let bytes = sqlite3_column_blob(statement, 1), sqlite3_column_bytes(statement, 1) > 0 else {
                throw SharedSleepError.storage("Sleep payload is missing")
            }
            let data = Data(bytes: bytes, count: Int(sqlite3_column_bytes(statement, 1)))
            let entry: SharedSleepEntry
            do { entry = try JSONDecoder().decode(SharedSleepEntry.self, from: data); try validate(entry, preventFuture: false) }
            catch { throw SharedSleepError.storage("Sleep record \(id) is unreadable: \(error.localizedDescription)") }
            guard entry.id == id else { throw SharedSleepError.storage("Sleep payload ID does not match its row") }
            rows[id] = .some(entry)
        }
        return rows
    }

    private func write(_ entry: SharedSleepEntry) throws {
        let payload = try JSONEncoder().encode(entry)
        let statement = try prepare("INSERT INTO sleep_records(id,payload,deleted) VALUES(?,?,0) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload,deleted=0")
        defer { sqlite3_finalize(statement) }
        try bind(entry.id, to: statement, at: 1)
        let bound = payload.withUnsafeBytes { sqlite3_bind_blob(statement, 2, $0.baseAddress, Int32(payload.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
        guard bound == SQLITE_OK, sqlite3_step(statement) == SQLITE_DONE else { throw sqlError() }
    }

    private func writeTombstone(_ id: String) throws {
        let statement = try prepare("INSERT INTO sleep_records(id,payload,deleted) VALUES(?,NULL,1) ON CONFLICT(id) DO UPDATE SET payload=NULL, deleted=1")
        defer { sqlite3_finalize(statement) }
        try bind(id, to: statement, at: 1)
        guard sqlite3_step(statement) == SQLITE_DONE else { throw sqlError() }
    }

    private func migrationExists(_ key: String) throws -> Bool {
        guard !key.isEmpty, !key.contains("\0") else { throw SharedSleepError.storage("Invalid migration key") }
        let statement = try prepare("SELECT key FROM sleep_migrations WHERE key=?")
        defer { sqlite3_finalize(statement) }
        try bind(key, to: statement, at: 1)
        let step = sqlite3_step(statement)
        if step == SQLITE_DONE { return false }
        guard step == SQLITE_ROW, sqlite3_column_type(statement, 0) == SQLITE_TEXT,
              sqlite3_step(statement) == SQLITE_DONE else { throw sqlError() }
        return true
    }

    private func verifySchema() throws {
        let check = try prepare("PRAGMA quick_check")
        defer { sqlite3_finalize(check) }
        guard sqlite3_step(check) == SQLITE_ROW, let text = sqlite3_column_text(check, 0),
              String(cString: text) == "ok", sqlite3_step(check) == SQLITE_DONE else { throw SharedSleepError.storage("SQLite integrity check failed") }
        let schema = try prepare("SELECT version FROM sleep_metadata WHERE id=1")
        defer { sqlite3_finalize(schema) }
        guard sqlite3_step(schema) == SQLITE_ROW, sqlite3_column_type(schema, 0) == SQLITE_INTEGER,
              sqlite3_column_int(schema, 0) == 1, sqlite3_step(schema) == SQLITE_DONE else {
            throw SharedSleepError.storage("Unsupported or missing sleep database schema")
        }
    }

    private func transaction(_ work: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do { try work(); try execute("COMMIT") }
        catch { try? execute("ROLLBACK"); throw error }
    }
    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let result = statement else { throw sqlError() }
        return result
    }
    private func execute(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw sqlError() }
    }
    private func bind(_ text: String, to statement: OpaquePointer, at index: Int32) throws {
        guard sqlite3_bind_text(statement, index, text, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self)) == SQLITE_OK else { throw sqlError() }
    }
    private func sqlError() -> SharedSleepError {
        .storage(db.map { String(cString: sqlite3_errmsg($0)) } ?? "Cannot open shared sleep database")
    }
    private func postChange() {
        DistributedNotificationCenter.default().postNotificationName(Self.changedNotification, object: nil, userInfo: nil, deliverImmediately: true)
    }
}
