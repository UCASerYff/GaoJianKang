import Foundation
import CryptoKit
import Darwin
#if canImport(WidgetKit)
import WidgetKit
#endif

/// These clocks describe different facts. None is an observation of the desktop.
struct HealthWidgetSnapshot: Codable {
    var state: HealthState
    var revision: String
    var sourceUpdatedAt: Date
    var generatedAt: Date
    var readAt: Date
    var latestRecordAt: Date?
}

struct HealthWidgetReadResult {
    var snapshot: HealthWidgetSnapshot?
    var attemptedAt: Date
    var error: String?
    var isStale: Bool
}

enum HealthWidgetData {
    static let kinds = ["GaoJianKangWidget", "GaoJianKangQuickEvents"]
    static let cacheFileName = "WidgetSnapshot-v1.json"
    static let pendingFileName = ".widget-refresh-pending"
    static let diagnosticsFileName = "WidgetDiagnostics-v1.json"

    private struct Envelope: Codable {
        var version = 1
        var payload: Data
        var sha256: String
    }
    private struct Diagnostic: Codable {
        var kind: String
        var requestedAt: Date
        var status: String
        var revision: String?
        var sourceUpdatedAt: Date?
        var generatedAt: Date?
        var readAt: Date?
        var latestRecordAt: Date?
        var recordCount: Int?
        var eventCount: Int?
        var plannedEntryCount: Int?
        var firstPlannedEntryAt: Date?
        var lastPlannedEntryAt: Date?
    }

    static func load(directory: URL? = nil, now: Date = Date(), kind: String = "diagnostic") -> HealthWidgetReadResult {
        let loaded = read(directory: directory, now: now, synchronizeSleep: true)
        if loaded.recoveredPending, let directory = loaded.directory { announce(directory: directory) }
        recordDiagnostic(kind: kind, result: loaded.result, dates: nil, directory: loaded.directory)
        return loaded.result
    }

    /// Called after COMMIT, never during a DB transaction. This path must not
    /// call the sleep bridge, because that bridge may itself commit a reward.
    static func databaseDidChange(directory: URL, now: Date) {
        markPending(directory: directory)
        let loaded = read(directory: directory, now: now, synchronizeSleep: false)
        recordDiagnostic(kind: "database-commit", result: loaded.result, dates: nil, directory: directory)
        // Even when cache publication fails, peers can reread the committed DB.
        // The marker remains until a later successful publication retries it.
        announce(directory: directory)
    }

    static func requestRefresh(directory: URL? = nil, now: Date = Date()) {
        let loaded = read(directory: directory, now: now, synchronizeSleep: false)
        recordDiagnostic(kind: "manual-refresh", result: loaded.result, dates: nil, directory: loaded.directory)
        if let directory = loaded.directory { announce(directory: directory) }
    }

    /// App polling only publishes when a commit was not yet reflected in cache.
    /// Unchanged data therefore does not become a periodic WidgetKit reload loop.
    @discardableResult
    static func retryPending(directory: URL, now: Date) -> Bool {
        let pending = FileManager.default.fileExists(atPath: directory.appendingPathComponent(pendingFileName).path)
        do {
            let source = try HealthDatabase(directory: directory, access: .readOnlyExisting).readVersioned()
            let cached = try? readCache(directory: directory)
            guard pending || cached?.revision != source.revision else { return false }
            // A retry is not a new business commit. Failed publication must not
            // notify peers, otherwise their read/retry path can create a loop.
            let loaded = read(directory: directory, now: now, synchronizeSleep: false)
            recordDiagnostic(kind: "publication-retry", result: loaded.result, dates: nil, directory: directory)
            guard loaded.result.snapshot != nil, !loaded.result.isStale, loaded.result.error == nil else { return false }
            announce(directory: directory)
            return true
        } catch {
            // Preserve the pending marker and last verified cache until recovery.
            return false
        }
    }

