import SwiftUI
import WidgetKit
import AppIntents

struct QuickWaterIntent: AppIntent {
    static var title: LocalizedStringResource = "记一杯水 / Log water"
    static var openAppWhenRun = false
    @Parameter(title:"Request") var requestID: String
    init() { requestID=UUID().uuidString }
    init(request:String) { requestID=request }
    func perform() async throws -> some IntentResult {
        let db=try HealthDatabase()
        _ = try db.transaction(request:requestID) { state in
            var r=HealthRecord(kind:.water); r.amount=state.preferences.cup; r.source="widget"
            try Engine.save(&state,record:r,now:Date())
        }
        try? db.automaticBackup()
        return .result()
    }
}
struct HealthEntry: TimelineEntry { let date:Date; var state:HealthState?; var request=UUID().uuidString }
struct HealthProvider: TimelineProvider {
    func placeholder(in context:Context)->HealthEntry { .init(date:Date(),state:HealthState()) }
    func getSnapshot(in context:Context,completion:@escaping(HealthEntry)->Void) { completion(entry(Date())) }
    func getTimeline(in context:Context,completion:@escaping(Timeline<HealthEntry>)->Void) {
        let now=Date(); let entries=(0..<5).map { entry(now.addingTimeInterval(Double($0)*900)) }
        completion(.init(entries:entries,policy:.after(now.addingTimeInterval(3600))))
    }
    private func entry(_ date:Date)->HealthEntry {
        var state=try? HealthDatabase().read()
        if var s=state { Engine.settle(&s,now:date); state=s }
        return .init(date:date,state:state)
    }
}
struct HealthWidgetView: View {
    var entry:HealthEntry
    @Environment(\.widgetFamily) var family
    var body: some View {
        Group {
            if let s=entry.state { content(s) }
            else { VStack(alignment:.leading,spacing:8) { Text("搞健康").font(.headline); Text("请先打开 App\nOpen the app to get started").font(.caption).foregroundStyle(.secondary); Link("打开 / Open",destination:URL(string:"gaojiankang://today")!) } }
        }.containerBackground(for:.widget) { Color(nsColor:.windowBackgroundColor) }
        .widgetURL(URL(string:"gaojiankang://today"))
    }
    private func content(_ s:HealthState)->some View {
        let en=s.preferences.english
        return HStack(spacing:18) {
            VStack(alignment:.leading,spacing:8) {
                HStack { Text(en ? "Gao Health" : "搞健康").font(.headline); Spacer(); if s.preferences.gameEnabled { Text("Lv.\(s.island.level)").font(.caption).foregroundStyle(.secondary) } }
                if s.preferences.gameEnabled {
                    meter(en ? "Water" : "水分",s.island.water,.blue)
                    meter(en ? "Food" : "饱食",s.island.food,.orange)
                    meter(en ? "Energy" : "活力",s.island.energy,.green)
                } else {
                    let today=Engine.day(entry.date,s)
                    Text("\(Int(s.records.filter{$0.kind == .water && Engine.day($0.occurredAt,s)==today}.reduce(0){$0+$1.amount})) mL").font(.title2.weight(.semibold))
                    Text(en ? "Water logged today" : "今日饮水记录").font(.caption).foregroundStyle(.secondary)
                }
                Button(intent:QuickWaterIntent(request:entry.request)) { Label("+\(Int(s.preferences.cup)) mL",systemImage:"drop.fill").font(.caption.weight(.semibold)).frame(maxWidth:.infinity) }.tint(.teal)
            }.frame(maxWidth:.infinity)
            if family == .systemMedium || family == .systemLarge {
                VStack(alignment:.leading,spacing:12) {
                    Image(systemName:"tree.fill").font(.system(size:28)).foregroundStyle(.teal)
                    Text(s.island.paused ? (en ? "Island resting" : "岛屿休整中") : (en ? "A little, every day." : "记录一点，生长一点")).font(.caption).foregroundStyle(.secondary)
                    Link(destination:URL(string:"gaojiankang://meal")!) { Label(en ? "Meal" : "记一餐",systemImage:"fork.knife") }
                    Link(destination:URL(string:"gaojiankang://exercise")!) { Label(en ? "Activity" : "记运动",systemImage:"figure.walk") }
                    Text(s.updatedAt,style:.time).font(.system(size:9)).foregroundStyle(.tertiary)
                }.font(.caption).frame(width:115,alignment:.leading)
            }
            if family == .systemLarge {
                let today=Engine.day(entry.date,s)
                let water=s.records.filter{$0.kind == .water && Engine.day($0.occurredAt,s)==today}.reduce(0){$0+$1.amount}
                let active=s.records.filter{$0.kind == .exercise && Engine.day($0.occurredAt,s)==today}.reduce(0){$0+$1.amount}
                let meals=s.records.filter{$0.kind == .meal && Engine.day($0.occurredAt,s)==today}.count
                VStack(alignment:.leading,spacing:10) {
                    Text(en ? "Today" : "今日").font(.caption.weight(.semibold))
                    Label("\(Int(water)) mL",systemImage:"drop.fill")
                    Label("\(meals) " + (en ? "meals" : "餐"),systemImage:"fork.knife")
                    Label("\(Int(active)) min",systemImage:"figure.walk")
                    Link(destination:URL(string:"gaojiankang://weight")!) { Label(en ? "Weight" : "记体重",systemImage:"scalemass.fill") }
                    Link(destination:URL(string:"gaojiankang://events")!) { Label(en ? "Events" : "快速事项",systemImage:"square.grid.3x3.fill") }
                }.font(.caption).foregroundStyle(.secondary).frame(width:110,alignment:.leading)
            }
        }
    }
    private func meter(_ title:String,_ value:Double,_ color:Color)->some View {
        HStack(spacing:6) { Text(title).font(.system(size:10)).frame(width:34,alignment:.leading); ProgressView(value:value,total:100).tint(color); Text("\(Int(value))").font(.system(size:10,design:.monospaced)).frame(width:20,alignment:.trailing) }
    }
}
struct HealthWidgets: Widget {
    let kind="GaoJianKangWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind:kind,provider:HealthProvider()) { HealthWidgetView(entry:$0) }
            .configurationDisplayName("搞健康 · 日常与小岛")
            .description("记一杯水，让你的小岛慢慢生长。Log water and watch your island grow.")
            .supportedFamilies([.systemSmall,.systemMedium,.systemLarge])
    }
}

