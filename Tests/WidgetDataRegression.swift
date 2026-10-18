import Foundation
import SQLite3

/// Isolated tests of the real database and widget data code. No app, WidgetKit host,
/// user defaults, real container, or desktop window is launched by this executable.
@main struct WidgetDataRegression {
    private static let sampleDate = ISO8601DateFormatter().date(from:"2026-10-14T08:00:00+08:00")!
    private static let readDate = ISO8601DateFormatter().date(from:"2026-10-18T12:00:00+08:00")!

    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("health-widget-data-" + UUID().uuidString, isDirectory:true)
        try fm.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? fm.removeItem(at:root) }
        setenv("GAOJIANKANG_TEST_DIRECTORY",root.appendingPathComponent("default").path,1)
        setenv("GAOSERIES_SLEEP_TEST_DIRECTORY",root.appendingPathComponent("absent-shared-sleep").path,1)
        try missingDatabaseSafety(root)
        try malformedDatabaseSafety(root)
        try legacyReadAndMigration(root.appendingPathComponent("legacy"))
        try databaseMutations(root.appendingPathComponent("mutations"))
        try transactionFailures(root.appendingPathComponent("rollback"))
        try consistentConcurrentReads(root.appendingPathComponent("concurrency"))
        try widgetSnapshotTimeChain(root.appendingPathComponent("snapshot"))
        try failedPublicationRetry(root.appendingPathComponent("publication"))
        try widgetCalendarBoundaries(root.appendingPathComponent("calendar"))
        try readOnlySharedSleepRewards(root.appendingPathComponent("sleep-bridge"))
        print("PASS Widget data: real SQLite access modes; missing/corrupt/future schema protection; App/intent CRUD; request idempotency; same-timestamp edits/revisions; rollback; concurrent snapshot consistency; cached failure retention; honest source/read/projection clocks; midnight/month/year/timezone schedules")
    }

    private static func missingDatabaseSafety(_ root: URL) throws {
        let fm = FileManager.default
        for access in [HealthDatabase.Access.readOnlyExisting, .readWriteExisting] {
            let missing = root.appendingPathComponent("missing-\(UUID().uuidString)")
            try expectFailure("existing-only access must reject an absent database") { _ = try HealthDatabase(directory:missing,access:access) }
            try require(!fm.fileExists(atPath:missing.path), "extension access must not CREATE a directory or empty database")
            let result = HealthWidgetData.load(directory:missing,now:readDate,kind:"isolated-unit-test")
            try require(result.snapshot == nil && result.error != nil && !fm.fileExists(atPath:missing.path),
                        "widget helper must report a missing database without creating fallback folders or default data")
        }
        let disappeared = root.appendingPathComponent("disappeared")
        do { _ = try fixtureDatabase(disappeared) }
        let file = disappeared.appendingPathComponent("health.sqlite")
        try fm.removeItem(at:file)
        try expectFailure("lost initialized app database must not become a blank save") { _ = try HealthDatabase(directory:disappeared) }
        try require(!fm.fileExists(atPath:file.path), "application access must preserve missing-database evidence after initialization")
    }

    private static func malformedDatabaseSafety(_ root: URL) throws {
        for scenario in ["future-storage", "future-json", "missing-state", "missing-events", "bad-row", "zero-byte", "not-sqlite"] {
            let directory = root.appendingPathComponent(scenario)
            do {
                let db = try fixtureDatabase(directory)
                _ = try db.transaction(now:sampleDate) { state in
                    try Engine.save(&state,record:makeRecord(.water,at:sampleDate),now:sampleDate)
                    var event = HealthEvent(typeID:state.eventTypes[0].id)
                    event.occurredAt = sampleDate
                    try EventLog.save(&state,event,now:sampleDate)
                }
            }
            let file = directory.appendingPathComponent("health.sqlite")
            switch scenario {
            case "future-storage": try rawSQL(file,"PRAGMA user_version=999")
            case "future-json":
                var object = try JSONSerialization.jsonObject(with:rawBlob(file,"SELECT json FROM state WHERE id=1")) as! [String:Any]
                object["schemaVersion"] = 999
                try rawBlobUpdate(file,JSONSerialization.data(withJSONObject:object),sql:"UPDATE state SET json=? WHERE id=1")
            case "missing-state": try rawSQL(file,"DELETE FROM state")
            case "missing-events": try rawSQL(file,"DROP TABLE events")
            case "bad-row": try rawSQL(file,"UPDATE records SET json=x'7b'")
            case "zero-byte": try Data().write(to:file)
            default: try Data("this is valuable unreadable fixture data".utf8).write(to:file)
            }
            let before = try Data(contentsOf:file)
            for access in [HealthDatabase.Access.readOnlyExisting, .readWriteExisting, .application] {
                try expectFailure("\(scenario) must never be accepted as a new blank save") {
                    let db = try HealthDatabase(directory:directory,access:access)
                    _ = try db.read()
                }
                try require(Data(contentsOf:file) == before, "\(scenario) original database bytes must remain intact after failed access")
            }
            if scenario == "missing-state" {
                try require(rawScalar(file,"SELECT count(*) FROM records") == "1" && rawScalar(file,"SELECT count(*) FROM events") == "1",
                            "missing core must not DELETE surviving record/event tables")
            }
        }

        let directory = root.appendingPathComponent("read-only")
        do { _ = try fixtureDatabase(directory) }
        let file = directory.appendingPathComponent("health.sqlite")
        var object = try JSONSerialization.jsonObject(with:rawBlob(file,"SELECT json FROM state WHERE id=1")) as! [String:Any]
        object["fixtureUnknownField"] = ["preserve":"read-only consumers must not normalize the save"]
        try rawBlobUpdate(file,JSONSerialization.data(withJSONObject:object),sql:"UPDATE state SET json=? WHERE id=1")
        let rawBefore = try rawBlob(file,"SELECT json FROM state WHERE id=1")
        let reader = try HealthDatabase(directory:directory,access:.readOnlyExisting)
        _ = try reader.read()
        try expectFailure("read-only database cannot perform intent writes") { _ = try reader.transaction { $0.preferences.cup = 999 } }
        try require(rawBlob(file,"SELECT json FROM state WHERE id=1") == rawBefore,
                    "read-only access must not rewrite core JSON or strip unknown metadata")
    }

    private static func legacyReadAndMigration(_ directory: URL) throws {
        try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
        let file = directory.appendingPathComponent("health.sqlite")
        var raw: OpaquePointer?
        guard sqlite3_open_v2(file.path,&raw,SQLITE_OPEN_READWRITE|SQLITE_OPEN_CREATE,nil) == SQLITE_OK else { throw FixtureFailure("Cannot create legacy fixture") }
        guard sqlite3_exec(raw,"CREATE TABLE state(id INTEGER PRIMARY KEY,json BLOB NOT NULL); INSERT INTO state VALUES(1,x'00'); PRAGMA user_version=0;",nil,nil,nil) == SQLITE_OK else {
            sqlite3_close(raw); throw FixtureFailure("Cannot create legacy schema")
        }
        sqlite3_close(raw)
        var state = HealthState()
        state.preferences.gameEnabled = false
        state.preferences.timezone = "Asia/Shanghai"
        state.updatedAt = sampleDate
        state.records = [makeRecord(.weight,at:sampleDate)]
        var event = HealthEvent(typeID:state.eventTypes[0].id)
        event.occurredAt = sampleDate
        state.events = [event]
        try rawBlobUpdate(file,JSONEncoder().encode(state),sql:"UPDATE state SET json=? WHERE id=1")
        let before = try Data(contentsOf:file)
        do {
            let reader = try HealthDatabase(directory:directory,access:.readOnlyExisting)
            try require(reader.read().records == state.records && reader.read().events == state.events,
                        "read-only widget must read a valid legacy single-blob snapshot without requiring migration")
        }
        try require(Data(contentsOf:file) == before, "legacy read-only access must not create split tables or rewrite data")
        try expectFailure("extension must not perform legacy database migration") { _ = try HealthDatabase(directory:directory,access:.readWriteExisting) }
        let app = try HealthDatabase(directory:directory)
        try require(app.read().records == state.records && app.read().events == state.events && rawScalar(file,"PRAGMA user_version") == "1",
                    "main App migration must retain legacy records and events in the established database")
    }

    private static func databaseMutations(_ directory: URL) throws {
        let app = try fixtureDatabase(directory)
        let extensionReader = try HealthDatabase(directory:directory,access:.readOnlyExisting)
        let extensionWriter = try HealthDatabase(directory:directory,access:.readWriteExisting)
        let kinds = RecordKind.allCases
        let records = kinds.map { makeRecord($0,at:sampleDate) }
        _ = try app.transaction(now:sampleDate) { state in
            for record in records { try Engine.save(&state,record:record,now:sampleDate) }
            var event = HealthEvent(typeID:state.eventTypes[0].id)
            event.occurredAt = sampleDate
            event.count = 2
            try EventLog.save(&state,event,now:sampleDate)
        }
        var loaded = try extensionReader.read()
        try require(Set(loaded.records.map(\.id)) == Set(records.map(\.id)) && loaded.events.first?.count == 2,
                    "extension reader must see all four App record kinds and quick events")
        let eventID = loaded.events[0].id
        let originalStamp = loaded.records.first { $0.kind == .water }!.updatedAt
        let initialRevision = try extensionReader.readVersioned().revision
        _ = try app.transaction(now:sampleDate) { state in
            for index in state.records.indices { state.records[index].note = "changed-with-same-timestamp" }
            let water = state.records.firstIndex { $0.kind == .water }!
            state.records[water].amount = 375
            state.events[0].count = 5
        }
        loaded = try extensionReader.read()
        try require(extensionReader.readVersioned().revision != initialRevision,
                    "content revision must change when values change even if all timestamps are unchanged")
        try require(loaded.records.allSatisfy { $0.note == "changed-with-same-timestamp" },
                    "record edits must persist even when updatedAt has not changed")
        try require(loaded.records.first { $0.kind == .water }?.amount == 375 &&
                    loaded.records.first { $0.kind == .water }?.updatedAt == originalStamp && loaded.events[0].count == 5,
                    "widget business values must change independently of timestamp changes")

        var waterCalls = 0
        for _ in 0..<2 {
            _ = try extensionWriter.transaction(request:"fixture-water-action",now:readDate) { state in
                waterCalls += 1
                var water = makeRecord(.water,at:readDate)
                water.amount = state.preferences.cup
                water.source = "widget"
                try Engine.save(&state,record:water,now:readDate)
            }
        }
        var eventCalls = 0
        for _ in 0..<2 {
            _ = try extensionWriter.transaction(request:"fixture-event-action",now:readDate) { state in
                eventCalls += 1
                var event = HealthEvent(typeID:state.eventTypes[0].id)
                event.occurredAt = readDate
                event.source = "widget"
                try EventLog.save(&state,event,now:readDate)
            }
        }
        loaded = try app.read()
        try require(waterCalls == 1 && eventCalls == 1 && loaded.records.count == 5 && loaded.events.count == 2,
                    "intent transactions must be visible to App and must not replay the same request")
        try require(loaded.records.filter { $0.source == "widget" }.count == 1 && loaded.events.filter { $0.source == "widget" }.count == 1,
                    "widget writes must preserve provenance while leaving original records intact")
        _ = try extensionWriter.transaction(request:"second-water-action",now:readDate) { state in
            var water = makeRecord(.water,at:readDate)
            water.source = "widget"
            try Engine.save(&state,record:water,now:readDate)
        }
        _ = try extensionWriter.transaction(request:"second-event-action",now:readDate) { state in
            var event = HealthEvent(typeID:state.eventTypes[0].id)
            event.occurredAt = readDate
            event.source = "widget"
            try EventLog.save(&state,event,now:readDate)
        }
        loaded = try app.read()
        try require(loaded.records.count == 6 && loaded.events.count == 3,
                    "distinct intent requests must both count, even at exactly the same time")

        _ = try app.transaction(now:readDate) { state in
            state.records.removeAll { records.map(\.id).contains($0.id) }
            state.events.removeAll { $0.id == eventID }
        }
        loaded = try extensionReader.read()
        try require(loaded.records.count == 2 && loaded.records.allSatisfy { $0.source == "widget" } && loaded.events.count == 2,
                    "App deletes must reach another already-open reader")
        try require(loaded.records[0].occurredAt == readDate && loaded.updatedAt == readDate,
                    "new widget samples carry their real creation time")
    }

    private static func transactionFailures(_ directory: URL) throws {
        let db = try fixtureDatabase(directory)
        let record = makeRecord(.weight,at:sampleDate)
        _ = try db.transaction(now:sampleDate) { try Engine.save(&$0,record:record,now:sampleDate) }
        let before = try canonicalData(db.read())
        try expectFailure("operation error must roll back") {
            _ = try db.transaction(request:"failed-operation",now:readDate) { state in
                state.records.removeAll()
                state.preferences.cup = 999
                throw FixtureFailure("intent failure")
            }
        }
        try require(canonicalData(db.read()) == before, "failed operation must preserve records, preferences, revision and request receipts")
        try expectFailure("validation error must roll back") {
            _ = try db.transaction(request:"failed-validation",now:readDate) { $0.island.energy = -1 }
        }
        try require(canonicalData(db.read()) == before, "failed validation must leave the entire committed snapshot intact")
        _ = try db.transaction(request:"retry-after-failure",now:readDate) { $0.records[0].note = "retry succeeded" }
        try require(db.read().records[0].note == "retry succeeded", "transaction can retry after rollback")
    }

    private static func consistentConcurrentReads(_ directory: URL) throws {
        let writer = try fixtureDatabase(directory)
        _ = try writer.transaction(now:sampleDate) { state in
            state.preferences.cup = 1
            state.records = (0..<40).map { index in
                var record = makeRecord(.water,at:sampleDate)
                record.amount = 1
                record.note = "row \(index)"
                return record
            }
            var event = HealthEvent(typeID:state.eventTypes[0].id)
            event.occurredAt = sampleDate
            event.count = 1
            state.events = [event]
        }
        let failures = Failures()
        let start = DispatchSemaphore(value:0)
        let group = DispatchGroup()
        group.enter()
        DispatchQueue.global().async {
            start.wait()
            do {
                for revision in 2...70 {
                    _ = try writer.transaction(now:sampleDate.addingTimeInterval(Double(revision))) { state in
                        state.preferences.cup = Double(revision)
                        for index in state.records.indices {
                            state.records[index].amount = Double(revision)
                            state.records[index].updatedAt = sampleDate.addingTimeInterval(Double(revision))
                        }
                        state.events[0].count = revision
                    }
                }
            } catch { failures.add(error) }
            group.leave()
        }
        for _ in 0..<3 {
            group.enter()
            DispatchQueue.global().async {
                start.wait()
                do {
                    let reader = try HealthDatabase(directory:directory,access:.readOnlyExisting)
                    for _ in 0..<120 {
                        let state = try reader.read()
                        try require(state.records.count == 40 && state.records.allSatisfy { $0.amount == state.preferences.cup } &&
                                    Double(state.events[0].count) == state.preferences.cup,
                                    "a read must not combine core, record rows and event rows from different commits")
                    }
                } catch { failures.add(error) }
                group.leave()
            }
        }
        for _ in 0..<4 { start.signal() }
        try require(group.wait(timeout:.now()+30) == .success, "isolated concurrent reads and writes must finish")
        try require(failures.values.isEmpty, "concurrency errors: \(failures.values)")
        try require(writer.read().preferences.cup == 70, "all writer commits must be retained")
    }

    private static func widgetSnapshotTimeChain(_ directory: URL) throws {
        let db = try fixtureDatabase(directory)
        let record = makeRecord(.water,at:sampleDate)
        _ = try db.transaction(now:sampleDate) { try Engine.save(&$0,record:record,now:sampleDate) }
        let cache = directory.appendingPathComponent("WidgetSnapshot-v1.json")
        if FileManager.default.fileExists(atPath:cache.path) { try FileManager.default.removeItem(at:cache) }
        let firstResult = HealthWidgetData.load(directory:directory,now:readDate,kind:"isolated-unit-test")
        guard let first = firstResult.snapshot else { throw FixtureFailure("first real widget snapshot unavailable: \(firstResult.error ?? "unknown")") }
        try require(!firstResult.isStale && first.sourceUpdatedAt == sampleDate && first.latestRecordAt == sampleDate,
                    "Oct18 widget read must preserve actual Oct14 business timestamps")
        try require(first.generatedAt == readDate && first.readAt == readDate, "snapshot creation and actual read timestamps must be explicit")
        let laterRead = readDate.addingTimeInterval(600)
        let secondResult = HealthWidgetData.load(directory:directory,now:laterRead,kind:"isolated-unit-test")
        guard let second = secondResult.snapshot else { throw FixtureFailure("repeat widget snapshot unavailable") }
        try require(second.revision == first.revision && second.generatedAt == first.generatedAt && second.readAt == laterRead,
                    "unchanged payload retains its generation time while a successful database read gets a distinct timestamp")
        let projectionDate = readDate.addingTimeInterval(86400)
        let projection = HealthWidgetData.projectedState(second,at:projectionDate)
        try require(projection.updatedAt == sampleDate && projection.records[0].occurredAt == sampleDate,
                    "future timeline projection must not make old samples look newly recorded")
        let stillRaw = try db.readVersioned()
        try require(stillRaw.revision == first.revision && stillRaw.state.updatedAt == sampleDate,
                    "widget projection must not write forecast island values into the real database")

        let file = directory.appendingPathComponent("health.sqlite")
        try rawSQL(file,"UPDATE records SET json=x'7b'")
        let cacheBefore = try Data(contentsOf:cache)
        let failureTime = readDate.addingTimeInterval(1200)
        let failed = HealthWidgetData.load(directory:directory,now:failureTime,kind:"isolated-unit-test")
        guard let retained = failed.snapshot else { throw FixtureFailure("failed database read must retain its last verified widget snapshot") }
        try require(failed.isStale && failed.error != nil && failed.attemptedAt == failureTime,
                    "failed read must be explicit and retain its actual attempted time")
        try require(retained.revision == second.revision && retained.sourceUpdatedAt == sampleDate &&
                    retained.generatedAt == second.generatedAt && retained.readAt == second.readAt && retained.state.records[0] == first.state.records[0],
                    "failure must retain last good content and all source/generation/read timestamps")
        try require(Data(contentsOf:cache) == cacheBefore, "failed database read must not overwrite valid cache with empty/default values")

        // An unverifiable cache is an error, never a plausible empty HealthState.
        let corruptCache = Data("unreadable cache".utf8)
        try corruptCache.write(to:cache)
        let noGoodSource = HealthWidgetData.load(directory:directory,now:failureTime,kind:"isolated-unit-test")
        try require(noGoodSource.snapshot == nil && noGoodSource.error != nil,
                    "broken database plus broken cache must not produce a fake default snapshot")
        try require(Data(contentsOf:cache) == corruptCache, "corrupt cache must be preserved for diagnosis")
    }

    private static func widgetCalendarBoundaries(_ directory: URL) throws {
        let db = try fixtureDatabase(directory)
        let formatter = ISO8601DateFormatter()
        for time in ["2026-10-31T23:50:00+08:00", "2026-12-31T23:50:00+08:00"] {
            let now = formatter.date(from:time)!
            let record = makeRecord(.water,at:now.addingTimeInterval(-120))
            _ = try db.transaction(now:now) { state in
                state.records = [record]
                state.events = []
            }
            let result = HealthWidgetData.load(directory:directory,now:now,kind:"isolated-unit-test")
            guard let snapshot = result.snapshot else { throw FixtureFailure("calendar widget snapshot unavailable") }
            let calendar = Engine.calendar(snapshot.state)
            let midnight = calendar.date(byAdding:.day,value:1,to:calendar.startOfDay(for:now))!
            let dates = HealthWidgetData.timelineDates(now:now,calendar:calendar)
            try require(dates.first == now && dates.contains(midnight) && dates == dates.sorted() && Set(dates).count == dates.count,
                        "timeline must include exact configured-timezone midnight across month/year without duplicate dates")
            try require(dates.last!.timeIntervalSince(now) >= 47*3600, "closed-app schedule must extend past the next day")
            let before = HealthWidgetData.projectedState(snapshot,at:now)
            let after = HealthWidgetData.projectedState(snapshot,at:midnight)
            let beforeTotal = before.records.filter { Engine.day($0.occurredAt,before) == Engine.day(now,before) }.reduce(0) { $0+$1.amount }
            let afterTotal = after.records.filter { Engine.day($0.occurredAt,after) == Engine.day(midnight,after) }.reduce(0) { $0+$1.amount }
            try require(beforeTotal == 250 && afterTotal == 0 && after.records[0].occurredAt == record.occurredAt,
                        "new-day business totals must reset by date grouping without changing the historical sample")
        }
        var newYork = Calendar(identifier:.gregorian)
        newYork.timeZone = TimeZone(identifier:"America/New_York")!
        let beforeDST = formatter.date(from:"2026-10-31T23:50:00-04:00")!
        let nextMidnight = newYork.date(byAdding:.day,value:1,to:newYork.startOfDay(for:beforeDST))!
        let dates = HealthWidgetData.timelineDates(now:beforeDST,calendar:newYork)
        try require(dates.contains(nextMidnight) && dates.allSatisfy { $0 >= beforeDST },
                    "timezone and DST schedule must use local calendar boundaries")
    }

    private static func failedPublicationRetry(_ directory: URL) throws {
        let fm = FileManager.default
        let db = try fixtureDatabase(directory)
        let record = makeRecord(.water,at:sampleDate)
        _ = try db.transaction(now:sampleDate) { try Engine.save(&$0,record:record,now:sampleDate) }
        let initial = HealthWidgetData.load(directory:directory,now:readDate,kind:"isolated-unit-test")
        guard let old = initial.snapshot else { throw FixtureFailure("Missing publication fixture snapshot") }
        let cache = directory.appendingPathComponent(HealthWidgetData.cacheFileName)
        let originalCache = try Data(contentsOf:cache)
        let lock = directory.appendingPathComponent(".widget-snapshot.lock")
        try fm.removeItem(at:lock)
        try fm.createDirectory(at:lock,withIntermediateDirectories:false)
        let newTime = readDate.addingTimeInterval(600)
        _ = try db.transaction(now:newTime) { state in
            state.records[0].amount = 525
            state.records[0].note = "committed despite blocked cache publication"
        }
        let pending = directory.appendingPathComponent(HealthWidgetData.pendingFileName)
        try require(db.read().records[0].amount == 525 && fm.fileExists(atPath:pending.path),
                    "cache publication failure must not undo committed business data and must keep retry pending")
        try require(Data(contentsOf:cache) == originalCache, "failed publication must preserve the complete prior verified cache")
        let blocked = HealthWidgetData.load(directory:directory,now:newTime,kind:"isolated-unit-test")
        try require(!blocked.isStale && blocked.error != nil && blocked.snapshot?.revision != old.revision && blocked.snapshot?.state.records[0].amount == 525,
                    "cache failure must not hide readable primary business data and must still report retry")
        try require(Data(contentsOf:cache) == originalCache && fm.fileExists(atPath:pending.path),
                    "fresh uncached reads must preserve the prior cache and keep publication pending")
        for attempt in 0..<3 {
            try require(!HealthWidgetData.retryPending(directory:directory,now:newTime.addingTimeInterval(Double(attempt))),
                        "persistent publication failure must return false without announcing a retry loop")
        }
        try require(Data(contentsOf:cache) == originalCache && fm.fileExists(atPath:pending.path),
                    "failed retries must retain the prior cache and pending publication")
        try fm.removeItem(at:lock)
        try require(HealthWidgetData.retryPending(directory:directory,now:newTime),
                    "first successful publication retry must request one refresh")
        try require(!fm.fileExists(atPath:pending.path) && Data(contentsOf:cache) != originalCache,
                    "retry after publication recovery must publish the changed content and clear its pending marker")
        try require(!HealthWidgetData.retryPending(directory:directory,now:newTime),
                    "an unchanged published revision must not request another refresh")
        let recovered = HealthWidgetData.load(directory:directory,now:newTime,kind:"isolated-unit-test")
        try require(!recovered.isStale && recovered.snapshot?.state.records[0].amount == 525 && recovered.snapshot?.sourceUpdatedAt == newTime,
                    "recovered widget snapshot must contain the actual latest business values")
    }

    private static func readOnlySharedSleepRewards(_ directory: URL) throws {
        let fm = FileManager.default
        let health = directory.appendingPathComponent("Health")
        let shared = directory.appendingPathComponent("SharedSleep")
        try fm.createDirectory(at:shared,withIntermediateDirectories:true)
        let file = shared.appendingPathComponent("sleep-records.sqlite")
        // A schema fixture feeds the real read-only bridge. Do not call the shared
        // writer here: its distributed notifications belong to actual app use.
        var raw: OpaquePointer?
        guard sqlite3_open_v2(file.path,&raw,SQLITE_OPEN_READWRITE|SQLITE_OPEN_CREATE,nil) == SQLITE_OK else { throw FixtureFailure("Cannot create isolated shared sleep fixture") }
        guard sqlite3_exec(raw,"CREATE TABLE sleep_metadata(id INTEGER PRIMARY KEY,version INTEGER); INSERT INTO sleep_metadata VALUES(1,1); CREATE TABLE sleep_records(id TEXT PRIMARY KEY,payload BLOB,deleted INTEGER); INSERT INTO sleep_records VALUES('recent',NULL,0); INSERT INTO sleep_records VALUES('old',NULL,0); INSERT INTO sleep_records VALUES('removed',NULL,1);",nil,nil,nil) == SQLITE_OK else {
            sqlite3_close(raw); throw FixtureFailure("Cannot populate shared sleep schema fixture")
        }
        sqlite3_close(raw)
        let end = readDate.addingTimeInterval(-3600)
        let recent = SharedSleepEntry(id:"recent",startedAt:end.addingTimeInterval(-8*3600),endedAt:end,durationSeconds:8*3600,score:100,pastureYield:7,
                                      manualEntry:true,manualGrowthCreditedSeconds:8*3600,manualProductionCreditedCycles:2,origin:"rhythm")
        var old = recent
        old.id = "old"
        old.startedAt.addTimeInterval(-72*3600)
        old.endedAt.addTimeInterval(-72*3600)
        try rawBlobUpdate(file,JSONEncoder().encode(recent),sql:"UPDATE sleep_records SET payload=? WHERE id='recent'")
        try rawBlobUpdate(file,JSONEncoder().encode(old),sql:"UPDATE sleep_records SET payload=? WHERE id='old'")
        let originalShared = try Data(contentsOf:file)
        let db = try fixtureDatabase(health)
        _ = try db.transaction(now:readDate) { state in
            state.preferences.gameEnabled = true
            state.island.energy = 10
            state.island.lastVisit = readDate
            state.island.lastSettled = readDate
        }
        let failures = Failures()
        DispatchQueue.concurrentPerform(iterations:2) { _ in
            do { _ = try HealthSleepRewardSync.synchronize(directory:health,now:readDate,sharedDirectory:shared) }
            catch { failures.add(error) }
        }
        try require(failures.values.isEmpty, "concurrent read-only sleep settlement must complete safely: \(failures.values)")
        let settled = try db.read()
        try require(settled.island.energy == 34 && settled.island.rewardedSleepIDs == Set(["recent"]),
                    "two widget readers settle only the recent nondeleted sleep once")
        try require(!HealthSleepRewardSync.synchronize(directory:health,now:readDate,sharedDirectory:shared),
                    "repeated sleep synchronization without pending rewards must be a no-op")
        try require(Data(contentsOf:file) == originalShared,
                    "widget sleep sync must preserve peer journal bytes, reward metadata and tombstones")

        let pausedDirectory = directory.appendingPathComponent("PausedHealth")
        let paused = try fixtureDatabase(pausedDirectory)
        _ = try paused.transaction(now:readDate) { state in
            state.preferences.gameEnabled = true
            state.island.paused = true
            state.island.energy = 10
            state.island.lastVisit = readDate
            state.island.lastSettled = readDate
        }
        try require(!HealthSleepRewardSync.synchronize(directory:pausedDirectory,now:readDate,sharedDirectory:shared) && paused.read().island.energy == 10,
                    "paused island does not consume pending sleep reward receipts")
        _ = try paused.transaction(now:readDate) { $0.island.paused = false }
        try require(HealthSleepRewardSync.synchronize(directory:pausedDirectory,now:readDate,sharedDirectory:shared) && paused.read().island.energy == 34,
                    "resumed island can settle eligible sleep once")

        let beforeFailure = try db.readVersioned().revision
        for defect in ["fractional-version", "text-version", "missing-table"] {
            let invalidDirectory = directory.appendingPathComponent(defect)
            try fm.createDirectory(at:invalidDirectory,withIntermediateDirectories:true)
            let invalidFile = invalidDirectory.appendingPathComponent("sleep-records.sqlite")
            try originalShared.write(to:invalidFile)
            switch defect {
            case "fractional-version":
                try rawSQL(invalidFile,"UPDATE sleep_metadata SET version=1.5")
                try require(rawScalar(invalidFile,"SELECT typeof(version) FROM sleep_metadata WHERE id=1") == "real",
                            "fractional version fixture must retain a SQLite REAL value")
            case "text-version":
                // INTEGER affinity coerces text '1' into an integer, so use an
                // untyped column to exercise an actual TEXT value from disk.
                try rawSQL(invalidFile,"DROP TABLE sleep_metadata; CREATE TABLE sleep_metadata(id INTEGER PRIMARY KEY,version); INSERT INTO sleep_metadata VALUES(1,CAST('1' AS TEXT))")
                try require(rawScalar(invalidFile,"SELECT typeof(version) FROM sleep_metadata WHERE id=1") == "text",
                            "text version fixture must retain a SQLite TEXT value")
            default:
                try rawSQL(invalidFile,"DROP TABLE sleep_records")
            }
            let bytesBefore = try Data(contentsOf:invalidFile)
            try expectFailure("invalid shared schema \(defect) must be rejected without treating it as empty") {
                _ = try HealthSleepRewardSync.synchronize(directory:health,now:readDate,sharedDirectory:invalidDirectory)
            }
            try require(db.readVersioned().revision == beforeFailure && Data(contentsOf:invalidFile) == bytesBefore,
                        "shared schema failure must preserve Health and the invalid shared source")
        }
        try rawSQL(file,"UPDATE sleep_records SET payload=x'7b' WHERE id='recent'")
        let damagedShared = try Data(contentsOf:file)
        try expectFailure("bad peer sleep row must not become an empty reward source") {
            _ = try HealthSleepRewardSync.synchronize(directory:health,now:readDate,sharedDirectory:shared)
        }
        try require(db.readVersioned().revision == beforeFailure && Data(contentsOf:file) == damagedShared,
                    "bad shared sleep source must leave both Health revision and peer bytes intact")
        let originalOverride = ProcessInfo.processInfo.environment["GAOSERIES_SLEEP_TEST_DIRECTORY"]!
        setenv("GAOSERIES_SLEEP_TEST_DIRECTORY",shared.path,1)
        defer { setenv("GAOSERIES_SLEEP_TEST_DIRECTORY",originalOverride,1) }
        let availableHealth = HealthWidgetData.load(directory:health,now:readDate,kind:"isolated-unit-test")
        try require(availableHealth.snapshot?.state.island.energy == 34 && !availableHealth.isStale && availableHealth.error != nil,
                    "unavailable sleep sync must not hide valid primary Health data and must indicate retry")
    }

    private static func fixtureDatabase(_ directory: URL) throws -> HealthDatabase {
        let database = try HealthDatabase(directory:directory)
        _ = try database.transaction(now:sampleDate) { state in
            state.preferences.gameEnabled = false
            state.preferences.timezone = "Asia/Shanghai"
            state.island.lastVisit = sampleDate
            state.island.lastSettled = sampleDate
        }
        return database
    }
    private static func makeRecord(_ kind: RecordKind, at date: Date) -> HealthRecord {
        var record = HealthRecord(kind:kind)
        record.occurredAt = date
        record.createdAt = date
        record.updatedAt = date
        record.timezone = "Asia/Shanghai"
        record.source = "fixture"
        switch kind {
        case .water: record.amount = 250
        case .meal: record.amount = 1; record.mealSource = .canteen; record.fullnessPercent = 75
        case .exercise: record.amount = 30
        case .weight: record.amount = 65
        }
        return record
    }
    private static func canonicalData(_ state: HealthState) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(state)
    }
    private static func rawSQL(_ file: URL, _ sql: String) throws {
        var db: OpaquePointer?
        guard sqlite3_open_v2(file.path,&db,SQLITE_OPEN_READWRITE,nil) == SQLITE_OK else { throw FixtureFailure("Cannot open fixture SQL") }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db,5000)
        guard sqlite3_exec(db,sql,nil,nil,nil) == SQLITE_OK else { throw FixtureFailure(String(cString:sqlite3_errmsg(db))) }
    }
    private static func rawBlob(_ file: URL, _ sql: String) throws -> Data {
        var db: OpaquePointer?
        guard sqlite3_open_v2(file.path,&db,SQLITE_OPEN_READONLY,nil) == SQLITE_OK else { throw FixtureFailure("Cannot read fixture SQL") }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db,sql,-1,&statement,nil) == SQLITE_OK else { throw FixtureFailure("Cannot prepare fixture SQL") }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW, let bytes = sqlite3_column_blob(statement,0) else { throw FixtureFailure("Missing fixture blob") }
        return Data(bytes:bytes,count:Int(sqlite3_column_bytes(statement,0)))
    }
    private static func rawScalar(_ file: URL, _ sql: String) throws -> String {
        var db: OpaquePointer?
        guard sqlite3_open_v2(file.path,&db,SQLITE_OPEN_READONLY,nil) == SQLITE_OK else { throw FixtureFailure("Cannot read fixture scalar") }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db,sql,-1,&statement,nil) == SQLITE_OK else { throw FixtureFailure("Cannot prepare fixture scalar") }
        defer { sqlite3_finalize(statement) }
        guard sqlite3_step(statement) == SQLITE_ROW, let bytes = sqlite3_column_text(statement,0) else { throw FixtureFailure("Missing fixture scalar") }
        return String(cString:bytes)
    }
    private static func rawBlobUpdate(_ file: URL, _ data: Data, sql: String) throws {
        var db: OpaquePointer?
        guard sqlite3_open_v2(file.path,&db,SQLITE_OPEN_READWRITE,nil) == SQLITE_OK else { throw FixtureFailure("Cannot update fixture blob") }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db,sql,-1,&statement,nil) == SQLITE_OK else { throw FixtureFailure("Cannot prepare fixture blob update") }
        defer { sqlite3_finalize(statement) }
        let bound = data.withUnsafeBytes { sqlite3_bind_blob(statement,1,$0.baseAddress,Int32(data.count),unsafeBitCast(-1,to:sqlite3_destructor_type.self)) }
        guard bound == SQLITE_OK && sqlite3_step(statement) == SQLITE_DONE else { throw FixtureFailure("Cannot update fixture blob") }
    }
    private static func require(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try condition() else { throw FixtureFailure(message) }
    }
    private static func expectFailure(_ message: String, _ work: () throws -> Void) throws {
        do { try work() } catch { return }
        throw FixtureFailure("Unexpected success: " + message)
    }
    private struct FixtureFailure: Error { let message: String; init(_ message: String) { self.message = message } }
    private final class Failures: @unchecked Sendable {
        private let lock = NSLock()
        private var errors: [Error] = []
        var values: [Error] { lock.lock(); defer { lock.unlock() }; return errors }
        func add(_ error: Error) { lock.lock(); defer { lock.unlock() }; errors.append(error) }
    }
}
