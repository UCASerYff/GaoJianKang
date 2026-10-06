import Foundation

enum RecordKind: String, Codable, CaseIterable, Identifiable {
    case water, meal, exercise, weight
    var id: String { rawValue }
    var symbol: String { switch self { case .water: "drop.fill"; case .meal: "fork.knife"; case .exercise: "figure.walk"; case .weight: "scalemass.fill" } }
    func title(_ en: Bool) -> String { switch self { case .water: en ? "Water" : "喝水"; case .meal: en ? "Meal" : "饮食"; case .exercise: en ? "Activity" : "运动"; case .weight: en ? "Weight" : "体重" } }
    var unit: String { switch self { case .water: "mL"; case .meal: "份"; case .exercise: "min"; case .weight: "kg" } }
}
enum MealSource: String, Codable, CaseIterable, Identifiable {
    case home, canteen, takeout, snack, restaurant, hotel
    var id: String { rawValue }
    func title(_ en: Bool) -> String {
        switch self {
        case .home: en ? "Home" : "家里"
        case .canteen: en ? "Canteen" : "食堂"
        case .takeout: en ? "Takeout" : "外卖"
        case .snack: en ? "Snack" : "零食"
        case .restaurant: en ? "Restaurant" : "餐馆"
        case .hotel: en ? "Hotel" : "酒店"
        }
    }
}
struct HealthRecord: Codable, Identifiable, Equatable {
    var id = UUID()
    var kind: RecordKind
    var occurredAt = Date()
    var createdAt = Date()
    var updatedAt = Date()
    var timezone = TimeZone.current.identifier
    var title = ""
    var amount: Double = 1
    var calories: Double?
    var protein: Double?
    var carbs: Double?
    var fat: Double?
    var slot = 0
    var note = ""
    var source = "manual"
    var rewardEligible = true
    var baseAmount: Double = 1
    var baseCalories: Double?
    var baseProtein: Double?
    var baseCarbs: Double?
    var baseFat: Double?
    var usesNutrition = false
    var foodUnit = "serving"
    var mealSource: MealSource?
    var fullnessPercent: Int?
}
struct HealthTemplate: Codable, Identifiable {
    var id = UUID()
    var name: String
    var record: HealthRecord
    var uses = 0
}
struct DailyConfig: Codable {
    var effectiveDay: String
    var waterGoal: Double?
    var slots = 3
    var restHour = 23
}
struct Preferences: Codable {
    var english = false
    var appearance = "system"
    var backgroundHex = ""
    var cup: Double = 250
    var hideCalories = false
    var hideWeight = false
    var gameEnabled = true
    var timezone = TimeZone.current.identifier
    var configs = [DailyConfig(effectiveDay: "0000-01-01")]
    var onboarding = false
    func config(_ day: String) -> DailyConfig { configs.filter { $0.effectiveDay <= day }.sorted { $0.effectiveDay < $1.effectiveDay }.last ?? DailyConfig(effectiveDay: "0000-01-01") }
}
struct DailyLedger: Codable {
    var water: Double = 0
    var food: Double = 0
    var activity: Double = 0
    var sleepEnergy: Double = 0
    var welcomed = false
    var supplies = 0
    var harvested = false
    var teaUses = 0
}
extension DailyLedger {
    // Tolerant decoding keeps the memberwise initializer and accepts ledgers written before `harvested` existed.
    private enum LedgerKeys: String, CodingKey { case water, food, activity, sleepEnergy, welcomed, supplies, harvested, teaUses }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: LedgerKeys.self)
        water = try c.decodeIfPresent(Double.self, forKey: .water) ?? 0
        food = try c.decodeIfPresent(Double.self, forKey: .food) ?? 0
        activity = try c.decodeIfPresent(Double.self, forKey: .activity) ?? 0
        sleepEnergy = try c.decodeIfPresent(Double.self, forKey: .sleepEnergy) ?? 0
        welcomed = try c.decodeIfPresent(Bool.self, forKey: .welcomed) ?? false
        supplies = try c.decodeIfPresent(Int.self, forKey: .supplies) ?? 0
        harvested = try c.decodeIfPresent(Bool.self, forKey: .harvested) ?? false
        teaUses = try c.decodeIfPresent(Int.self, forKey: .teaUses) ?? 0
    }
}
struct GameLog: Codable, Identifiable {
    var id = UUID()
    var date: Date
    var action: String
    var description: String
}
struct IslandPoint: Codable, Equatable {
    var x: Double
    var z: Double
}
struct Island: Codable {
    var water: Double = 60
    var food: Double = 60
    var energy: Double = 60
    var lastSettled = Date()
    var lastVisit = Date()
    var lastGift: Date?
    var paused = false
    var inventory: [String: Int] = ["wood":0,"stone":0,"fiber":0,"ration":0]
    var tools: Set<String> = []
    var buildings: Set<String> = []
    var buildingLevels: [String: Int] = [:]
    var placements: [String: IslandPoint] = [:]
    var expansionLevel = 0
    var rewardedSleepIDs: Set<String> = []
    var logs: [GameLog] = []
    static let levelMarks = [0,20,60,100,140,190,260,340,430,520]
    func buildingLevel(_ id: String) -> Int { buildings.contains(id) ? buildingLevels[id] ?? 1 : 0 }
    var prosperity: Int { buildings.count * 20 + tools.count * 5 + buildingLevels.values.reduce(0) { $0 + ($1-1)*10 } + expansionLevel*30 }
    var level: Int { Self.levelMarks.filter { prosperity >= $0 }.count }
    /// Prosperity needed for the next level; nil at the maximum level.
    var nextThreshold: Int? { level >= Self.levelMarks.count ? nil : Self.levelMarks[level] }
    private enum CodingKeys: String, CodingKey { case water, food, energy, lastSettled, lastVisit, lastGift, paused, inventory, tools, buildings, buildingLevels, placements, expansionLevel, rewardedSleepIDs, logs }
    init() {}
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        water = try c.decode(Double.self, forKey:.water)
        food = try c.decode(Double.self, forKey:.food)
        energy = try c.decode(Double.self, forKey:.energy)
        lastSettled = try c.decode(Date.self, forKey:.lastSettled)
        lastVisit = try c.decode(Date.self, forKey:.lastVisit)
        lastGift = try c.decodeIfPresent(Date.self, forKey:.lastGift)
        paused = try c.decode(Bool.self, forKey:.paused)
        inventory = try c.decode([String:Int].self, forKey:.inventory)
        tools = try c.decode(Set<String>.self, forKey:.tools)
        buildings = try c.decode(Set<String>.self, forKey:.buildings)
        buildingLevels = try c.decodeIfPresent([String:Int].self, forKey:.buildingLevels) ?? [:]
        placements = try c.decodeIfPresent([String:IslandPoint].self, forKey:.placements) ?? [:]
        expansionLevel = try c.decodeIfPresent(Int.self, forKey:.expansionLevel) ?? 0
        rewardedSleepIDs = try c.decodeIfPresent(Set<String>.self, forKey:.rewardedSleepIDs) ?? []
        logs = try c.decode([GameLog].self, forKey:.logs)
    }
}
struct HealthState: Codable {
    var schemaVersion = 2
    var rulesVersion = 1
    var records: [HealthRecord] = []
    var templates: [HealthTemplate] = []
    var preferences = Preferences()
    var island = Island()
    var ledgers: [String: DailyLedger] = [:]
    var requests: Set<String> = []
    var updatedAt = Date()
    var lastBackupDay: String?
    var eventTypes = HealthEventType.defaults
    var events: [HealthEvent] = []
    init() {}
    enum CodingKeys: String, CodingKey {
        case schemaVersion, rulesVersion, records, templates, preferences, island, ledgers, requests, updatedAt, lastBackupDay, eventTypes, events
    }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let version = try c.decode(Int.self, forKey: .schemaVersion)
        guard (1...2).contains(version) else { throw HealthError("不支持此存档版本 / Unsupported save version") }
        schemaVersion = 2
        rulesVersion = try c.decode(Int.self, forKey: .rulesVersion)
        records = try c.decode([HealthRecord].self, forKey: .records)
        templates = try c.decode([HealthTemplate].self, forKey: .templates)
        preferences = try c.decode(Preferences.self, forKey: .preferences)
        island = try c.decode(Island.self, forKey: .island)
        ledgers = try c.decode([String: DailyLedger].self, forKey: .ledgers)
        requests = try c.decode(Set<String>.self, forKey: .requests)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        lastBackupDay = try c.decodeIfPresent(String.self, forKey: .lastBackupDay)
        if version == 2 {
            eventTypes = try c.decode([HealthEventType].self, forKey: .eventTypes)
            events = try c.decode([HealthEvent].self, forKey: .events)
        }
    }
}

