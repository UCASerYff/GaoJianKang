import Foundation
import SQLite3

@main struct SharedSleepRegression {
    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("gao-shared-sleep-regression-" + UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let directory = root.appendingPathComponent("normal")
        setenv("GAOSERIES_SLEEP_TEST_DIRECTORY", directory.path, 1)
        let health = try SharedSleepStore()
        let rhythm = try SharedSleepStore(directory: directory)
        try require(SharedSleepStore.location().standardizedFileURL.path == directory.standardizedFileURL.path, "isolated default directory")

        var full = entry("full", day: 10)
        full.healthSource = "watch"
        full.healthGrowthCreditedSeconds = 1200
        full.healthProductionCreditedCycles = 1
        full.manualEntry = true
        full.manualGrowthCreditedSeconds = 1000
        full.manualProductionCreditedCycles = 1
        full.origin = "rhythm"
        full.pastureYield = 3
        try health.seed([full])
        try require(rhythm.records() == [full], "all optional metadata round trips across connections")
        var stale = full
        stale.score = 5
        stale.manualGrowthCreditedSeconds = nil
        try rhythm.seed([stale])
        try require(health.records() == [full], "idempotent legacy seed cannot overwrite canonical record")

        var legacyDuplicate = full
        legacyDuplicate.id = "legacy-same-night"
        try health.seed([legacyDuplicate])
        try require(rhythm.records().count == 2, "legacy import preserves distinct historical IDs")
        var newDuplicate = full
        newDuplicate.id = "new-same-night"
        newDuplicate.startedAt.addTimeInterval(30)
        newDuplicate.endedAt.addTimeInterval(30)
        try expectFailure("new duplicates rejected", matching: { if case SharedSleepError.duplicate = $0 { return true }; return false }) {
            try rhythm.upsert(newDuplicate)
        }

        var edit = full
        edit.score = 92
        edit.healthGrowthCreditedSeconds = nil
        edit.healthProductionCreditedCycles = 0
        edit.manualGrowthCreditedSeconds = 100
        edit.manualProductionCreditedCycles = nil
        edit.pastureYield = 0
        edit.origin = nil
        try health.upsert(edit)
        var expected = full
        expected.score = 92
        try require(rhythm.records().first(where: { $0.id == full.id }) == expected, "stale edits preserve all settled credit metadata")
        var settlement = full
        settlement.pastureYield = 5
        settlement.manualGrowthCreditedSeconds = 2000
        settlement.manualProductionCreditedCycles = 2
        try rhythm.updateRhythmSettlement(settlement)
        expected.pastureYield = 5
        expected.manualGrowthCreditedSeconds = 2000
        expected.manualProductionCreditedCycles = 2
        try require(health.records().first(where: { $0.id == full.id }) == expected, "reward-only update preserves concurrent score edits")

        try health.remove(full.id)
        try rhythm.seed([full])
        try require(!health.records().contains(where: { $0.id == full.id }), "tombstone survives legacy reseed")
        try expectFailure("stale upsert cannot resurrect deletion", matching: { if case SharedSleepError.deleted = $0 { return true }; return false }) { try rhythm.upsert(full) }
        try expectFailure("stale settlement cannot resurrect deletion", matching: { if case SharedSleepError.deleted = $0 { return true }; return false }) { try rhythm.updateRhythmSettlement(full) }
        try health.remove("not-yet-imported")
        try rhythm.seed([entry("not-yet-imported", day: 14)])
        try require(!health.records().contains(where: { $0.id == "not-yet-imported" }), "tombstone prevents later first import")

        let short = entry("short-timer", day: 20, duration: 5)
        let long = entry("long-timer", day: 25, duration: 48 * 3600)
        let zero = entry("zero-timer", day: 30, duration: 0)
        try health.seed([short, long, zero])
        try require(rhythm.records().contains(short) && rhythm.records().contains(long) && rhythm.records().contains(zero), "legacy short, long, and zero-duration timers preserved")
        var future = entry("future", day: 0)
        future.startedAt = Date().addingTimeInterval(3600)
        future.endedAt = future.startedAt.addingTimeInterval(100)
        future.durationSeconds = 100
        try expectFailure("future upsert rejected") { try health.upsert(future) }
        var invalid = entry("invalid", day: 31)
        invalid.durationSeconds = -.infinity
        try expectFailure("invalid batch is atomic") { try health.seed([entry("rollback", day: 32), invalid]) }
        try require(!health.records().contains(where: { $0.id == "rollback" }), "partial seed transaction rolls back")

        try concurrentInserts(root.appendingPathComponent("concurrent"))
        try legacyMigrationChecks(root.appendingPathComponent("migration"))
        try pendingReconciliationChecks(root.appendingPathComponent("pending"))
        try corruptionChecks(root: root)
        print("PASS Shared sleep: cross-app roundtrip; metadata preservation; atomic one-time migration; duplicate/future guards; tombstones; atomic rollback; 40 concurrent writers; corrupt/missing data retained")
    }

