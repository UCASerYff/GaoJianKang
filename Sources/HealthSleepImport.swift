import Foundation

/// The shared journal is authoritative. Reading the legacy library only seeds
/// previously unseen IDs and never overwrites a synchronized record or deletion.
enum HealthSleepImport {
    private struct LegacyLibrary: Decodable { var sleepRecords: [SharedSleepEntry] }

    static func migrateLegacy(to shared: SharedSleepStore) throws {
        guard try !shared.hasLegacyMigration(SharedSleepStore.legacyMigrationKey) else { return }
        // An absent Rhythm library may be a not-yet-installed peer. Do not mark
        // that as a completed empty migration or suppress its eventual history.
        if let records = try legacyRecords() {
            try shared.seedLegacyOnce(records,key:SharedSleepStore.legacyMigrationKey)
        }
    }

    static func legacyRecords() throws -> [SharedSleepEntry]? {
        let environment = ProcessInfo.processInfo.environment
        if let override = environment["GAOJIEZOU_DATA_DIR"] {
            return try read(URL(fileURLWithPath:override).appendingPathComponent("library.json"))
        }
        // An isolated Health test must never seed from the user's real Rhythm data.
        if environment["GAOJIANKANG_TEST_DIRECTORY"] != nil || environment["GAOSERIES_SLEEP_TEST_DIRECTORY"] != nil { return nil }
        let base = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask).first!
        if let records = try read(base.appendingPathComponent("GaoSeries/Rhythm/library.json")) { return records }
        guard let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier:"5G96498KGJ.com.gaojiezou.rhythm") else { return nil }
        return try read(group.appendingPathComponent("library.json"))
    }

    private static func read(_ url: URL) throws -> [SharedSleepEntry]? {
        do { return try JSONDecoder().decode(LegacyLibrary.self,from:Data(contentsOf:url)).sleepRecords }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return nil }
        catch { throw HealthError("睡眠同步暂未完成，原始记录已保留。请检查搞节奏资料库后重试。 / Sleep sync failed; original records are retained. Check the Rhythm library and retry.") }
    }

    static func durationMinutes(hours: Int, minutes: Int) -> Int? {
        guard (0...24).contains(hours), (0...59).contains(minutes) else { return nil }
        let total = hours * 60 + minutes
        return (30...1440).contains(total) ? total : nil
    }

    /// Match Rhythm's duration entry: the selected night wakes at 07:00 the next day.
    static func manualInterval(night: Date, durationMinutes: Int, calendar: Calendar = .current) -> (start: Date, end: Date) {
        let nightStart = calendar.startOfDay(for:night)
        let wakeDay = calendar.date(byAdding:.day,value:1,to:nightStart) ?? nightStart
        let end = calendar.date(bySettingHour:7,minute:0,second:0,of:wakeDay) ?? wakeDay
        return (calendar.date(byAdding:.minute,value:-durationMinutes,to:end) ?? end,end)
    }

    static func manual(start: Date, end: Date, now: Date = Date()) throws -> SharedSleepEntry {
        let duration = end.timeIntervalSince(start)
        guard start.timeIntervalSinceReferenceDate.isFinite, end.timeIntervalSinceReferenceDate.isFinite,
              (1800...86400).contains(duration), end <= now else {
            throw HealthError("请填写已结束的睡眠，就寝早于起床，时长为 30 分钟至 24 小时。 / Enter completed sleep lasting 30 minutes to 24 hours.")
        }
        return SharedSleepEntry(id:UUID().uuidString,startedAt:start,endedAt:end,durationSeconds:duration,
            score:max(0,min(100,Int(100-abs(duration/3600-8)*18))),pastureYield:0,
            manualEntry:true,manualGrowthCreditedSeconds:0,manualProductionCreditedCycles:0,origin:"health")
    }
}
