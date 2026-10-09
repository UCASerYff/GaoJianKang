import Foundation

// This suite uses value fixtures only: no application containers or personal files are opened.
enum HealthCSV { static func cell(_ value: String) -> String { value } }

@main struct BackfillRegression {
    static func main() throws {
        try sleepDurationAndNight()
        try historicalRecordsAndEdits()
        try sameDayRewardLimits()
        try preferenceTimezoneBoundary()
        try historicalQuickEvents()
        try historicalSleepRewards()
        print("PASS Backfill: duration bounds; selected-night 07:00 conversion; month/year/leap/DST boundaries; future wake rejection; all four historical record kinds; stable edit IDs; timezone day attribution; daily reward idempotency; quick-event history; once-only recent sleep rewards")
    }

    private static func sleepDurationAndNight() throws {
        let valid: [(Int, Int, Int)] = [(0,30,30),(1,0,60),(7,45,465),(8,0,480),(23,59,1439),(24,0,1440)]
        for (hours, minutes, total) in valid {
            try require(HealthSleepImport.durationMinutes(hours:hours,minutes:minutes) == total, "valid hour/minute duration must be preserved")
        }
        let invalid: [(Int, Int)] = [(0,0),(0,29),(-1,30),(25,0),(24,1),(8,60),(8,-1),(Int.max,0),(0,Int.max),(Int.min,0)]
        for (hours, minutes) in invalid {
            try require(HealthSleepImport.durationMinutes(hours:hours,minutes:minutes) == nil, "invalid hour/minute duration must not normalize silently")
        }

        let shanghai = calendar("Asia/Shanghai")
        let nights = [
            (date(2026,1,31,12,calendar:shanghai), "2026-02-01"),
            (date(2025,12,31,12,calendar:shanghai), "2026-01-01"),
            (date(2028,2,28,12,calendar:shanghai), "2028-02-29")
        ]
        for (night, wakeDay) in nights {
            for minutes in [30, 480, 1440] {
                let interval = HealthSleepImport.manualInterval(night:night,durationMinutes:minutes,calendar:shanghai)
                try require(day(interval.end,calendar:shanghai) == wakeDay, "selected night must end on next calendar day")
                try require(shanghai.component(.hour,from:interval.end) == 7 && shanghai.component(.minute,from:interval.end) == 0, "converted wake-up remains 07:00")
                try require(interval.end.timeIntervalSince(interval.start) == Double(minutes * 60), "converted interval preserves actual sleep duration")
                let saved = try HealthSleepImport.manual(start:interval.start,end:interval.end,now:interval.end)
                try require(saved.durationSeconds == Double(minutes * 60) && saved.manualEntry == true && saved.origin == "health", "duration entry must use the existing shared sleep wire format")
            }
        }

        let newYork = calendar("America/New_York")
        for night in [date(2026,3,7,12,calendar:newYork), date(2026,10,31,12,calendar:newYork)] {
            let interval = HealthSleepImport.manualInterval(night:night,durationMinutes:480,calendar:newYork)
            try require(newYork.component(.hour,from:interval.end) == 7, "DST wake-up is a local 07:00, not a fixed UTC offset")
            try require(interval.end.timeIntervalSince(interval.start) == 8 * 3600, "DST night must preserve entered elapsed hours")
            let tomorrow = newYork.date(byAdding:.day,value:1,to:newYork.startOfDay(for:night))!
            try require(newYork.isDate(interval.end,inSameDayAs:tomorrow), "DST must not change selected-night date attribution")
        }

        let lastNight = date(2026,10,8,12,calendar:shanghai)
        let interval = HealthSleepImport.manualInterval(night:lastNight,durationMinutes:480,calendar:shanghai)
        try expectFailure("before 07:00, the derived sleep has not ended") {
            _ = try HealthSleepImport.manual(start:interval.start,end:interval.end,now:date(2026,10,9,6,59,calendar:shanghai))
        }
        _ = try HealthSleepImport.manual(start:interval.start,end:interval.end,now:date(2026,10,9,7,calendar:shanghai))
    }