    static func entry(_ id: String, day: Int, duration: Double = 8 * 3600) -> SharedSleepEntry {
        let end = Date(timeIntervalSince1970: 1_700_000_000 - Double(day) * 86_400)
        return SharedSleepEntry(id: id, startedAt: end.addingTimeInterval(-duration), endedAt: end, durationSeconds: duration, score: 80, pastureYield: 0)
    }

    static func concurrentInserts(_ directory: URL) throws {
        let errors = Errors()
        DispatchQueue.concurrentPerform(iterations: 40) { index in
            do {
                let store = try SharedSleepStore(directory: directory)
                try store.upsert(entry("concurrent-\(index)", day: 100 + index))
            } catch { errors.add(error) }
        }
        try require(errors.values.isEmpty, "concurrent creation/writes: \(errors.values)")
        try require(SharedSleepStore(directory: directory).records().count == 40, "concurrent writes retain every record")

        let duplicates = Errors()
        DispatchQueue.concurrentPerform(iterations: 10) { index in
            do { try SharedSleepStore(directory: directory).upsert(entry("racing-duplicate-\(index)", day: 200)) }
            catch { duplicates.add(error) }
        }
        try require(duplicates.values.count == 9 && duplicates.values.allSatisfy { if case SharedSleepError.duplicate = $0 { return true }; return false }, "concurrent duplicate prevention is atomic")
        try require(SharedSleepStore(directory: directory).records().count == 41, "one winning concurrent duplicate")
    }

    static func legacyMigrationChecks(_ directory: URL) throws {
        let store = try SharedSleepStore(directory: directory)
        let key = SharedSleepStore.legacyMigrationKey
        try require(!store.hasLegacyMigration(key), "new journal has no legacy import receipt")
        var invalid = entry("invalid-legacy", day: 1)
        invalid.score = -1
        try expectFailure("invalid migration rolls back receipt and rows") { try store.seedLegacyOnce([entry("rollback-legacy", day: 1), invalid], key: key) }
        try require(!store.hasLegacyMigration(key) && store.records().isEmpty, "failed migration remains retryable without partial records")
        let errors = Errors()
        DispatchQueue.concurrentPerform(iterations: 12) { index in
            do {
                let peer = try SharedSleepStore(directory: directory)
                try peer.seedLegacyOnce([entry("migration-winner-\(index)", day: 10), entry("historical-duplicate-\(index)", day: 10)], key: key)
            } catch { errors.add(error) }
        }
        try require(errors.values.isEmpty, "concurrent migration callers succeed")
        try require(store.hasLegacyMigration(key) && store.records().count == 2, "one atomic winning snapshot, including its historical duplicates")
        let before = try store.records()
        try store.seedLegacyOnce([entry("must-not-be-imported", day: 20)], key: key)
        try require(store.records() == before, "repeated migration does not unrestricted-seed new local records")
        let canonical = entry("canonical-new", day: 30)
        try store.upsert(canonical)
        var pending = canonical
        pending.id = "pending-new"
        try store.seedLegacyOnce([pending], key: key)
        try expectFailure("new local record cannot bypass duplicate guard via repeated seed", matching: { if case SharedSleepError.duplicate = $0 { return true }; return false }) {
            try store.upsert(pending)
        }
    }