struct HealthEventType: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var englishName: String = ""
    var symbol = "checkmark.circle"
    var color = "blue"
    var archived = false
    var inWidget = true
    func title(_ en: Bool) -> String { en && !englishName.isEmpty ? englishName : name }
    static let symbols = ["cup.and.saucer.fill", "mug.fill", "waterbottle.fill", "brain.head.profile", "toilet.fill", "pills.fill", "heart.fill", "moon.fill", "figure.walk", "checkmark.circle"]
    static let colors = ["blue", "teal", "orange", "purple", "pink", "green"]
    static let defaults: [HealthEventType] = [
        .init(id:UUID(uuidString:"C21F813B-465B-4835-942F-000000000001")!,name:"喝饮料",englishName:"Soft drink",symbol:"waterbottle.fill",color:"blue"),
        .init(id:UUID(uuidString:"C21F813B-465B-4835-942F-000000000002")!,name:"喝奶茶",englishName:"Milk tea",symbol:"mug.fill",color:"orange"),
        .init(id:UUID(uuidString:"C21F813B-465B-4835-942F-000000000003")!,name:"喝咖啡",englishName:"Coffee",symbol:"cup.and.saucer.fill",color:"teal"),
        .init(id:UUID(uuidString:"C21F813B-465B-4835-942F-000000000004")!,name:"头疼",englishName:"Headache",symbol:"brain.head.profile",color:"purple"),
        .init(id:UUID(uuidString:"C21F813B-465B-4835-942F-000000000005")!,name:"拉屎",englishName:"Bowel movement",symbol:"toilet.fill",color:"green")
    ]
}
struct HealthEvent: Codable, Identifiable, Equatable {
    var id = UUID()
    var typeID: UUID
    var occurredAt = Date()
    var count = 1
    var note = ""
    var source = "manual"
}
struct EventDay: Identifiable {
    var date: Date
    var count: Int
    var id: Date { date }
}
enum EventLog {
    static func save(_ s: inout HealthState, _ event: HealthEvent, now: Date = Date()) throws {
        guard s.eventTypes.contains(where: { $0.id == event.typeID && (!$0.archived || s.events.contains(where: { $0.id == event.id })) }) else { throw HealthError("事项已停用或不存在 / Event type unavailable") }
        guard event.count > 0 && event.count <= 999 && event.note.count <= 2000 && event.occurredAt <= now.addingTimeInterval(60) else { throw HealthError("检查次数（1–999）和记录时间，不支持未来记录 / Check count and date") }
        if let i = s.events.firstIndex(where: { $0.id == event.id }) { s.events[i] = event } else { s.events.append(event) }
    }
    static func saveType(_ s: inout HealthState, _ type: HealthEventType) throws {
        var t = type; t.name = t.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.name.isEmpty && t.name.count <= 24 && HealthEventType.colors.contains(t.color) && HealthEventType.symbols.contains(t.symbol) else { throw HealthError("请填写 1–24 字事项名称 / Enter a name (1–24 characters)") }
        guard !s.eventTypes.contains(where: { $0.id != t.id && $0.name.caseInsensitiveCompare(t.name) == .orderedSame }) else { throw HealthError("已有同名事项 / Name already exists") }
        if let i = s.eventTypes.firstIndex(where: { $0.id == t.id }) { s.eventTypes[i] = t } else { s.eventTypes.append(t) }
    }
    static func month(_ date: Date, state: HealthState, type: UUID? = nil) -> [EventDay] {
        let cal = Engine.calendar(state)
        guard let range = cal.dateInterval(of: .month, for: date), let days = cal.range(of: .day, in: .month, for: date) else { return [] }
        var totals: [String:Int] = [:]
        for e in state.events where (type == nil || e.typeID == type) && range.contains(e.occurredAt) && e.occurredAt < range.end {
            totals[Engine.day(e.occurredAt,state),default:0] += e.count
        }
        return days.compactMap { day in cal.date(byAdding:.day,value:day-1,to:range.start).map { EventDay(date:$0,count:totals[Engine.day($0,state),default:0]) } }
    }
    static func level(_ count: Int) -> Int { count <= 0 ? 0 : min(count, 4) }
    static func export(_ state: HealthState) -> String {
        let f = ISO8601DateFormatter()
        var rows = [["id","type_id","name","occurred_at","count","note","source"]]
        rows += state.events.sorted { $0.occurredAt < $1.occurredAt }.map { e in [e.id.uuidString,e.typeID.uuidString,state.eventTypes.first(where:{$0.id == e.typeID})?.name ?? "",f.string(from:e.occurredAt),String(e.count),e.note,e.source] }
        return "\u{FEFF}" + rows.map { $0.map(HealthCSV.cell).joined(separator:",") }.joined(separator:"\r\n")
    }
}
struct HealthError: LocalizedError {
    var message: String
    var errorDescription: String? { message }
    init(_ message: String) { self.message = message }
}
struct Recipe: Identifiable {
    let id: String
    let cn: String
    let en: String
    let symbol: String
    let cost: [String: Int]
    let detailCN: String
    let detailEN: String
    var prerequisite: String? = nil
    var tool = false
    var minimumExpansion = 0
    func title(_ en: Bool) -> String { en ? self.en : cn }
}
enum Catalog {
    static let defaultSites: [String:IslandPoint] = [
        "campfire": .init(x:-1.7,z:0.7), "shelter": .init(x:1.1,z:-1.1), "well": .init(x:2.8,z:0.7),
        "garden": .init(x:-3.4,z:-1.9), "farm": .init(x:3.5,z:-2.2), "herbGarden": .init(x:-1.3,z:-3),
        "clinic": .init(x:3.2,z:3), "training": .init(x:-3.6,z:2.7),
        "rainCollector": .init(x:0,z:3.8), "orchard": .init(x:5.4,z:0),
        "workshop": .init(x:-4.9,z:0.6), "windmill": .init(x:-4.9,z:-3.5),
        "kitchen": .init(x:0,z:-5.2), "teaHouse": .init(x:1.1,z:5.6)
    ]
    static let materials = ["wood", "stone", "fiber", "ration", "iron", "herb"]
    static func name(_ key: String, _ en: Bool) -> String {
        let names = ["wood": ["木材","Wood"], "stone":["石材","Stone"], "fiber":["纤维","Fiber"], "ration":["干粮","Rations"], "iron":["铁矿","Iron ore"], "herb":["药材","Herbs"]]
        return names[key]?[en ? 1 : 0] ?? key
    }
    static func symbol(_ key: String) -> String { ["wood":"tree.fill","stone":"mountain.2.fill","fiber":"leaf.fill","ration":"fish.fill","iron":"cube.fill","herb":"cross.case.fill"][key] ?? "shippingbox.fill" }
    static let recipes: [Recipe] = [
        .init(id:"campfire",cn:"篝火",en:"Campfire",symbol:"flame.fill",cost:["wood":6,"stone":2],detailCN:"解锁叉鱼 · 繁荣度 +20",detailEN:"Unlock fishing · +20 prosperity"),
        .init(id:"shelter",cn:"木棚",en:"Shelter",symbol:"house.fill",cost:["wood":12,"fiber":6],detailCN:"休息时段衰减降低 25%",detailEN:"25% less decay during rest"),
        .init(id:"well",cn:"水井",en:"Well",symbol:"drop.circle.fill",cost:["wood":6,"stone":8,"fiber":4],detailCN:"水分衰减降低 25%",detailEN:"25% less water decay",prerequisite:"pickaxe"),
        .init(id:"garden",cn:"菜园",en:"Garden",symbol:"carrot.fill",cost:["wood":8,"fiber":4],detailCN:"每日首次到岛 +2 干粮",detailEN:"+2 rations on first daily visit"),
        .init(id:"farm",cn:"农田",en:"Farm",symbol:"square.grid.2x2.fill",cost:["wood":20,"stone":10,"fiber":8],detailCN:"每日首次到岛 +5 干粮",detailEN:"+5 rations on first daily visit",prerequisite:"garden"),
        .init(id:"herbGarden",cn:"药圃",en:"Herb garden",symbol:"leaf.arrow.circlepath",cost:["wood":6,"stone":2,"fiber":4],detailCN:"解锁采药",detailEN:"Unlock herb gathering"),
        .init(id:"clinic",cn:"医馆",en:"Clinic",symbol:"cross.case.fill",cost:["wood":15,"stone":12,"herb":5],detailCN:"每日首次到岛 +5 活力",detailEN:"+5 energy on first daily visit",prerequisite:"herbGarden"),
        .init(id:"training",cn:"训练场",en:"Training ground",symbol:"figure.strengthtraining.traditional",cost:["wood":12,"stone":8],detailCN:"运动奖励 +25%",detailEN:"+25% activity rewards"),
        .init(id:"rainCollector",cn:"雨水收集站",en:"Rain collector",symbol:"cloud.rain.fill",cost:["wood":16,"stone":10,"fiber":8],detailCN:"每日首次到岛恢复水分，每级 +6，上限 100",detailEN:"First daily visit: +6 water per level, capped at 100"),
        .init(id:"orchard",cn:"果园",en:"Orchard",symbol:"tree.fill",cost:["wood":24,"fiber":14,"ration":6],detailCN:"每日首次到岛收获干粮，每级 +2",detailEN:"First daily visit: +2 rations per level",prerequisite:"garden",minimumExpansion:1),
        .init(id:"workshop",cn:"工坊",en:"Workshop",symbol:"hammer.fill",cost:["wood":30,"stone":20,"iron":5],detailCN:"所有采集行动的活力消耗每级降低 5%",detailEN:"Gathering energy cost reduced by 5% per level",prerequisite:"pickaxe",minimumExpansion:1),
        .init(id:"windmill",cn:"风车",en:"Windmill",symbol:"wind",cost:["wood":30,"stone":25,"iron":8],detailCN:"割藤采麻每次额外获得纤维，每级 +1",detailEN:"Gathering fiber yields +1 extra per level",prerequisite:"workshop",minimumExpansion:2),
        .init(id:"kitchen",cn:"厨房",en:"Kitchen",symbol:"oven.fill",cost:["wood":20,"stone":30,"iron":6],detailCN:"每份干粮额外恢复饱食，每级 +3；仍限每日 3 次",detailEN:"Rations restore +3 extra food per level; still 3 uses per day",prerequisite:"campfire",minimumExpansion:1),
        .init(id:"teaHouse",cn:"茶亭",en:"Tea pavilion",symbol:"cup.and.saucer.fill",cost:["wood":28,"stone":12,"fiber":15,"herb":8],detailCN:"每次消耗 2 药材恢复 8+4×等级活力，每日最多 2 次",detailEN:"Brew with 2 herbs: restore 8+4×level energy, twice per day",prerequisite:"herbGarden",minimumExpansion:2),
        .init(id:"axe",cn:"石斧",en:"Stone axe",symbol:"hammer.fill",cost:["wood":3,"stone":2,"fiber":2],detailCN:"砍树产量 ×2",detailEN:"Double wood yield",tool:true),
        .init(id:"pickaxe",cn:"石镐",en:"Stone pickaxe",symbol:"wrench.and.screwdriver.fill",cost:["wood":3,"stone":3,"fiber":2],detailCN:"解锁采石与挖矿",detailEN:"Unlock quarry and mining",tool:true),
        .init(id:"spear",cn:"鱼叉",en:"Fishing spear",symbol:"fish.fill",cost:["wood":4,"fiber":3],detailCN:"叉鱼产量 ×2",detailEN:"Double fishing yield",tool:true),
        .init(id:"ironAxe",cn:"铁斧",en:"Iron axe",symbol:"hammer.fill",cost:["wood":5,"iron":4,"fiber":3],detailCN:"砍树产量 ×3",detailEN:"Triple wood yield",tool:true),
        .init(id:"ironPickaxe",cn:"铁镐",en:"Iron pickaxe",symbol:"wrench.and.screwdriver.fill",cost:["wood":4,"iron":5],detailCN:"采石与挖矿产量 ×2",detailEN:"Double quarry and mining yield",tool:true),
        .init(id:"net",cn:"渔网",en:"Fishing net",symbol:"circle.hexagongrid.fill",cost:["wood":6,"fiber":10],detailCN:"叉鱼产量 ×3",detailEN:"Triple fishing yield",tool:true)
    ]
    struct Action: Identifiable {
        let id: String; let cn: String; let en: String; let symbol: String
        let energy: Double; let food: Double; let water: Double
        let output: String; let quantity: Int; let need: String?
        func title(_ en: Bool) -> String { en ? self.en : cn }
    }
    static let actions: [Action] = [
        .init(id:"chop",cn:"砍树",en:"Chop wood",symbol:"tree.fill",energy:8,food:5,water:0,output:"wood",quantity:3,need:nil),
        .init(id:"fiber",cn:"割藤采麻",en:"Gather fiber",symbol:"leaf.fill",energy:5,food:0,water:0,output:"fiber",quantity:3,need:nil),
        .init(id:"pebble",cn:"敲碎石",en:"Break pebbles",symbol:"mountain.2.fill",energy:6,food:0,water:0,output:"stone",quantity:1,need:nil),
        .init(id:"quarry",cn:"采石",en:"Quarry",symbol:"hammer.fill",energy:10,food:6,water:0,output:"stone",quantity:4,need:"pickaxe"),
        .init(id:"mine",cn:"挖矿",en:"Mine iron",symbol:"cube.fill",energy:12,food:6,water:0,output:"iron",quantity:2,need:"pickaxe"),
        .init(id:"fish",cn:"叉鱼",en:"Catch fish",symbol:"fish.fill",energy:6,food:0,water:3,output:"ration",quantity:2,need:"campfire"),
        .init(id:"coconut",cn:"采椰摘果",en:"Pick coconuts",symbol:"carrot.fill",energy:4,food:0,water:0,output:"ration",quantity:1,need:nil),
        .init(id:"herb",cn:"采药",en:"Gather herbs",symbol:"cross.case.fill",energy:6,food:0,water:0,output:"herb",quantity:2,need:"herbGarden")
    ]
}