    private static func historicalRecordsAndEdits() throws {
        let cal = calendar("Asia/Shanghai")
        let now = date(2026,10,9,12,calendar:cal)
        let yesterday = date(2026,10,8,18,calendar:cal)
        var state = fixture(now:now)
        let before = resources(state)
        for kind in RecordKind.allCases {
            var record = record(kind:kind,occurredAt:yesterday,createdAt:now)
            try Engine.save(&state,record:record,now:now)
            let originalID = record.id
            record.note = "补记后的修正"
            record.occurredAt = yesterday.addingTimeInterval(-3600)
            try Engine.save(&state,record:record,now:now)
            let saved = state.records.filter { $0.id == originalID }
            try require(saved.count == 1 && saved[0].occurredAt == record.occurredAt && saved[0].note == record.note, "editing a backfill must preserve its ID and historical timestamp")
            try require(saved[0].createdAt == now && saved[0].updatedAt == now, "backfill must distinguish occurrence time from creation time")
            try require(resources(state) == before, "historical backfill must not issue retroactive island rewards")
        }
        try require(state.records.count == RecordKind.allCases.count && state.ledgers.isEmpty, "all historical kinds persist without creating reward ledgers")
        try Engine.validate(state)
        let restored = try JSONDecoder().decode(HealthState.self,from:JSONEncoder().encode(state))
        try require(restored.records == state.records, "backfill dates and stable IDs survive existing-format roundtrip")

        var future = record(kind:.water,occurredAt:now.addingTimeInterval(3600),createdAt:now)
        future.amount = 250
        let original = state.records
        try expectFailure("future health record rejected") { try Engine.save(&state,record:future,now:now) }
        try require(state.records == original && resources(state) == before, "invalid future record must not alter history or game state")
    }

    private static func sameDayRewardLimits() throws {
        let cal = calendar("Asia/Shanghai")
        let now = date(2026,10,9,20,calendar:cal)
        var state = fixture(now:now)
        let today = Engine.day(now,state)
        state.ledgers[today] = DailyLedger(welcomed:true,harvested:true)
        var water = record(kind:.water,occurredAt:date(2026,10,9,8,calendar:cal),createdAt:now)
        try Engine.save(&state,record:water,now:now)
        try require(state.island.water == 20, "same-day backfill follows today's existing water reward")
        try Engine.save(&state,record:water,now:now)
        water.note = "修正备注，不重复领奖"
        try Engine.save(&state,record:water,now:now)
        try require(state.island.water == 20 && state.records.count == 1, "resaving or editing backfill cannot replay its reward")

        let meal = record(kind:.meal,occurredAt:date(2026,10,9,12,calendar:cal),createdAt:now)
        try Engine.save(&state,record:meal,now:now)
        try Engine.save(&state,record:meal,now:now)
        try require(state.island.food == 28.75, "meal backfill settles fullness once using current meal slots")
        let activity = record(kind:.exercise,occurredAt:date(2026,10,9,15,calendar:cal),createdAt:now)
        try Engine.save(&state,record:activity,now:now)
        try Engine.save(&state,record:activity,now:now)
        try require(state.island.energy == 28, "activity backfill settles the 18-point daily cap once")
        let beforeWeight = resources(state)
        try Engine.save(&state,record:record(kind:.weight,occurredAt:date(2026,10,9,7,calendar:cal),createdAt:now),now:now)
        try require(resources(state) == beforeWeight, "weight backfill has no additional island reward")
        try Engine.save(&state,record:record(kind:.exercise,occurredAt:date(2026,10,9,16,calendar:cal),createdAt:now),now:now)
        try require(state.island.energy == 28 && state.ledgers[today]?.activity == 18, "multiple backfills cannot exceed the existing daily activity cap")
    }

    private static func preferenceTimezoneBoundary() throws {
        let cal = calendar("Asia/Shanghai")
        // Both timestamps are October 8 in UTC, but straddle local midnight.
        let now = date(2026,10,9,0,30,calendar:cal)
        let yesterday = date(2026,10,8,23,30,calendar:cal)
        var state = fixture(now:now)
        let old = record(kind:.water,occurredAt:yesterday,createdAt:now)
        try Engine.save(&state,record:old,now:now)
        try require(Engine.day(old.occurredAt,state) == "2026-10-08" && state.island.water == 10, "configured timezone decides historical day at UTC boundary")
        state.ledgers[Engine.day(now,state)] = DailyLedger(welcomed:true,harvested:true)
        try Engine.save(&state,record:record(kind:.water,occurredAt:date(2026,10,9,0,15,calendar:cal),createdAt:now),now:now)
        try require(state.island.water == 20 && state.ledgers["2026-10-09"]?.water == 10, "same local day awards despite its different UTC date label")
    }

