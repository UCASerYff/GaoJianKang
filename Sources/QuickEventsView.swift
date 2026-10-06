import SwiftUI

extension HealthEventType {
    var tint: Color { Self.tint(color) }
    static func tint(_ key: String) -> Color {
        switch key { case "teal": .teal; case "orange": .orange; case "purple": .purple; case "pink": .pink; case "green": .green; default: .blue }
    }
}
struct QuickEventsView: View {
    @EnvironmentObject var store: AppStore
    @State private var month = Date()
    @State private var page=0
    @State private var filter: UUID?
    @State private var selectedDay: Date?
    @State private var typeEditor: HealthEventType?
    @State private var eventEditor: HealthEvent?
    @State private var showArchived = false
    private var types: [HealthEventType] { store.state.eventTypes.filter { !$0.archived } }
    private var days: [EventDay] { EventLog.month(month,state:store.state,type:filter) }
    private var monthTitle: String {
        let f=DateFormatter(); f.locale=Locale(identifier:store.en ? "en_US" : "zh_CN"); f.timeZone=Engine.calendar(store.state).timeZone; f.dateFormat=store.en ? "MMMM yyyy" : "yyyy 年 M 月"; return f.string(from:month)
    }
    private var tint: Color { store.state.eventTypes.first { $0.id == filter }?.tint ?? Theme.blue }
    private var entries: [HealthEvent] {
        let cal=Engine.calendar(store.state)
        return store.state.events.filter { e in
            (filter == nil || e.typeID == filter) && cal.isDate(e.occurredAt,equalTo:month,toGranularity:.month) && (selectedDay == nil || cal.isDate(e.occurredAt,inSameDayAs:selectedDay!))
        }.sorted { $0.occurredAt > $1.occurredAt }
    }
    var body: some View {
        HStack {
            SectionTitle(title:store.t("快速事项","Quick events"),subtitle:store.t("点一下，留住日常中的小事。","One tap for the little things in your day."))
            Spacer()
            Button { typeEditor=HealthEventType(name:"") } label: { Label(store.t("自定义事项","New event type"),systemImage:"plus") }.buttonStyle(.borderedProminent).tint(Theme.blue)
        }
        LazyVGrid(columns:[GridItem(.adaptive(minimum:165),spacing:12)],spacing:12) {
            ForEach(types) { type in quickCard(type) }
        }
        if types.isEmpty { Text(store.t("添加一个事项，或者在下方恢复已停用事项。","Add a type or restore an archived type below.")).foregroundStyle(.secondary) }
        VStack(alignment:.leading,spacing:18) {
            HStack {
                Text(store.t("事项活动","Event activity")).font(.headline)
                Spacer()
                Picker(store.t("事项","Type"),selection:$filter) {
                    Text(store.t("全部事项","All events")).tag(nil as UUID?)
                    ForEach(store.state.eventTypes) { type in Text(type.title(store.en)+(type.archived ? store.t("（已停用）"," (archived)") : "")).tag(Optional(type.id)) }
                }.labelsHidden().frame(maxWidth:210)
            }
            HStack {
                Button { shift(-1) } label: { Image(systemName:"chevron.left") }.help(store.t("上个月","Previous month"))
                Text(monthTitle).font(.title3.weight(.semibold)).frame(minWidth:150)
                Button { shift(1) } label: { Image(systemName:"chevron.right") }.help(store.t("下个月","Next month")).disabled(Engine.calendar(store.state).isDate(month,equalTo:Date(),toGranularity:.month))
                Button(store.t("本月","This month")) { month=Date(); selectedDay=nil }.buttonStyle(.link)
                Spacer()
                Text(store.t("本月 \(days.reduce(0){$0+$1.count}) 次 · \(days.filter{$0.count>0}.count) 天有记录","\(days.reduce(0){$0+$1.count}) events · \(days.filter{$0.count>0}.count) active days")).font(.caption).foregroundStyle(.secondary)
            }
            calendar
            HStack(spacing:6) {
                Text(store.t("每日次数","Daily count")).font(.caption).foregroundStyle(.secondary)
                ForEach(0..<5) { level in
                    RoundedRectangle(cornerRadius:3).fill(level == 0 ? Color.primary.opacity(0.045) : tint.opacity(Double(level)*0.22+0.10)).frame(width:15,height:15)
                    Text(level == 4 ? "4+" : String(level)).font(.caption2).foregroundStyle(.secondary)
                }
                Spacer()
                Text(store.t("点击日期查看记录","Select a day to see entries")).font(.caption).foregroundStyle(.secondary)
            }
        }.card()
        HStack {
            Text(selectedDay.map { $0.formatted(date:.abbreviated,time:.omitted) } ?? store.t("本月明细","This month's entries")).font(.headline)
            if selectedDay != nil { Button(store.t("显示整月","Show month")) { selectedDay=nil }.buttonStyle(.link) }
            Spacer()
            Menu(store.t("补记事项","Add past entry")) {
                ForEach(types) { type in var entry=HealthEvent(typeID:type.id); Button(type.title(store.en)) { entry.occurredAt=min(selectedDay ?? Date(),Date()); eventEditor=entry } }
            }.disabled(types.isEmpty)
        }
        if entries.isEmpty { EmptyCard(symbol:"square.grid.3x3",title:store.t("还没有记录","No entries yet"),detail:store.t("点击上方事项记一次，颜色会随当天次数加深。","Tap an event above. More entries make the day darker.")) }
        else {
            LazyVStack(spacing:0) {
                GQHistoryPager(page:$page,count:entries.count)
                ForEach(Array(entries.dropFirst(page*100).prefix(100))) { event in
                    HStack(spacing:12) {
                        if let type=store.state.eventTypes.first(where:{$0.id == event.typeID}) {
                            Image(systemName:type.symbol).foregroundStyle(type.tint).frame(width:24)
                            VStack(alignment:.leading,spacing:4) {
                                Text(type.title(store.en)).font(.system(size:13,weight:.medium))
                                Text(event.occurredAt.formatted(date:.abbreviated,time:.shortened)+(event.note.isEmpty ? "" : " · "+event.note)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        Text("×\(event.count)").monospacedDigit()
                        Button { eventEditor=event } label: { Image(systemName:"pencil") }.help(store.t("编辑","Edit"))
                        Button { store.removeEvent(event) } label: { Image(systemName:"trash") }.help(store.t("删除，可撤销","Delete; undo available"))
                    }.padding(.vertical,12)
                    if event.id != entries.last?.id { Divider() }
                }
            }.card()
        }
        DisclosureGroup(store.t("已停用事项","Archived types"),isExpanded:$showArchived) {
            ForEach(store.state.eventTypes.filter(\.archived)) { type in
                HStack { Label(type.title(store.en),systemImage:type.symbol); Spacer(); Button(store.t("恢复使用","Restore")) { var t=type; t.archived=false; _=store.update { try EventLog.saveType(&$0,t) } } }.padding(.vertical,8)
            }
            Text(store.t("停用仅隐藏快捷按钮，历史记录始终保留。","Archiving hides the shortcut and keeps all history.")).font(.caption).foregroundStyle(.secondary)
        }.card()
        .sheet(item:$typeEditor) { type in EventTypeEditor(type:type).environmentObject(store) }
        .sheet(item:$eventEditor) { event in EventEntryEditor(event:event).environmentObject(store) }
    }
    private func shift(_ amount: Int) { month=Engine.calendar(store.state).date(byAdding:.month,value:amount,to:month) ?? month; selectedDay=nil }
    private func quickCard(_ type: HealthEventType) -> some View {
        let count=store.state.events.filter { $0.typeID == type.id && Engine.day($0.occurredAt,store.state) == Engine.day(Date(),store.state) }.reduce(0){$0+$1.count}
        return VStack(alignment:.leading,spacing:12) {
            HStack { Image(systemName:type.symbol).font(.title3).foregroundStyle(type.tint); Spacer(); Menu {
                Button(store.t("编辑事项","Edit type")) { typeEditor=type }
                Button(store.t("补记","Add past entry")) { eventEditor=HealthEvent(typeID:type.id) }
                Button(store.t("停用（保留记录）","Archive (keep history)")) { var t=type; t.archived=true; _=store.update { try EventLog.saveType(&$0,t) } }
            } label: { Image(systemName:"ellipsis") }.menuStyle(.borderlessButton).fixedSize() }
            Text(type.title(store.en)).font(.headline).lineLimit(2)
            HStack { Text(store.t("今日 \(count) 次","\(count) today")).font(.caption).foregroundStyle(.secondary); Spacer(); Button { store.logEvent(type) } label: { Text("+1").fontWeight(.semibold) }.buttonStyle(.borderedProminent).tint(type.tint).accessibilityLabel(store.t("记录","Log ")+type.title(store.en)) }
        }.card()
    }
    private var calendar: some View {
        let cal=Engine.calendar(store.state)
        let offset=days.first.map { (cal.component(.weekday,from:$0.date)+5)%7 } ?? 0
        let weekdays=store.en ? ["Mon","Tue","Wed","Thu","Fri","Sat","Sun"] : ["一","二","三","四","五","六","日"]
        return LazyVGrid(columns:Array(repeating:GridItem(.flexible(),spacing:8),count:7),spacing:8) {
            ForEach(weekdays,id:\.self) { Text($0).font(.caption).foregroundStyle(.secondary).frame(maxWidth:.infinity) }
            ForEach(0..<offset,id:\.self) { _ in Color.clear.frame(height:48) }
            ForEach(days) { day in
                let level=EventLog.level(day.count)
                Button { selectedDay=day.date } label: {
                    VStack(alignment:.leading,spacing:3) {
                        Text("\(cal.component(.day,from:day.date))").font(.caption)
                        HStack { Spacer(); Text(day.count == 0 ? " " : "\(day.count)").font(.system(size:15,weight:.semibold,design:.rounded)) }
                    }.padding(8).frame(maxWidth:.infinity).frame(height:48)
                        .foregroundStyle(level>=3 ? Color.white : Color.primary)
                        .background(level == 0 ? Color.primary.opacity(0.045) : tint.opacity(Double(level)*0.22+0.10),in:RoundedRectangle(cornerRadius:7))
                        .overlay(RoundedRectangle(cornerRadius:7).stroke(selectedDay.map { cal.isDate($0,inSameDayAs:day.date) } == true ? tint : Color.clear,lineWidth:2))
                }.buttonStyle(.plain).help("\(Engine.day(day.date,store.state)) · \(day.count)").accessibilityLabel("\(Engine.day(day.date,store.state)), \(day.count) "+store.t("次","events"))
            }
        }
    }
}
struct EventTypeEditor: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State var type: HealthEventType
    @State private var error: String?
    var body: some View {
        VStack(alignment:.leading,spacing:20) {
            Text(store.t("自定义健康事项","Customize event")).font(.title2.bold())
            TextField(store.t("事项名称（最多 24 字）","Name (up to 24 characters)"),text:$type.name).textFieldStyle(.roundedBorder)
            TextField(store.t("英文名称（可选）","English name (optional)"),text:$type.englishName).textFieldStyle(.roundedBorder)
            HStack { ForEach(HealthEventType.symbols,id:\.self) { symbol in Button { type.symbol=symbol } label: { Image(systemName:symbol).frame(width:22,height:25).foregroundStyle(type.symbol == symbol ? type.tint : .secondary) }.buttonStyle(.bordered) } }
            HStack { Text(store.t("颜色","Color")); ForEach(HealthEventType.colors,id:\.self) { key in Button { type.color=key } label: { Circle().fill(HealthEventType.tint(key)).frame(width:25,height:25).overlay { if type.color == key { Image(systemName:"checkmark").foregroundStyle(.white) } } }.buttonStyle(.plain).accessibilityLabel(key) } }
            Toggle(store.t("显示在小组件快捷按钮中","Show in widget shortcuts"),isOn:$type.inWidget)
            if let error { Text(error).foregroundStyle(.red).font(.caption) }
            HStack { Spacer(); Button(store.t("取消","Cancel")) { dismiss() }.keyboardShortcut(.cancelAction); Button(store.t("保存","Save")) {
                var probe=store.state
                do { try EventLog.saveType(&probe,type); if store.update({ try EventLog.saveType(&$0,type) }) { dismiss() } } catch { self.error=error.localizedDescription }
            }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent) }
        }.padding(28).frame(width:560)
    }
}
struct EventEntryEditor: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State var event: HealthEvent
    @State private var error: String?
    var body: some View {
        VStack(alignment:.leading,spacing:20) {
            Text(store.state.eventTypes.first { $0.id == event.typeID }?.title(store.en) ?? "").font(.title2.bold())
            DatePicker(store.t("时间","Date"),selection:$event.occurredAt,in:...Date(),displayedComponents:[.date,.hourAndMinute])
            Stepper(store.t("次数：\(event.count)","Count: \(event.count)"),value:$event.count,in:1...999)
            TextField(store.t("备注（可选）","Note (optional)"),text:$event.note).textFieldStyle(.roundedBorder)
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack { Spacer(); Button(store.t("取消","Cancel")) { dismiss() }.keyboardShortcut(.cancelAction); Button(store.t("保存","Save")) {
                var probe=store.state
                do { try EventLog.save(&probe,event); if store.saveEvent(event) { dismiss() } } catch { self.error=error.localizedDescription }
            }.keyboardShortcut(.defaultAction).buttonStyle(.borderedProminent) }
        }.padding(28).frame(width:440)
    }
}