    /// Half-hour entries provide a bounded fallback when WidgetKit delays a new
    /// request. Explicit local midnights also cover DST and calendar month changes.
    static func timelineDates(now: Date, calendar: Calendar) -> [Date] {
        let end = now.addingTimeInterval(48 * 3600)
        var dates = Set((0...96).map { now.addingTimeInterval(Double($0) * 1800) })
        var boundary = calendar.dateInterval(of: .day, for: now)?.end
        while let midnight = boundary, midnight <= end {
            dates.insert(midnight)
            guard let next = calendar.date(byAdding: .day, value: 1, to: midnight), next > midnight else { break }
            boundary = next
        }
        return dates.sorted()
    }

    static func projectedState(_ snapshot: HealthWidgetSnapshot, at date: Date) -> HealthState {
        var state = snapshot.state
        Engine.settle(&state, now: date)
        return state
    }

    /// This is a schedule submitted to WidgetKit, not a measured display time.
    static func recordTimeline(kind: String, result: HealthWidgetReadResult, dates: [Date], directory: URL? = nil) {
        recordDiagnostic(kind: kind, result: result, dates: dates, directory: directory ?? (try? HealthDatabase.location()))
    }

    private static func read(directory: URL?, now: Date, synchronizeSleep: Bool) -> (result: HealthWidgetReadResult, directory: URL?, recoveredPending: Bool) {
        var resolved = directory
        do {
            let folder = try directory ?? HealthDatabase.location()
            resolved = folder
            // An extension must never create a missing health database. Validate
            // the primary source before attempting any optional sleep settlement.
            if synchronizeSleep {
                _ = try HealthDatabase(directory: folder, access: .readOnlyExisting).readVersioned()
            }
            var advisory: String?
            if synchronizeSleep {
                do { _ = try HealthSleepRewardSync.synchronize(directory: folder, now: now) }
                catch { advisory = "睡眠同步待重试，健康资料仍可读取 / Sleep sync will retry; health data remains available." }
            }
            var recoveredPending = false
            let snapshot = try withLock(directory: folder) {
                let source = try HealthDatabase(directory: folder, access: .readOnlyExisting).readVersioned()
                let previous = try? readCache(directory: folder)
                let snapshot = HealthWidgetSnapshot(
                    state: source.state,
                    revision: source.revision,
                    sourceUpdatedAt: source.state.updatedAt,
                    generatedAt: previous?.revision == source.revision ? previous!.generatedAt : now,
                    readAt: now,
                    latestRecordAt: (source.state.records.map(\.occurredAt) + source.state.events.map(\.occurredAt)).max()
                )
                do {
                    try writeCache(snapshot, directory: folder)
                    let pending = folder.appendingPathComponent(pendingFileName)
                    if FileManager.default.fileExists(atPath: pending.path) {
                        try FileManager.default.removeItem(at: pending)
                        recoveredPending = true
                    }
                } catch {
                    markPending(directory: folder)
                    advisory = "已读取健康资料，缓存更新待重试 / Health data was read; cache publication will retry."
                }
                return snapshot
            }
            return (HealthWidgetReadResult(snapshot: snapshot, attemptedAt: now, error: advisory, isStale: false), folder, recoveredPending)
        } catch {
            if let folder = resolved,
               let source = try? HealthDatabase(directory: folder, access: .readOnlyExisting).readVersioned() {
                // Cache-directory permissions must not hide an otherwise valid DB.
                let previous = try? readCache(directory: folder)
                let snapshot = HealthWidgetSnapshot(state: source.state, revision: source.revision,
                    sourceUpdatedAt: source.state.updatedAt,
                    generatedAt: previous?.revision == source.revision ? previous!.generatedAt : now,
                    readAt: now, latestRecordAt: (source.state.records.map(\.occurredAt) + source.state.events.map(\.occurredAt)).max())
                markPending(directory: folder)
                return (HealthWidgetReadResult(snapshot: snapshot, attemptedAt: now,
                    error: "已读取健康资料，缓存更新待重试 / Health data was read; cache publication will retry.", isStale: false), folder, false)
            }
            // Decode only a verified, previously published snapshot. A failed
            // attempt cannot advance its source, generation or successful-read clocks.
            let cached = resolved.flatMap { try? readCache(directory: $0) }
            let message = cached == nil
                ? "健康资料暂不可读取，原资料未改动 / Health data is unavailable; original data is unchanged."
                : "健康资料暂不可读取，显示上次有效资料 / Health data is unavailable; showing the last verified data."
            return (HealthWidgetReadResult(snapshot: cached, attemptedAt: now, error: message, isStale: true), resolved, false)
        }
    }