    static func pendingReconciliationChecks(_ directory: URL) throws {
        let store = try SharedSleepStore(directory: directory)
        var canonical = entry("canonical", day: 1)
        canonical.origin = "health"
        canonical.score = 85
        try store.upsert(canonical)
        var alias = canonical
        alias.id = "offline-alias"
        alias.origin = "rhythm"
        alias.score = 99
        alias.pastureYield = 3
        alias.manualGrowthCreditedSeconds = 8 * 3600
        alias.manualProductionCreditedCycles = 2
        try store.reconcilePending(alias, settlement: alias)
        var expected = canonical
        expected.pastureYield = 3
        expected.manualGrowthCreditedSeconds = 8 * 3600
        expected.manualProductionCreditedCycles = 2
        try require(store.records() == [expected], "pending duplicate transfers only receipts to canonical identity")
        try store.remove(canonical.id)
        try store.reconcilePending(alias, settlement: alias)
        try store.seed([alias])
        try require(store.records().isEmpty, "alias remains deleted after canonical deletion and stale retry/import")
        try expectFailure("alias tombstone blocks direct stale upsert", matching: { if case SharedSleepError.deleted = $0 { return true }; return false }) { try store.upsert(alias) }

        let timer = entry("unique-timer", day: 10)
        var settledTimer = timer
        settledTimer.manualGrowthCreditedSeconds = 8 * 3600
        settledTimer.manualProductionCreditedCycles = 2
        try store.reconcilePending(timer, settlement: settledTimer)
        try require(store.records() == [timer], "unique pending timer preserves original metadata, not alias-only receipts")
        try store.remove(timer.id)
        try store.reconcilePending(timer, settlement: settledTimer)
        try require(store.records().isEmpty, "known deletion wins over pending upload")

        var legacyClock = entry("legacy-clock", day: 1)
        legacyClock.endedAt = Date().addingTimeInterval(86400)
        legacyClock.startedAt = legacyClock.endedAt.addingTimeInterval(-8 * 3600)
        try store.seed([legacyClock])
        try store.remove(legacyClock.id)
        try store.reconcilePending(legacyClock, settlement: legacyClock)
        try require(store.records().isEmpty, "legacy future-clock tombstone still wins over stale upload")
        legacyClock.id = "new-future-clock"
        try expectFailure("genuinely new pending future record rejected") { try store.reconcilePending(legacyClock, settlement: legacyClock) }

        let errors = Errors()
        DispatchQueue.concurrentPerform(iterations: 12) { index in
            do {
                let peer = try SharedSleepStore(directory: directory)
                var pending = entry("racing-pending-\(index)", day: 20)
                pending.manualProductionCreditedCycles = 2
                try peer.reconcilePending(pending, settlement: pending)
            } catch { errors.add(error) }
        }
        try require(errors.values.isEmpty && store.records().count == 1, "concurrent pending duplicates produce one canonical row")
        let winner = try store.records()[0]
        try store.remove(winner.id)
        for index in 0..<12 {
            let pending = entry("racing-pending-\(index)", day: 20)
            try store.reconcilePending(pending, settlement: pending)
        }
        try require(store.records().isEmpty, "all concurrent aliases stay deleted after canonical deletion")
    }