    private static func historicalQuickEvents() throws {
        let cal = calendar("Asia/Shanghai")
        let now = date(2026,10,9,12,calendar:cal)
        var state = fixture(now:now)
        var event = HealthEvent(typeID:state.eventTypes[0].id)
        event.occurredAt = date(2026,9,30,23,45,calendar:cal)
        event.count = 2
        let before = resources(state)
        try EventLog.save(&state,event,now:now)
        event.count = 3
        event.note = "补记事项"
        try EventLog.save(&state,event,now:now)
        try require(state.events == [event], "quick-event edit preserves ID and replaces the original instead of appending")
        let september = EventLog.month(date(2026,9,1,12,calendar:cal),state:state,type:event.typeID)
        let october = EventLog.month(now,state:state,type:event.typeID)
        try require(september.reduce(0) { $0+$1.count } == 3 && october.reduce(0) { $0+$1.count } == 0, "quick-event backfill stays in the selected historical month")
        try require(resources(state) == before && state.ledgers.isEmpty, "quick-event history and edits never grant island rewards")
        var future = event
        future.id = UUID()
        future.occurredAt = now.addingTimeInterval(3600)
        try expectFailure("future quick event rejected") { try EventLog.save(&state,future,now:now) }
        try require(state.events == [event], "rejected future quick event leaves history intact")
    }

    private static func historicalSleepRewards() throws {
        let cal = calendar("Asia/Shanghai")
        let now = date(2026,10,9,12,calendar:cal)
        var state = fixture(now:now)
        let oldInterval = HealthSleepImport.manualInterval(night:date(2026,9,30,12,calendar:cal),durationMinutes:480,calendar:cal)
        let old = try HealthSleepImport.manual(start:oldInterval.start,end:oldInterval.end,now:now)
        let oldReward = Engine.SleepReward(id:old.id,endedAt:old.endedAt,durationSeconds:old.durationSeconds)
        Engine.rewardSleep(&state,records:[oldReward],now:now)
        try require(state.island.energy == 10 && !state.island.rewardedSleepIDs.contains(old.id), "old sleep backfill persists but is outside the existing 36-hour reward window")
        let recentInterval = HealthSleepImport.manualInterval(night:date(2026,10,8,12,calendar:cal),durationMinutes:480,calendar:cal)
        let recent = try HealthSleepImport.manual(start:recentInterval.start,end:recentInterval.end,now:now)
        let reward = Engine.SleepReward(id:recent.id,endedAt:recent.endedAt,durationSeconds:recent.durationSeconds)
        Engine.rewardSleep(&state,records:[reward],now:now)
        Engine.rewardSleep(&state,records:[reward],now:now)
        try require(state.island.energy == 34 && state.island.rewardedSleepIDs.contains(recent.id), "recent sleep backfill restores 24 energy once with unchanged game rules")
    }

    private static func fixture(now: Date) -> HealthState {
        var state = HealthState()
        state.preferences.timezone = "Asia/Shanghai"
        state.island.lastSettled = now
        state.island.lastVisit = now
        state.island.energy = 10
        state.island.water = 10
        state.island.food = 10
        return state
    }
    private static func record(kind: RecordKind, occurredAt: Date, createdAt: Date) -> HealthRecord {
        var result = HealthRecord(kind:kind)
        result.occurredAt = occurredAt
        result.createdAt = createdAt
        result.updatedAt = createdAt
        result.timezone = "Asia/Shanghai"
        switch kind {
        case .water: result.amount = 250
        case .meal: result.amount = 1; result.fullnessPercent = 75; result.mealSource = .canteen; result.slot = 0
        case .exercise: result.amount = 30
        case .weight: result.amount = 65
        }
        return result
    }
    private static func resources(_ state: HealthState) -> [Double] { [state.island.water,state.island.food,state.island.energy] }
    private static func calendar(_ timezone: String) -> Calendar {
        var result = Calendar(identifier:.gregorian)
        result.timeZone = TimeZone(identifier:timezone)!
        return result
    }
    private static func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int = 0, calendar: Calendar) -> Date {
        calendar.date(from:DateComponents(year:year,month:month,day:day,hour:hour,minute:minute))!
    }
    private static func day(_ date: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year,.month,.day],from:date)
        return String(format:"%04d-%02d-%02d",c.year!,c.month!,c.day!)
    }
    private static func require(_ condition: @autoclosure () throws -> Bool, _ message: String) throws {
        guard try condition() else { throw TestFailure(message) }
    }
    private static func expectFailure(_ message: String, _ work: () throws -> Void) throws {
        do { try work() } catch { return }
        throw TestFailure(message)
    }
    private struct TestFailure: Error { let message: String; init(_ message: String) { self.message = message } }
}