    private static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    private static func encoder() -> JSONEncoder { let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; return encoder }

    private static func readCache(directory: URL) throws -> HealthWidgetSnapshot {
        let data = try Data(contentsOf: directory.appendingPathComponent(cacheFileName), options: .mappedIfSafe)
        guard data.count <= 100_000_000 else { throw HealthError("Widget cache is too large") }
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        guard envelope.version == 1, digest(envelope.payload) == envelope.sha256 else { throw HealthError("Widget cache checksum/version mismatch") }
        let snapshot = try JSONDecoder().decode(HealthWidgetSnapshot.self, from: envelope.payload)
        try Engine.validate(snapshot.state)
        guard !snapshot.revision.isEmpty,
              snapshot.sourceUpdatedAt == snapshot.state.updatedAt,
              [snapshot.sourceUpdatedAt, snapshot.generatedAt, snapshot.readAt].allSatisfy({ $0.timeIntervalSince1970.isFinite }),
              snapshot.latestRecordAt?.timeIntervalSince1970.isFinite != false else { throw HealthError("Invalid widget cache metadata") }
        return snapshot
    }

    private static func writeCache(_ snapshot: HealthWidgetSnapshot, directory: URL) throws {
        let payload = try encoder().encode(snapshot)
        let data = try encoder().encode(Envelope(payload: payload, sha256: digest(payload)))
        try data.write(to: directory.appendingPathComponent(cacheFileName), options: .atomic)
    }

    private static func markPending(directory: URL) {
        try? Data("Health widget publication pending\n".utf8).write(to: directory.appendingPathComponent(pendingFileName), options: .atomic)
    }

    private static func withLock<T>(directory: URL, _ body: () throws -> T) throws -> T {
        let path = directory.appendingPathComponent(".widget-snapshot.lock").path
        let fd = Darwin.open(path, O_CREAT | O_RDWR | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw HealthError("Widget cache lock unavailable") }
        defer { _ = flock(fd, LOCK_UN); _ = Darwin.close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw HealthError("Widget cache lock unavailable") }
        return try body()
    }

    private static func announce(directory: URL) {
        guard ProcessInfo.processInfo.environment["GAOJIANKANG_TEST_DIRECTORY"] == nil else { return }
        DistributedNotificationCenter.default().postNotificationName(HealthDatabase.changedNotification, object: nil, userInfo: nil, deliverImmediately: true)
#if canImport(WidgetKit)
        for kind in kinds { WidgetCenter.shared.reloadTimelines(ofKind: kind) }
#endif
    }

    private static func recordDiagnostic(kind: String, result: HealthWidgetReadResult, dates: [Date]?, directory: URL?) {
        guard let directory else { return }
        try? withLock(directory: directory) {
            let file = directory.appendingPathComponent(diagnosticsFileName)
            var entries: [Diagnostic] = []
            if let data = try? Data(contentsOf: file), data.count <= 128_000 {
                entries = (try? JSONDecoder().decode([Diagnostic].self, from: data)) ?? []
            }
            let snapshot = result.snapshot
            entries.append(Diagnostic(
                kind: String(kind.prefix(80)), requestedAt: result.attemptedAt,
                status: result.isStale ? (snapshot == nil ? "unavailable" : "cached-source-unavailable") : (result.error == nil ? "source-read" : "source-read-retry-pending"),
                revision: snapshot?.revision, sourceUpdatedAt: snapshot?.sourceUpdatedAt,
                generatedAt: snapshot?.generatedAt, readAt: snapshot?.readAt,
                latestRecordAt: snapshot?.latestRecordAt, recordCount: snapshot?.state.records.count,
                eventCount: snapshot?.state.events.count, plannedEntryCount: dates?.count,
                firstPlannedEntryAt: dates?.first, lastPlannedEntryAt: dates?.last
            ))
            try encoder().encode(Array(entries.suffix(32))).write(to: file, options: .atomic)
        }
    }
}
