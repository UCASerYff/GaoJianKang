import Foundation

enum Engine {
    static func placementAllowed(x: Double, z: Double, expansion: Int) -> Bool {
        let radius = sqrt(31.0) + Double(min(3,max(0,expansion))) * 0.7
        return x.isFinite && z.isFinite && x*x + z*z < radius*radius
    }
    static func calendar(_ s: HealthState) -> Calendar {
        var c = Calendar(identifier:.gregorian); c.timeZone = TimeZone(identifier:s.preferences.timezone) ?? .current; return c
    }
    static func day(_ date: Date, _ s: HealthState) -> String {
        let c = calendar(s).dateComponents([.year,.month,.day],from:date)
        return String(format:"%04d-%02d-%02d",c.year!,c.month!,c.day!)
    }
    /// Consecutive days with at least one record, ending today (or yesterday when today has none yet).
    static func streak(_ s: HealthState, now: Date) -> Int {
        let c = calendar(s)
        let days = Set(s.records.map { day($0.occurredAt,s) })
        var cursor = c.startOfDay(for:now)
        if !days.contains(day(cursor,s)) {
            guard let yesterday = c.date(byAdding:.day,value:-1,to:cursor) else { return 0 }
            cursor = yesterday
        }
        var count = 0
        while days.contains(day(cursor,s)) {
            count += 1
            guard let previous = c.date(byAdding:.day,value:-1,to:cursor) else { break }
            cursor = previous
        }
        return count
    }
    static func settle(_ s: inout HealthState, now: Date) {
        if s.island.logs.count > 300 { s.island.logs=Array(s.island.logs.suffix(300)) }
        guard now > s.island.lastSettled else { return }
        defer { s.island.lastSettled = now }
        guard s.preferences.gameEnabled && !s.island.paused else { return }
        let finish = min(now, s.island.lastVisit.addingTimeInterval(86400))
        var t = s.island.lastSettled
        let c = calendar(s)
        while t < finish {
            let boundary = c.dateInterval(of:.hour,for:t)?.end ?? t.addingTimeInterval(3600)
            let end = min(finish, boundary)
            let hours = end.timeIntervalSince(t) / 3600
            let cfg = s.preferences.config(day(t,s))
            let h = c.component(.hour,from:t)
            let resting = ((h - cfg.restHour + 24) % 24) < 8
            let multiplier = resting ? (s.island.buildingLevel("shelter") > 0 ? 0.375 - Double(s.island.buildingLevel("shelter")-1)*0.055 : 0.5) : 1.0
            let wellFactor = s.island.buildingLevel("well") > 0 ? 0.75 - Double(s.island.buildingLevel("well")-1)*0.10 : 1.0
            s.island.water = max(0,s.island.water - 3 * hours * multiplier * wellFactor)
            s.island.food = max(0,s.island.food - 2.5 * hours * multiplier)
            s.island.energy = max(0,s.island.energy - 0.8 * hours * multiplier)
            t = end
        }
    }
    static func visit(_ s: inout HealthState, now: Date, welcome: Bool) {
        settle(&s,now:now)
        guard s.preferences.gameEnabled && !s.island.paused else { s.island.lastVisit = max(s.island.lastVisit,now); return }
        if now.timeIntervalSince(s.island.lastVisit) >= 3*86400 && now.timeIntervalSince(s.island.lastGift ?? .distantPast) >= 7*86400 {
            s.island.water = max(s.island.water,30); s.island.food = max(s.island.food,30); s.island.energy = max(s.island.energy,30)
            s.island.lastGift = now
            log(&s,"return","Welcome back / 欢迎回来",now)
        }
        s.island.lastVisit = max(s.island.lastVisit,now)
        let key = day(now,s)
        var ledger = s.ledgers[key,default:DailyLedger()]
        if !ledger.harvested {
            ledger.harvested = true
            var gains: [String] = []
            if s.island.buildingLevel("garden") > 0 { let n = s.island.buildingLevel("garden")+1; s.island.inventory["ration",default:0]+=n; gains.append("+\(n) 干粮 Rations") }
            if s.island.buildingLevel("farm") > 0 { let n = 3+2*s.island.buildingLevel("farm"); s.island.inventory["ration",default:0]+=n; gains.append("+\(n) 干粮 Rations") }
            if s.island.buildingLevel("clinic") > 0 { let n = 2+3*s.island.buildingLevel("clinic"); s.island.energy = min(100,s.island.energy+Double(n)); gains.append("+\(n) 活力 Energy") }
            let rain=s.island.buildingLevel("rainCollector"),fruit=s.island.buildingLevel("orchard")
            if rain>0 { let gain=min(100-s.island.water,Double(6*rain));s.island.water+=gain;gains.append("+\(Int(gain)) 水分 Water") }
            if fruit>0 { s.island.inventory["ration",default:0]+=2*fruit;gains.append("+\(2*fruit) 干粮 Rations") }
            if !gains.isEmpty { log(&s,"harvest","每日收获 Daily harvest · " + gains.joined(separator:" · "),now) }
        }
        s.ledgers[key] = ledger
        if welcome && !s.ledgers[key,default:DailyLedger()].welcomed && now >= s.island.lastSettled {
            s.ledgers[key,default:DailyLedger()].welcomed = true
            s.island.energy = min(100,s.island.energy+20)
        }
    }
    static func save(_ s: inout HealthState, record: HealthRecord, now: Date) throws {
        try validateRecord(record,now:now)
        let old = s.records.first { $0.id == record.id }
        var r = record; r.updatedAt = now
        r.rewardEligible = old?.rewardEligible ?? (s.preferences.gameEnabled && !s.island.paused)
        if let old { r.createdAt = old.createdAt }
        settle(&s,now:now)
        s.records.removeAll { $0.id == r.id }; s.records.append(r)
        let currentDay = day(now,s)
        let today = day(r.occurredAt,s) == currentDay
        if today { visit(&s,now:now,welcome:r.rewardEligible) }
        guard today && r.rewardEligible && s.preferences.gameEnabled && !s.island.paused && now >= s.island.lastSettled else { return }
        let all = s.records.filter { $0.rewardEligible && day($0.occurredAt,s)==currentDay }
        let water = min(80,all.filter { $0.kind == .water }.reduce(0) { $0 + $1.amount } / 25)
        let slots = s.preferences.config(currentDay).slots
        var fullnessBySlot: [Int: Int] = [:]
        for meal in all where meal.kind == .meal && meal.slot >= 0 && meal.slot < slots {
            fullnessBySlot[meal.slot] = max(fullnessBySlot[meal.slot] ?? 0, meal.fullnessPercent ?? 100)
        }
        let food = min(75, Double(fullnessBySlot.values.reduce(0, +)) * 75 / Double(slots * 100))
        let training = s.island.buildingLevel("training")
        let activityCap = Double(18 + max(0,training-1)*3)
        let activity = min(activityCap,all.filter { $0.kind == .exercise }.reduce(0) { $0 + $1.amount } * 0.6 * (training > 0 ? 1.25 + Double(training-1)*0.10 : 1))
        var ledger = s.ledgers[currentDay,default:DailyLedger()]
        s.island.water = min(100,s.island.water + max(0,water-ledger.water))
        s.island.food = min(100,s.island.food + max(0,food-ledger.food))
        s.island.energy = min(100,s.island.energy + max(0,activity-ledger.activity))
        ledger.water = max(water,ledger.water); ledger.food = max(food,ledger.food); ledger.activity = max(activity,ledger.activity)
        s.ledgers[currentDay] = ledger
    }
    static func has(_ s: HealthState,_ key: String) -> Bool { s.island.tools.contains(key) || s.island.buildings.contains(key) }
    static func energyCost(_ s:HealthState,_ a:Catalog.Action)->Double { a.energy*(1-0.05*Double(s.island.buildingLevel("workshop"))) }
    static func actionProblem(_ s: HealthState,_ a: Catalog.Action) -> String? {
        let en = s.preferences.english
        if !s.preferences.gameEnabled || s.island.paused { return en ? "Resume your island first" : "请先恢复岛屿经营" }
        if let need = a.need, !has(s,need) { return (en ? "Requires " : "需要先获得") + (Catalog.recipes.first { $0.id==need }?.title(en) ?? need) }
        var missing:[String]=[]
        if s.island.energy < energyCost(s,a) { missing.append(en ? "Energy: sleep or activity records" : "活力不足：记录睡眠或运动") }
        if s.island.food < a.food { missing.append(en ? "Food: record a meal or use rations" : "饱食不足：记录饮食或食用干粮") }
        if s.island.water < a.water { missing.append(en ? "Water: record drinking water" : "水分不足：记录饮水") }
        if !missing.isEmpty { return missing.joined(separator:" · ") }
        return nil
    }
    static func yield(_ s: HealthState,_ a: Catalog.Action) -> Int {
        let multiplier: Int
        switch a.id {
        case "chop": multiplier = has(s,"ironAxe") ? 3 : has(s,"axe") ? 2 : 1
        case "quarry", "mine": multiplier = has(s,"ironPickaxe") ? 2 : 1
        case "fish": multiplier = has(s,"net") ? 3 : has(s,"spear") ? 2 : 1
        default: multiplier = 1
        }
        let bonus = a.id == "fish" ? max(0,s.island.buildingLevel("campfire")-1) : a.id == "herb" ? max(0,s.island.buildingLevel("herbGarden")-1) : 0
        return a.quantity * multiplier + bonus + (a.id == "fiber" ? s.island.buildingLevel("windmill") : 0)
    }
    /// Default meal display name; snack slots never fall back to a regular meal name.
    static func mealTitle(slot: Int, occurredAt: Date, _ s: HealthState) -> String {
        let en = s.preferences.english
        let slots = s.preferences.config(day(occurredAt,s)).slots
        if slot >= slots { return en ? "Snack" : "加餐" }
        if slots == 3 { return [en ? "Breakfast" : "早餐", en ? "Lunch" : "午餐", en ? "Dinner" : "晚餐"][slot] }
        return en ? "Meal \(slot+1)" : "第 \(slot+1) 餐"
    }
    static func act(_ s: inout HealthState,id: String,now: Date) throws {
        visit(&s,now:now,welcome:true)
        guard let a = Catalog.actions.first(where: { $0.id==id }) else { throw HealthError("Unknown action") }
        if let problem = actionProblem(s,a) { throw HealthError(problem) }
        let n = yield(s,a)
        s.island.energy -= energyCost(s,a); s.island.food -= a.food; s.island.water -= a.water
        s.island.inventory[a.output,default:0] += n
        if id == "coconut" { s.island.food = min(100,s.island.food+3) }
        log(&s,id,"\(a.cn) / \(a.en) · +\(n) \(Catalog.name(a.output,false))",now)
    }
    static func buildProblem(_ s: HealthState,_ r: Recipe) -> String? {
        let en = s.preferences.english
        if has(s,r.id) { return en ? "Completed" : "已拥有" }
        if !s.preferences.gameEnabled || s.island.paused { return en ? "Island resting" : "岛屿休整中" }
        if let need = r.prerequisite, !has(s,need) { return (en ? "Requires " : "需要先获得") + (Catalog.recipes.first { $0.id==need }?.title(en) ?? need) }
        if s.island.expansionLevel<r.minimumExpansion { return en ? "Requires shore expansion \(r.minimumExpansion)" : "需先扩建海岸至 \(r.minimumExpansion) 级" }
        if !r.tool && freeSite(s.island,id:r.id) == nil { return en ? "Rearrange buildings to make room" : "请进入布局模式腾出建筑空间" }
        if r.cost.contains(where: { s.island.inventory[$0.key,default:0] < $0.value }) { return en ? "Gather more materials" : "材料尚不足" }
        return nil
    }
    static func build(_ s: inout HealthState,id: String,now: Date) throws {
        visit(&s,now:now,welcome:true)
        guard let r = Catalog.recipes.first(where: { $0.id==id }) else { throw HealthError("Unknown recipe") }
        if let problem = buildProblem(s,r) { throw HealthError(problem) }
        for (key,value) in r.cost { s.island.inventory[key,default:0] -= value }
        if r.tool { s.island.tools.insert(id) } else { let site=freeSite(s.island,id:id)!;s.island.buildings.insert(id);s.island.placements[id]=site }
        log(&s,id,"\(r.cn) / \(r.en)",now)
    }
    struct SleepReward {
        let id: String
        let endedAt: Date
        let durationSeconds: Double
    }
    static func eligibleSleep(_ s: HealthState, records: [SleepReward], now: Date) -> [SleepReward] {
        guard s.preferences.gameEnabled && !s.island.paused else { return [] }
        return records.filter { r in
            !r.id.isEmpty && !s.island.rewardedSleepIDs.contains(r.id) && r.durationSeconds.isFinite &&
            (1800...86400).contains(r.durationSeconds) && r.endedAt <= now && now.timeIntervalSince(r.endedAt) <= 36*3600
        }.sorted { $0.endedAt < $1.endedAt }
    }
    static func rewardSleep(_ s: inout HealthState, records: [SleepReward], now: Date) {
        let pending = eligibleSleep(s,records:records,now:now)
        guard !pending.isEmpty else { return }
        visit(&s,now:now,welcome:false)
        let key = day(now,s)
        var ledger = s.ledgers[key,default:DailyLedger()]
        var earned = 0.0
        for record in pending {
            guard s.island.rewardedSleepIDs.insert(record.id).inserted else { continue }
            let gain = min(max(0,24-ledger.sleepEnergy),record.durationSeconds/3600*3)
            ledger.sleepEnergy += gain
            earned += gain
        }
        if earned > 0 {
            s.island.energy = min(100,s.island.energy+earned)
            log(&s,"sleep","睡眠恢复活力 / Sleep restored energy · +\(Int(earned.rounded()))",now)
        }
        s.ledgers[key] = ledger
    }
    static func upgradeCost(_ recipe: Recipe, to level: Int) -> [String:Int] {
        recipe.cost.mapValues { $0 * level }
    }
    static func upgradeProblem(_ s: HealthState,_ recipe: Recipe) -> String? {
        let en = s.preferences.english
        let level = s.island.buildingLevel(recipe.id)
        if recipe.tool || level == 0 { return en ? "Build it first" : "请先建造" }
        if level >= 4 { return en ? "Max level" : "已升至最高级" }
        if !s.preferences.gameEnabled || s.island.paused { return en ? "Island resting" : "岛屿休整中" }
        if upgradeCost(recipe,to:level+1).contains(where:{ s.island.inventory[$0.key,default:0] < $0.value }) { return en ? "Gather more materials" : "材料尚不足" }
        return nil
    }
    static func upgrade(_ s: inout HealthState,id: String,now: Date) throws {
        visit(&s,now:now,welcome:true)
        guard let recipe = Catalog.recipes.first(where:{ $0.id == id && !$0.tool }) else { throw HealthError("Unknown building") }
        if let problem = upgradeProblem(s,recipe) { throw HealthError(problem) }
        let level = s.island.buildingLevel(id)+1
        for (key,value) in upgradeCost(recipe,to:level) { s.island.inventory[key,default:0] -= value }
        s.island.buildingLevels[id] = level
        log(&s,"upgrade","\(recipe.cn) / \(recipe.en) · Lv.\(level)",now)
    }
    static let expansionCosts: [[String:Int]] = [
        ["wood":35,"stone":20,"fiber":12],
        ["wood":70,"stone":45,"iron":20],
        ["wood":120,"stone":80,"iron":40,"herb":20]
    ]
    static let expansionRequirements = [100,240,370]
    static func expansionProblem(_ s: HealthState) -> String? {
        let en = s.preferences.english
        let stage = s.island.expansionLevel
        if stage >= expansionCosts.count { return en ? "All shores opened" : "海岸已全部开拓" }
        if !s.preferences.gameEnabled || s.island.paused { return en ? "Island resting" : "岛屿休整中" }
        if s.island.prosperity < expansionRequirements[stage] { return en ? "More prosperity needed" : "繁荣度尚不足" }
        if expansionCosts[stage].contains(where:{ s.island.inventory[$0.key,default:0] < $0.value }) { return en ? "Gather more materials" : "材料尚不足" }
        return nil
    }
    static func expand(_ s: inout HealthState,now: Date) throws {
        visit(&s,now:now,welcome:true)
        if let problem = expansionProblem(s) { throw HealthError(problem) }
        let stage = s.island.expansionLevel
        for (key,value) in expansionCosts[stage] { s.island.inventory[key,default:0] -= value }
        s.island.expansionLevel += 1
        log(&s,"expand","扩建海岸 / Expanded the shore · \(s.island.expansionLevel)/3",now)
    }
    static func supply(_ s: inout HealthState,now: Date) throws {
        visit(&s,now:now,welcome:true); let d = day(now,s)
        guard s.preferences.gameEnabled && !s.island.paused && s.island.inventory["ration",default:0]>0 && s.island.food<100 && s.ledgers[d,default:DailyLedger()].supplies<3 else { throw HealthError(s.preferences.english ? "Supplies unavailable or daily limit reached" : "暂无干粮、饱食已满或今日已使用 3 次") }
        s.island.inventory["ration",default:0] -= 1; s.island.food = min(100,s.island.food+Double(5+3*s.island.buildingLevel("kitchen")))
        s.ledgers[d,default:DailyLedger()].supplies += 1
        log(&s,"supply","食用补给 / Eat supplies · +\(5+3*s.island.buildingLevel("kitchen"))",now)
    }
    static func site(_ island:Island,_ id:String)->IslandPoint { island.placements[id] ?? Catalog.defaultSites[id] ?? IslandPoint(x:0,z:0) }
    static func freeSite(_ island:Island,id:String)->IslandPoint? {
        var candidates=[Catalog.defaultSites[id] ?? IslandPoint(x:0,z:0)]
        for z in stride(from:-7.0,through:7.0,by:0.7) { for x in stride(from:-7.0,through:7.0,by:0.7) { candidates.append(.init(x:x,z:z)) } }
        return candidates.first { p in placementAllowed(x:p.x,z:p.z,expansion:island.expansionLevel) && island.buildings.allSatisfy { key in let q=site(island,key);return hypot(p.x-q.x,p.z-q.z)>1.9 } }
    }
    static func applyLayout(_ s:inout HealthState,placements:[String:IslandPoint]) throws {
        guard Set(placements.keys)==s.island.buildings else { throw HealthError("建筑已变化，请重新进入布局模式 / Buildings changed; reopen layout") }
        for (id,p) in placements {
            guard placementAllowed(x:p.x,z:p.z,expansion:s.island.expansionLevel),placements.allSatisfy({ other,q in other==id || hypot(p.x-q.x,p.z-q.z)>1.5 }) else { throw HealthError("建筑不能重叠或超出海岸 / Buildings overlap or leave the shore") }
        }
        s.island.placements=placements
    }
    static func teaProblem(_ s:HealthState,now:Date)->String? {
        if !s.preferences.gameEnabled || s.island.paused || s.island.buildingLevel("teaHouse")==0 { return s.preferences.english ? "Tea pavilion unavailable" : "茶亭尚未开放" }
        if s.ledgers[day(now,s),default:DailyLedger()].teaUses>=2 { return s.preferences.english ? "Daily limit reached" : "今日已泡茶 2 次" }
        if s.island.inventory["herb",default:0]<2 || s.island.energy>=100 { return s.preferences.english ? "Need 2 herbs and room for energy" : "需要 2 药材，且活力未满" }
        return nil
    }
    static func brewTea(_ s:inout HealthState,now:Date) throws {
        visit(&s,now:now,welcome:false)
        if let problem=teaProblem(s,now:now) { throw HealthError(problem) }
        let gain=min(100-s.island.energy,Double(8+4*s.island.buildingLevel("teaHouse")))
        s.island.inventory["herb",default:0]-=2;s.island.energy+=gain
        s.ledgers[day(now,s),default:DailyLedger()].teaUses+=1
        log(&s,"tea","茶亭休憩 / Tea break · +\(Int(gain)) 活力 Energy",now)
    }
    static func log(_ s: inout HealthState,_ action: String,_ description: String,_ date: Date) {
        s.island.logs.append(.init(date:date,action:action,description:description))
        if s.island.logs.count > 300 { s.island.logs.removeFirst(s.island.logs.count-300) }
    }
    static func validateRecord(_ r: HealthRecord,now: Date) throws {
        guard r.amount.isFinite && r.amount>0 && r.amount<=100000 && r.occurredAt<=now.addingTimeInterval(5), r.occurredAt > Date(timeIntervalSince1970:0), r.slot >= 0 && r.slot <= 4,
              r.title.count<=200, r.note.count<=4000, r.baseAmount.isFinite && r.baseAmount>0,
              [r.calories,r.protein,r.carbs,r.fat,r.baseCalories,r.baseProtein,r.baseCarbs,r.baseFat].allSatisfy({ $0 == nil || ($0!.isFinite && $0! >= 0 && $0! <= 100000) }) else { throw HealthError("请检查时间、数量和营养值 / Check date, amount and nutrition") }
        if (r.kind == .weight && r.amount>1000) || (r.kind == .exercise && r.amount>1440) || (r.kind == .water && r.amount>10000) { throw HealthError("数量过大，请检查单位 / Check the unit and amount") }
        if r.kind == .meal, let fullness = r.fullnessPercent, !(0...100).contains(fullness) { throw HealthError("饱食程度需要在 0%–100% 之间 / Fullness must be 0%–100%") }
    }
    static func validate(_ s: HealthState) throws {
        guard s.schemaVersion == 2 && s.rulesVersion == 1 else { throw HealthError("不支持此备份版本 / Unsupported backup version") }
        guard Set(s.records.map(\.id)).count == s.records.count,
              [s.island.water,s.island.food,s.island.energy].allSatisfy({ $0.isFinite && $0>=0 && $0<=100 }),
              s.island.inventory.values.allSatisfy({ $0>=0 && $0<100000000 }),
              Set(s.island.inventory.keys).isSubset(of:Set(Catalog.materials)),
              s.island.tools.isSubset(of:Set(Catalog.recipes.filter(\.tool).map(\.id))),
              s.island.buildings.isSubset(of:Set(Catalog.recipes.filter { !$0.tool }.map(\.id))),
              (0...3).contains(s.island.expansionLevel),
              s.island.buildingLevels.allSatisfy({ s.island.buildings.contains($0.key) && (2...4).contains($0.value) }),
              s.island.placements.allSatisfy({ key, point in s.island.buildings.contains(key) && placementAllowed(x:point.x,z:point.z,expansion:s.island.expansionLevel) }),
              s.preferences.cup.isFinite && s.preferences.cup>0 && s.preferences.cup<=10000,
              TimeZone(identifier:s.preferences.timezone) != nil,
              !s.preferences.configs.isEmpty,
              s.preferences.configs.allSatisfy({ (1...4).contains($0.slots) && (0...23).contains($0.restHour) && ($0.waterGoal == nil || ($0.waterGoal!.isFinite && $0.waterGoal!>0 && $0.waterGoal!<=10000)) }),
              s.ledgers.values.allSatisfy({ $0.water>=0 && $0.water<=80 && $0.food>=0 && $0.food<=75 && $0.activity>=0 && $0.activity<=27 && $0.sleepEnergy>=0 && $0.sleepEnergy<=24 && (0...3).contains($0.supplies) && (0...2).contains($0.teaUses) }) else { throw HealthError("存档校验未通过 / Invalid save data") }
        guard Set(s.eventTypes.map(\.id)).count == s.eventTypes.count,
              Set(s.events.map(\.id)).count == s.events.count else { throw HealthError("事项 ID 重复 / Duplicate event IDs") }
        for t in s.eventTypes {
            guard !t.name.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty, t.name.count <= 24, HealthEventType.colors.contains(t.color), HealthEventType.symbols.contains(t.symbol) else { throw HealthError("事项格式无效 / Invalid event type") }
        }
        for e in s.events {
            guard s.eventTypes.contains(where:{$0.id == e.typeID}), (1...999).contains(e.count), e.note.count <= 2000, e.occurredAt.timeIntervalSince1970.isFinite else { throw HealthError("事项记录无效 / Invalid event record") }
        }
        for r in s.records { try validateRecord(r,now:.distantFuture) }
        for t in s.templates { try validateRecord(t.record,now:.distantFuture) }
    }
}