    static func corruptionChecks(root: URL) throws {
        let fm = FileManager.default
        let malformed = root.appendingPathComponent("malformed")
        try fm.createDirectory(at: malformed, withIntermediateDirectories: true)
        let malformedFile = malformed.appendingPathComponent(SharedSleepStore.fileName)
        let malformedBytes = Data("user data that must never become an empty database".utf8)
        try malformedBytes.write(to: malformedFile)
        try expectFailure("malformed preexisting file rejected") { _ = try SharedSleepStore(directory: malformed) }
        try require(Data(contentsOf: malformedFile) == malformedBytes, "malformed file bytes retained")

        let empty = root.appendingPathComponent("empty")
        try fm.createDirectory(at: empty, withIntermediateDirectories: true)
        let emptyFile = empty.appendingPathComponent(SharedSleepStore.fileName)
        try Data().write(to: emptyFile)
        try expectFailure("preexisting empty file rejected") { _ = try SharedSleepStore(directory: empty) }
        try require(Data(contentsOf: emptyFile).isEmpty, "empty preexisting file not initialized")

        let missing = root.appendingPathComponent("missing")
        do { let store = try SharedSleepStore(directory: missing); try store.seed([entry("saved", day: 1)]) }
        try fm.removeItem(at: missing.appendingPathComponent(SharedSleepStore.fileName))
        try expectFailure("missing known database rejected") { _ = try SharedSleepStore(directory: missing) }
        try require(!fm.fileExists(atPath: missing.appendingPathComponent(SharedSleepStore.fileName).path), "missing database not recreated blank")

        let badRow = root.appendingPathComponent("bad-row")
        let store = try SharedSleepStore(directory: badRow)
        try store.seed([entry("protected", day: 1)])
        let file = badRow.appendingPathComponent(SharedSleepStore.fileName)
        try rawSQL(file, "UPDATE sleep_records SET payload=x'7b' WHERE id='protected'")
        try expectFailure("malformed row prevents read") { _ = try store.records() }
        try expectFailure("malformed row prevents seed") { try store.seed([entry("replacement", day: 2)]) }
        try expectFailure("malformed row cannot be overwritten") { try store.upsert(entry("protected", day: 1)) }
        try expectFailure("malformed row cannot be deleted silently") { try store.remove("protected") }
        try expectFailure("malformed row prevents next initialization") { _ = try SharedSleepStore(directory: badRow) }
        try require(rawScalar(file, "SELECT hex(payload) FROM sleep_records WHERE id='protected'") == "7B", "malformed payload preserved byte for byte")
        try require(rawScalar(file, "SELECT count(*) FROM sleep_records") == "1", "failed writes did not add replacement data")

        let missingRow = root.appendingPathComponent("missing-payload")
        do { let initial = try SharedSleepStore(directory: missingRow); try initial.seed([entry("missing", day: 1)]) }
        let missingFile = missingRow.appendingPathComponent(SharedSleepStore.fileName)
        try rawSQL(missingFile, "PRAGMA ignore_check_constraints=ON; UPDATE sleep_records SET payload=NULL WHERE id='missing'")
        try expectFailure("missing active payload rejected") { _ = try SharedSleepStore(directory: missingRow) }
        try require(rawScalar(missingFile, "SELECT count(*) FROM sleep_records WHERE payload IS NULL AND deleted=0") == "1", "missing payload row remains intact")
    }

    static func require(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try condition() else { throw TestFailure(message) }
    }
    static func expectFailure(_ message: String, matching: (Error) -> Bool = { _ in true }, _ work: () throws -> Void) throws {
        do { try work() } catch { if matching(error) { return }; throw TestFailure("\(message): unexpected error \(error)") }
        throw TestFailure("\(message): operation unexpectedly succeeded")
    }
    static func rawSQL(_ file: URL, _ sql: String) throws {
        var db: OpaquePointer?
        guard sqlite3_open_v2(file.path, &db, SQLITE_OPEN_READWRITE, nil) == SQLITE_OK else { throw TestFailure("raw open") }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 10_000)
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else { throw TestFailure(String(cString: sqlite3_errmsg(db))) }
    }
    static func rawScalar(_ file: URL, _ sql: String) throws -> String {
        var db: OpaquePointer?
        guard sqlite3_open_v2(file.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { throw TestFailure("raw read open") }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { throw TestFailure("raw prepare") }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW, let bytes = sqlite3_column_text(statement, 0) else { throw TestFailure("raw scalar") }
        return String(cString: bytes)
    }
    struct TestFailure: Error { let message: String; init(_ message: String) { self.message = message } }
    final class Errors: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [Error] = []
        var values: [Error] { lock.lock(); defer { lock.unlock() }; return stored }
        func add(_ error: Error) { lock.lock(); defer { lock.unlock() }; stored.append(error) }
    }
}
