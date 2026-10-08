import Foundation
enum HealthCSV { static func cell(_ value:String)->String { value } }

@main struct HealthSleepRegression {
    static func check(_ value: Bool) { assert(value) }
    static func main() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("health-sleep-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true)
        defer { try? FileManager.default.removeItem(at:root) }
        setenv("GAOSERIES_SLEEP_TEST_DIRECTORY",root.appendingPathComponent("shared").path,1)
        setenv("GAOJIEZOU_DATA_DIR",root.appendingPathComponent("rhythm").path,1)
        let now=Date(), end=now.addingTimeInterval(-60)
        let manual=try HealthSleepImport.manual(start:end.addingTimeInterval(-8*3600),end:end,now:now)
        assert(manual.origin == "health" && manual.manualEntry == true)
        assert(manual.durationSeconds == 8*3600 && manual.score == 100)
        for interval in [60.0,90000.0] {
            do { _ = try HealthSleepImport.manual(start:end.addingTimeInterval(-interval),end:end,now:now); assertionFailure("Invalid duration accepted") } catch {}
        }
        do { _ = try HealthSleepImport.manual(start:now,end:now.addingTimeInterval(3600),now:now); assertionFailure("Future sleep accepted") } catch {}
        check(try HealthSleepImport.legacyRecords() == nil)
        let legacy = root.appendingPathComponent("rhythm")
        try FileManager.default.createDirectory(at:legacy,withIntermediateDirectories:true)
        let saved = try JSONEncoder().encode(["sleepRecords":[manual]])
        try saved.write(to:legacy.appendingPathComponent("library.json"))
        check(try HealthSleepImport.legacyRecords() == [manual])
        let first=try SharedSleepStore(), second=try SharedSleepStore()
        try HealthSleepImport.migrateLegacy(to:first)
        try second.seed([manual])
        check(try first.records().count == 1)
        var state=HealthState(); state.island.energy=10;state.island.lastSettled=now;state.island.lastVisit=now
        let rewards=try second.records().map { Engine.SleepReward(id:$0.id,endedAt:$0.endedAt,durationSeconds:$0.durationSeconds) }
        Engine.rewardSleep(&state,records:rewards,now:now)
        assert(state.island.energy == 34 && state.island.rewardedSleepIDs.contains(manual.id))
        Engine.rewardSleep(&state,records:rewards,now:now)
        assert(state.island.energy == 34)
        try second.remove(manual.id); try first.seed([manual])
        check(try first.records().isEmpty)
        assert(state.island.energy == 34)
        let corrupt=Data("unreadable fixture".utf8)
        try corrupt.write(to:legacy.appendingPathComponent("library.json"))
        do { _ = try HealthSleepImport.legacyRecords(); assertionFailure("Corruption treated as empty") } catch {}
        check(try Data(contentsOf:legacy.appendingPathComponent("library.json")) == corrupt)
        try HealthSleepImport.migrateLegacy(to:first) // completed migration never re-reads stale/corrupt peer data
        check(try first.records().isEmpty)
        print("PASS Health sleep: validated manual entry, legacy import, both connections, reward once, deletion retention, unreadable source preserved")
    }
}
