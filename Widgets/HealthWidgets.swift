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
        let db=try HealthDatabase(access:.readWriteExisting)
        let now=Date()
        // Every invocation is a new user action. A cached Timeline entry may be
        // shared by several instances and cannot serve as the operation identity.
        _ = try db.transaction(request:"widget-water-"+UUID().uuidString,now:now) { state in
            var r=HealthRecord(kind:.water); r.amount=state.preferences.cup; r.source="widget"
            r.timezone=state.preferences.timezone; r.occurredAt=now
            try Engine.save(&state,record:r,now:now)
        }
        // Successful database commits publish and notify both widget kinds and App.
        try? db.automaticBackup()
        return .result()
    }
}
struct RefreshHealthWidgetsIntent: AppIntent {
    static var title: LocalizedStringResource = "刷新健康资料 / Refresh health data"
    static var openAppWhenRun = false
    func perform() async throws -> some IntentResult {
        HealthWidgetData.requestRefresh()
        return .result()
    }
}
/// Entry metadata is deliberately small: timeline entries never contain a second
/// copy of the full business snapshot just to render its clocks.
struct WidgetSourceStatus {
    var sourceUpdatedAt: Date?
    var generatedAt: Date?
    var readAt: Date?
    var latestRecordAt: Date?
    var attemptedAt: Date
    var isStale: Bool
    var error: String?
    var english: Bool
    var timezone: String
    init(_ result: HealthWidgetReadResult) {
        sourceUpdatedAt=result.snapshot?.sourceUpdatedAt; generatedAt=result.snapshot?.generatedAt
        readAt=result.snapshot?.readAt; latestRecordAt=result.snapshot?.latestRecordAt
        attemptedAt=result.attemptedAt; isStale=result.isStale; error=result.error
        english=result.snapshot?.state.preferences.english ?? false
        timezone=result.snapshot?.state.preferences.timezone ?? TimeZone.current.identifier
    }
}
private struct WidgetDataStatus: View {
    let source: WidgetSourceStatus?
    let scheduledAt: Date
    var body: some View {
        if let source {
            HStack(alignment:.bottom,spacing:4) {
                VStack(alignment:.leading,spacing:1) {
                    if let updated=source.sourceUpdatedAt, let read=source.readAt {
                        Text((source.english ? "Data " : "资料 ")+stamp(updated,source))
                        Text((source.english ? "Read " : "读取 ")+stamp(read,source))
                    }
                    if source.isStale {
                        Text(source.english ? "Read failed · cached" : "读取失败 · 上次资料").foregroundStyle(.orange)
                    } else if source.error != nil {
                        Text(source.english ? "Sync pending" : "同步待重试").foregroundStyle(.orange)
                    }
                }.font(.system(size:8)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
                Spacer(minLength:0)
                Button(intent:RefreshHealthWidgetsIntent()) { Image(systemName:"arrow.clockwise").font(.system(size:10)) }
                    .buttonStyle(.plain).accessibilityLabel(source.english ? "Refresh health data" : "刷新健康资料")
            }.help(details(source)).accessibilityElement(children:.contain)
        }
    }
    private func stamp(_ date:Date,_ source:WidgetSourceStatus)->String {
        let formatter=DateFormatter(); formatter.locale=Locale(identifier:source.english ? "en_US_POSIX" : "zh_CN")
        formatter.timeZone=TimeZone(identifier:source.timezone) ?? .current
        formatter.dateFormat="M/d HH:mm"
        return formatter.string(from:date)
    }
    private func details(_ source:WidgetSourceStatus)->String {
        var lines:[String]=[]
        if let date=source.sourceUpdatedAt { lines.append((source.english ? "Business data changed: " : "业务资料变更：")+stamp(date,source)) }
        if let date=source.latestRecordAt { lines.append((source.english ? "Latest record: " : "最近记录发生：")+stamp(date,source)) }
        if let date=source.generatedAt { lines.append((source.english ? "Snapshot generated: " : "快照生成：")+stamp(date,source)) }
        if let date=source.readAt { lines.append((source.english ? "Last successful read: " : "上次成功读取：")+stamp(date,source)) }
        lines.append((source.english ? "Read attempted: " : "本次尝试读取：")+stamp(source.attemptedAt,source))
        lines.append((source.english ? "Scheduled statistics time: " : "计划统计时间：")+stamp(scheduledAt,source))
        lines.append(source.english ? "Scheduled time is not an observation of the desktop display." : "计划时间不代表已观测到桌面显示。")
        if let error=source.error { lines.append(error) }
        return lines.joined(separator:"\n")
    }
}
/// Keep only the business rows needed by this entry. The verified on-disk cache
/// remains complete; these smaller display copies are never saved to the DB.
private func widgetDisplayState(_ state:HealthState,at date:Date,events:Bool)->HealthState {
    var result=state
    result.templates=[]; result.ledgers=[:]; result.requests=[]
    result.island.logs=[]; result.island.rewardedSleepIDs=[]
    if events {
        result.records=[]
        let month=Engine.calendar(state).dateInterval(of:.month,for:date)
        result.events=state.events.filter { month?.contains($0.occurredAt) == true }
    } else {
        let day=Engine.day(date,state)
        result.records=state.records.filter { Engine.day($0.occurredAt,state) == day }
        result.events=[]; result.eventTypes=[]
    }
    return result
}
struct HealthEntry: TimelineEntry {
    let date:Date
    var state:HealthState?
    var source:WidgetSourceStatus? = nil
    var request=UUID().uuidString
    var statisticsDate:Date { source?.isStale == true ? (source?.readAt ?? date) : date }
}
struct HealthProvider: TimelineProvider {
    func placeholder(in context:Context)->HealthEntry { .init(date:Date(),state:HealthState()) }
    func getSnapshot(in context:Context,completion:@escaping(HealthEntry)->Void) {
        if context.isPreview { completion(placeholder(in:context)); return }
        let now=Date(),source=HealthWidgetData.load(kind:"health-snapshot")
        completion(entry(now,source))
    }
    func getTimeline(in context:Context,completion:@escaping(Timeline<HealthEntry>)->Void) {
        let now=Date(),source=HealthWidgetData.load(now:now,kind:"health-timeline-read")
        let calendar=source.snapshot.map { Engine.calendar($0.state) } ?? Calendar.current
        let dates=HealthWidgetData.timelineDates(now:now,calendar:calendar)
        HealthWidgetData.recordTimeline(kind:"health-timeline-plan",result:source,dates:dates)
        completion(.init(entries:dates.map { entry($0,source) },policy:.after(now.addingTimeInterval(1800))))
    }
    private func entry(_ date:Date,_ source:HealthWidgetReadResult)->HealthEntry {
        let statisticsDate=source.isStale ? (source.snapshot?.readAt ?? date) : date
        let state=source.snapshot.map {
            widgetDisplayState(source.isStale ? $0.state : HealthWidgetData.projectedState($0,at:date),at:statisticsDate,events:false)
        }
        return .init(date:date,state:state,source:WidgetSourceStatus(source))
    }
}
struct HealthWidgetView: View {
    var entry:HealthEntry
    @Environment(\.widgetFamily) var family
    var body: some View {
        VStack(alignment:.leading,spacing:5) {
            if let s=entry.state { content(s) }
            else { VStack(alignment:.leading,spacing:8) { Text("搞健康").font(.headline); Text("健康资料暂不可读取\nHealth data unavailable").font(.caption).foregroundStyle(.secondary); Link("打开 / Open",destination:URL(string:"gaojiankang://today")!) } }
            WidgetDataStatus(source:entry.source,scheduledAt:entry.date)
        }.containerBackground(for:.widget) { Color(nsColor:.windowBackgroundColor) }
        .widgetURL(URL(string:"gaojiankang://today"))
    }
    private func content(_ s:HealthState)->some View {
        let en=s.preferences.english
        return HStack(spacing:family == .systemLarge ? 10 : 18) {
            VStack(alignment:.leading,spacing:8) {
                HStack { Text(en ? "Gao Health" : "搞健康").font(.headline); Spacer(); if s.preferences.gameEnabled { Text("Lv.\(s.island.level)").font(.caption).foregroundStyle(.secondary) } }
                if s.preferences.gameEnabled {
                    meter(en ? "Water" : "水分",s.island.water,.blue)
                    meter(en ? "Food" : "饱食",s.island.food,.orange)
                    meter(en ? "Energy" : "活力",s.island.energy,.green)
                } else {
                    let today=Engine.day(entry.statisticsDate,s)
                    Text("\(Int(s.records.filter{$0.kind == .water && Engine.day($0.occurredAt,s)==today}.reduce(0){$0+$1.amount})) mL").font(.title2.weight(.semibold))
                    Text(entry.source?.isStale == true ? (en ? "Water on cached day" : "缓存当日饮水") : (en ? "Water logged today" : "今日饮水记录")).font(.caption).foregroundStyle(.secondary)
                }
                Button(intent:QuickWaterIntent(request:entry.request)) { Label("+\(Int(s.preferences.cup)) mL",systemImage:"drop.fill").font(.caption.weight(.semibold)).frame(maxWidth:.infinity) }.tint(.teal)
                    .disabled(entry.source?.isStale == true)
            }.frame(maxWidth:.infinity)
            if family == .systemMedium || family == .systemLarge {
                VStack(alignment:.leading,spacing:12) {
                    Image(systemName:"tree.fill").font(.system(size:28)).foregroundStyle(.teal)
                    Text(s.island.paused ? (en ? "Island resting" : "岛屿休整中") : (en ? "A little, every day." : "记录一点，生长一点")).font(.caption).foregroundStyle(.secondary)
                    Link(destination:URL(string:"gaojiankang://meal")!) { Label(en ? "Meal" : "记一餐",systemImage:"fork.knife") }
                    Link(destination:URL(string:"gaojiankang://exercise")!) { Label(en ? "Activity" : "记运动",systemImage:"figure.walk") }
                }.font(.caption).frame(width:family == .systemLarge ? 82 : 115,alignment:.leading)
            }
            if family == .systemLarge {
                let today=Engine.day(entry.statisticsDate,s)
                let water=s.records.filter{$0.kind == .water && Engine.day($0.occurredAt,s)==today}.reduce(0){$0+$1.amount}
                let active=s.records.filter{$0.kind == .exercise && Engine.day($0.occurredAt,s)==today}.reduce(0){$0+$1.amount}
                let meals=s.records.filter{$0.kind == .meal && Engine.day($0.occurredAt,s)==today}.count
                VStack(alignment:.leading,spacing:10) {
                    Text(entry.source?.isStale == true ? (en ? "Cached day" : "缓存当日") : (en ? "Today" : "今日")).font(.caption.weight(.semibold))
                    Label("\(Int(water)) mL",systemImage:"drop.fill")
                    Label("\(meals) " + (en ? "meals" : "餐"),systemImage:"fork.knife")
                    Label("\(Int(active)) min",systemImage:"figure.walk")
                    Link(destination:URL(string:"gaojiankang://weight")!) { Label(en ? "Weight" : "记体重",systemImage:"scalemass.fill") }
                    Link(destination:URL(string:"gaojiankang://events")!) { Label(en ? "Events" : "快速事项",systemImage:"square.grid.3x3.fill") }
                }.font(.caption).foregroundStyle(.secondary).frame(width:90,alignment:.leading)
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
        let s=try HealthDatabase(access:.readOnlyExisting).read()
        return s.eventTypes.filter { identifiers.contains($0.id.uuidString) }.map { .init(id:$0.id.uuidString,name:$0.title(s.preferences.english)) }
    }
    func suggestedEntities() async throws -> [EventTypeEntity] {
        let s=try HealthDatabase(access:.readOnlyExisting).read()
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
        let db=try HealthDatabase(access:.readWriteExisting)
        let now=Date()
        try db.transaction(request:"widget-event-"+UUID().uuidString,now:now) { s in
            var e=HealthEvent(typeID:id); e.source="widget"; e.occurredAt=now; try EventLog.save(&s,e,now:now)
        }
        try? db.automaticBackup()
        return .result()
    }
}
struct EventWidgetEntry: TimelineEntry {
    let date:Date
    var state:HealthState?
    var typeID:UUID?
    var source:WidgetSourceStatus? = nil
    var request=UUID().uuidString
    var statisticsDate:Date { source?.isStale == true ? (source?.readAt ?? date) : date }
}
struct EventWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context:Context) -> EventWidgetEntry { preview() }
    func snapshot(for configuration:EventConfiguration,in context:Context) async -> EventWidgetEntry {
        if context.isPreview { return preview() }
        let now=Date(),source=HealthWidgetData.load(kind:"events-snapshot")
        return entry(configuration,date:now,source:source)
    }
    func timeline(for configuration:EventConfiguration,in context:Context) async -> Timeline<EventWidgetEntry> {
        let now=Date(),source=HealthWidgetData.load(now:now,kind:"events-timeline-read")
        let calendar=source.snapshot.map { Engine.calendar($0.state) } ?? Calendar.current
        // Event totals do not decay. Only day/month boundaries need scheduled
        // entries; new business records trigger an explicit reload after commit.
        let end=now.addingTimeInterval(48*3600)
        var dates=[now]
        var boundary=calendar.dateInterval(of:.day,for:now)?.end
        while let midnight=boundary, midnight<=end {
            dates.append(midnight)
            guard let next=calendar.date(byAdding:.day,value:1,to:midnight), next>midnight else { break }
            boundary=next
        }
        HealthWidgetData.recordTimeline(kind:"events-timeline-plan",result:source,dates:dates)
        return Timeline(entries:dates.map { entry(configuration,date:$0,source:source) },policy:.after(now.addingTimeInterval(1800)))
    }
    private func entry(_ c:EventConfiguration,date:Date,source:HealthWidgetReadResult) -> EventWidgetEntry {
        let statisticsDate=source.isStale ? (source.snapshot?.readAt ?? date) : date
        let state=source.snapshot.map { widgetDisplayState($0.state,at:statisticsDate,events:true) }
        return .init(date:date,state:state,typeID:c.eventType.flatMap { UUID(uuidString:$0.id) },source:WidgetSourceStatus(source))
    }
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
        VStack(alignment:.leading,spacing:4) {
            if let s=entry.state { content(s) }
            else { Text("健康资料暂不可读取 / Health data unavailable").font(.caption); Link("打开搞健康 / Open Gao Health",destination:URL(string:"gaojiankang://events")!) }
            WidgetDataStatus(source:entry.source,scheduledAt:entry.date)
        }.containerBackground(for:.widget) { Color(nsColor:.windowBackgroundColor) }
        .widgetURL(URL(string:"gaojiankang://events"))
    }
    private func color(_ key:String) -> Color {
        switch key { case "teal": .teal; case "orange": .orange; case "purple": .purple; case "pink": .pink; case "green": .green; default: .blue }
    }
    private func content(_ s:HealthState) -> some View {
        let en=s.preferences.english
        let type=s.eventTypes.first { $0.id == entry.typeID }
        let days=EventLog.month(entry.statisticsDate,state:s,type:entry.typeID)
        let month=Engine.calendar(s).component(.month,from:entry.statisticsDate)
        let monthCount=days.reduce(0){$0+$1.count}
        let selected=s.eventTypes.filter { !$0.archived && (entry.typeID == nil ? $0.inWidget : $0.id == entry.typeID) }
        return VStack(alignment:.leading,spacing:family == .systemLarge ? 8 : 5) {
            HStack {
                Text(type?.title(en) ?? (en ? "Quick events" : "快速事项")).font(.headline).lineLimit(1)
                Spacer(minLength:4)
                Text(family == .systemMedium
                     ? (en ? "\(month) / mo · \(monthCount)" : "\(month) 月 · \(monthCount) 次")
                     : "\(month)"+(en ? " / mo" : " 月"))
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
            }
            if family == .systemMedium {
                HStack(alignment:.top,spacing:16) {
                    grid(days,s,color(type?.color ?? "blue")).frame(maxWidth:.infinity)
                    VStack(alignment:.leading,spacing:4) {
                        ForEach(Array(selected.prefix(3))) { shortcut($0,s).controlSize(.mini) }
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
            .disabled(entry.source?.isStale == true)
    }
    private func grid(_ days:[EventDay],_ s:HealthState,_ tint:Color) -> some View {
        let cal=Engine.calendar(s)
        let offset=days.first.map { (cal.component(.weekday,from:$0.date)+5)%7 } ?? 0
        let headers=s.preferences.english ? ["M","T","W","T","F","S","S"] : ["一","二","三","四","五","六","日"]
        return LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:3),count:7),spacing:2) {
            ForEach(0..<7,id:\.self) { Text(headers[$0]).font(.system(size:8)).foregroundStyle(.secondary) }
            ForEach(0..<offset,id:\.self) { _ in Color.clear.frame(height:family == .systemLarge ? 18 : 9) }
            ForEach(days) { day in
                let level=EventLog.level(day.count)
                RoundedRectangle(cornerRadius:3).fill(level == 0 ? Color.primary.opacity(0.055) : tint.opacity(Double(level)*0.22+0.10))
                    .frame(height:family == .systemLarge ? 18 : 9)
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