struct EventTypeEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "健康事项 / Health event"
    static var defaultQuery = EventTypeQuery()
    var id: String
    var name: String
    var displayRepresentation: DisplayRepresentation { .init(title:"\(name)") }
}
struct EventTypeQuery: EntityQuery {
    func entities(for identifiers:[String]) async throws -> [EventTypeEntity] {
        let s=try HealthDatabase().read()
        return s.eventTypes.filter { identifiers.contains($0.id.uuidString) }.map { .init(id:$0.id.uuidString,name:$0.title(s.preferences.english)) }
    }
    func suggestedEntities() async throws -> [EventTypeEntity] {
        let s=try HealthDatabase().read()
        return s.eventTypes.filter { !$0.archived }.map { .init(id:$0.id.uuidString,name:$0.title(s.preferences.english)) }
    }
}
struct EventConfiguration: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "快速事项 / Quick events"
    static var description = IntentDescription("选择一个事项；留空显示全部。Select a type, or leave empty for all events.")
    @Parameter(title:"事项（留空显示全部） / Event") var eventType: EventTypeEntity?
}
struct LogHealthEventIntent: AppIntent {
    static var title: LocalizedStringResource = "记一次 / Log event"
    static var openAppWhenRun = false
    @Parameter(title:"Type") var typeID: String
    @Parameter(title:"Request") var requestID: String
    init() { typeID=""; requestID=UUID().uuidString }
    init(type:UUID,request:String) { typeID=type.uuidString; requestID=request }
    func perform() async throws -> some IntentResult {
        guard let id=UUID(uuidString:typeID) else { throw HealthError("Invalid event type") }
        let db=try HealthDatabase()
        try db.transaction(request:requestID) { s in
            var e=HealthEvent(typeID:id); e.source="widget"; try EventLog.save(&s,e)
        }
        try? db.automaticBackup()
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
struct EventWidgetEntry: TimelineEntry {
    let date:Date
    var state:HealthState?
    var typeID:UUID?
    var request=UUID().uuidString
}
struct EventWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context:Context) -> EventWidgetEntry { preview() }
    func snapshot(for configuration:EventConfiguration,in context:Context) async -> EventWidgetEntry {
        context.isPreview ? preview() : entry(configuration)
    }
    func timeline(for configuration:EventConfiguration,in context:Context) async -> Timeline<EventWidgetEntry> {
        let e=entry(configuration)
        return Timeline(entries:[e],policy:.after(Date().addingTimeInterval(900)))
    }
    private func entry(_ c:EventConfiguration) -> EventWidgetEntry { .init(date:Date(),state:try? HealthDatabase().read(),typeID:c.eventType.flatMap { UUID(uuidString:$0.id) }) }
    private func preview() -> EventWidgetEntry {
        var s=HealthState()
        let cal=Engine.calendar(s)
        if let start=cal.dateInterval(of:.month,for:Date())?.start {
            for day in 0..<cal.component(.day,from:Date()) where day%4 != 0 {
                s.events.append(HealthEvent(typeID:s.eventTypes[day%5].id,occurredAt:cal.date(byAdding:.day,value:day,to:start)!,count:day%4+1))
            }
        }
        return .init(date:Date(),state:s)
    }
}
struct EventWidgetView: View {
    let entry:EventWidgetEntry
    @Environment(\.widgetFamily) private var family
    var body: some View {
        Group {
            if let s=entry.state { content(s) }
            else { Link("打开搞健康 / Open Gao Health",destination:URL(string:"gaojiankang://events")!) }
        }.containerBackground(for:.widget) { Color(nsColor:.windowBackgroundColor) }
        .widgetURL(URL(string:"gaojiankang://events"))
    }
    private func color(_ key:String) -> Color {
        switch key { case "teal": .teal; case "orange": .orange; case "purple": .purple; case "pink": .pink; case "green": .green; default: .blue }
    }
    private func content(_ s:HealthState) -> some View {
        let en=s.preferences.english
        let type=s.eventTypes.first { $0.id == entry.typeID }
        let days=EventLog.month(entry.date,state:s,type:entry.typeID)
        let selected=s.eventTypes.filter { !$0.archived && (entry.typeID == nil ? $0.inWidget : $0.id == entry.typeID) }
        return VStack(alignment:.leading,spacing:family == .systemSmall ? 5 : 10) {
            HStack {
                Text(type?.title(en) ?? (en ? "Quick events" : "快速事项")).font(.headline).lineLimit(1)
                Spacer(minLength:4)
                Text("\(Engine.calendar(s).component(.month,from:entry.date))"+(en ? " / mo" : " 月")).font(.caption).foregroundStyle(.secondary)
            }
            if family == .systemMedium {
                HStack(alignment:.top,spacing:16) {
                    grid(days,s,color(type?.color ?? "blue")).frame(maxWidth:.infinity)
                    VStack(alignment:.leading,spacing:7) {
                        Text(en ? "\(days.reduce(0){$0+$1.count}) this month" : "本月 \(days.reduce(0){$0+$1.count}) 次").font(.caption).foregroundStyle(.secondary)
                        ForEach(Array(selected.prefix(3))) { shortcut($0,s) }
                        if selected.count>3 { Link(en ? "All events →" : "全部事项 →",destination:URL(string:"gaojiankang://events")!).font(.caption2) }
                    }.frame(width:115)
                }
            } else {
                grid(days,s,color(type?.color ?? "blue"))
                HStack { Text(en ? "\(days.reduce(0){$0+$1.count}) this month" : "本月 \(days.reduce(0){$0+$1.count}) 次").font(.caption2).foregroundStyle(.secondary); Spacer(); if family == .systemSmall, let type=type, !type.archived { shortcut(type,s) } }
                if family == .systemLarge {
                    LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:8) { ForEach(Array(selected.prefix(8))) { shortcut($0,s) } }
                }
            }
        }
    }
    private func shortcut(_ type:HealthEventType,_ s:HealthState) -> some View {
        Button(intent:LogHealthEventIntent(type:type.id,request:entry.request+type.id.uuidString)) {
            HStack(spacing:4) { Image(systemName:type.symbol); Text(type.title(s.preferences.english)).lineLimit(1).minimumScaleFactor(0.7); Spacer(minLength:0); Text("+1") }.font(.caption2)
        }.tint(color(type.color))
    }
    private func grid(_ days:[EventDay],_ s:HealthState,_ tint:Color) -> some View {
        let cal=Engine.calendar(s)
        let offset=days.first.map { (cal.component(.weekday,from:$0.date)+5)%7 } ?? 0
        let headers=s.preferences.english ? ["M","T","W","T","F","S","S"] : ["一","二","三","四","五","六","日"]
        return LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:3),count:7),spacing:3) {
            ForEach(0..<7,id:\.self) { Text(headers[$0]).font(.system(size:8)).foregroundStyle(.secondary) }
            ForEach(0..<offset,id:\.self) { _ in Color.clear.frame(height:family == .systemLarge ? 21 : 12) }
            ForEach(days) { day in
                let level=EventLog.level(day.count)
                RoundedRectangle(cornerRadius:3).fill(level == 0 ? Color.primary.opacity(0.055) : tint.opacity(Double(level)*0.22+0.10))
                    .frame(height:family == .systemLarge ? 21 : 12)
                    .overlay(Text("\(cal.component(.day,from:day.date))").font(.system(size:family == .systemLarge ? 10 : 7)).foregroundStyle(level>=3 ? .white : .primary))
                    .accessibilityLabel("\(Engine.day(day.date,s)): \(day.count)")
            }
        }
    }
}
struct QuickEventsWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind:"GaoJianKangQuickEvents",intent:EventConfiguration.self,provider:EventWidgetProvider()) { EventWidgetView(entry:$0) }
            .configurationDisplayName("搞健康 · 快速事项月历")
            .description("一键记录自定义事项，月历颜色越深代表次数越多。编辑小组件可选择事项。")
            .supportedFamilies([.systemSmall,.systemMedium,.systemLarge])
    }
}
@main struct GaoHealthWidgetBundle: WidgetBundle {
    var body: some Widget { HealthWidgets(); QuickEventsWidget() }
}
