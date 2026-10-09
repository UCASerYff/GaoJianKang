import SwiftUI

struct RecordEditor: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) var dismiss
    @State var record: HealthRecord
    var startInBackfill = false
    @State private var isBackfill = false
    @State private var amount=""
    @State private var calories=""
    @State private var mealSource: MealSource? = .canteen
    @State private var fullness = 75.0
    @State private var template=false
    @State private var validation=""
    var existing: Bool { store.state.records.contains{$0.id==record.id} }
    var body: some View {
        VStack(spacing:0) {
            HStack { SymbolTile(symbol:record.kind.symbol,color:Theme.color(record.kind)); VStack(alignment:.leading,spacing:4) { Text((existing ? store.t("编辑","Edit ") : isBackfill ? store.t("补记","Past entry: ") : store.t("记录","Record "))+record.kind.title(store.en)).font(.title2.weight(.semibold)); Text(store.t("真实记录就好，留空也没关系。","Just the facts. Optional fields can stay empty.")).font(.caption).foregroundStyle(.secondary) }; Spacer(); Button { dismiss() } label:{Image(systemName:"xmark")}.buttonStyle(.plain) }.padding(24)
            Divider()
            ScrollView {
                VStack(alignment:.leading,spacing:18) {
                    HealthRecordTimeFields(occurredAt:$record.occurredAt,isBackfill:$isBackfill,isEditing:existing,calendar:Engine.calendar(store.state),en:store.en)
                    if record.kind == .meal {
                        let slots=store.state.preferences.config(Engine.day(record.occurredAt,store.state)).slots
                        Picker(store.t("餐别","Meal slot"),selection:$record.slot) {
                            ForEach(0..<slots,id:\.self) { i in Text(Engine.mealTitle(slot:i,occurredAt:record.occurredAt,store.state)).tag(i) }
                            Text(store.t("加餐（仅记录）","Snack (journal only)")).tag(4)
                        }.pickerStyle(.segmented)
                    }
                    if record.kind == .meal || record.kind == .exercise {
                        field(store.t("名称","Name"),$record.title,store.t("例如：家常午餐 / 步行","e.g. Lunch / Walking"))
                    }
                    if record.kind == .meal {
                        Picker(store.t("饮食方式","Meal source"), selection:$mealSource) {
                            Text(store.t("旧记录未分类","Earlier entry: unspecified")).tag(nil as MealSource?)
                            ForEach(MealSource.allCases) { source in Text(source.title(store.en)).tag(Optional(source)) }
                        }
                        HStack {
                            Text(store.t("饱食程度","Fullness"))
                            Slider(value:$fullness,in:0...100,step:5)
                            Text("\(Int(fullness))%").monospacedDigit().frame(width:48,alignment:.trailing)
                        }
                        Text(store.t("饱食程度会影响今天给岛屿补充的食物储备；每餐按上限计算。","Fullness determines today's island food reward, subject to the meal limit."))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    if record.kind != .meal {
                        HStack {
                            field(store.t("数量","Amount"),$amount,record.kind.unit)
                            Text(record.kind.unit).foregroundStyle(.secondary).padding(.top,20)
                        }
                    }
                    if record.kind == .exercise {
                        field(store.t("消耗（手填，可选）","Energy burned (manual, optional)"),$calories,"kcal")
                    }
                    field(store.t("备注（可选）","Note (optional)"),$record.note,store.t("给这次记录留一句话","Anything you want to remember"))
                    if record.kind == .meal || record.kind == .exercise { Toggle(store.t("同时保存为常用模板","Also save as a favorite template"),isOn:$template) }
                    if !validation.isEmpty { Text(validation).foregroundStyle(.red).font(.callout) }
                    Text(store.t("补记只更正历史；每日游戏奖励有上限。","Past entries update your history. Game rewards have daily limits.")).font(.caption).foregroundStyle(.secondary)
                }.padding(24)
            }
            Divider()
            HStack { Button(store.t("取消","Cancel")) { dismiss() }.keyboardShortcut(.cancelAction); Spacer(); Button(existing ? store.t("保存修改","Save changes") : store.t("保存记录","Save record")) { submit() }.buttonStyle(.borderedProminent).tint(Theme.teal).keyboardShortcut(.defaultAction) }.padding(20)
        }.frame(minWidth:560,idealWidth:600,maxWidth:720,minHeight:480,idealHeight:record.kind == .meal ? 530 : 520)
        .onAppear {
            isBackfill=existing || startInBackfill || !Engine.calendar(store.state).isDate(record.occurredAt,inSameDayAs:Date())
            amount=number(record.amount)
            calories=record.calories.map(number) ?? ""
            mealSource=record.mealSource
            fullness=Double(record.fullnessPercent ?? 100)
        }
    }
    private func field(_ title:String,_ binding:Binding<String>,_ placeholder:String)->some View {
        VStack(alignment:.leading,spacing:6) { Text(title).font(.caption).foregroundStyle(.secondary); TextField(placeholder,text:binding).textFieldStyle(.roundedBorder) }
    }
    private func submit() {
        func parse(_ input:String) throws -> Double? {
            let v=input.trimmingCharacters(in:.whitespacesAndNewlines)
            if v.isEmpty { return nil }
            guard let n=Double(v.replacingOccurrences(of:",",with:".")),n.isFinite,n>=0 else { throw HealthError(store.t("请输入有效的非负数字，或留空。","Enter a non-negative number or leave blank.")) }; return n
        }
        do {
            if !existing && !isBackfill { record.occurredAt=Date() }
            if record.kind == .meal {
                record.mealSource=mealSource
                record.fullnessPercent=Int(fullness)
            } else {
                guard let n=try parse(amount),n>0 else { throw HealthError(store.t("数量必须大于 0。","Amount must be positive.")) }
                record.amount=n
                if record.kind == .exercise { record.calories=try parse(calories) }
            }
            if record.kind == .meal && record.title.isEmpty { record.title=Engine.mealTitle(slot:record.slot,occurredAt:record.occurredAt,store.state) }
            if record.kind == .exercise && record.title.isEmpty { record.title=store.t("运动","Activity") }
            try Engine.validateRecord(record,now:Date()); store.save(record,template:template)
        } catch { validation=error.localizedDescription }
    }
}

/// Reused by health records and quick events. Merely opening an editor never
/// rewrites its timestamp; only an explicit shortcut or a new immediate save does.
struct HealthRecordTimeFields: View {
    @Binding var occurredAt: Date
    @Binding var isBackfill: Bool
    let isEditing: Bool
    let calendar: Calendar
    let en: Bool

    var body: some View {
        VStack(alignment:.leading,spacing:12) {
            if !isEditing {
                Picker(en ? "Entry time" : "记录方式",selection:$isBackfill) {
                    Text(en ? "Record now" : "即时记录").tag(false)
                    Text(en ? "Past entry" : "补记").tag(true)
                }.pickerStyle(.segmented)
            }
            if isBackfill || isEditing {
                HStack {
                    Label(en ? "Choose date and time" : "选择日期与时间",systemImage:"calendar.badge.clock").font(.subheadline.weight(.medium))
                    Spacer()
                    Button(en ? "Yesterday" : "昨天") { selectDay(-1) }
                    Button(en ? "Today" : "今天") { selectDay(0) }
                }
                DatePicker(en ? "Occurred at" : "实际发生时间",selection:$occurredAt,in:...Date(),displayedComponents:[.date,.hourAndMinute])
                    .environment(\.calendar,calendar).environment(\.timeZone,calendar.timeZone)
                Text(en ? "Saved under the selected date, including entries from earlier today." : "按实际发生日期归档；今天早些时候的记录也可以补记。")
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                HStack {
                    Label(en ? "Use the time when saved" : "使用保存时的当前时间",systemImage:"clock").font(.subheadline)
                    Spacer()
                    Button(en ? "Yesterday" : "补记昨天") { selectDay(-1) }
                }
                Button(en ? "Choose an earlier date and time…" : "选择日期补记…") { isBackfill=true }
                    .buttonStyle(.link)
            }
        }
        .onChange(of:isBackfill) { _,past in
            if !past && !isEditing { occurredAt=Date() }
        }
    }

    private func selectDay(_ offset:Int) {
        isBackfill=true
        let now=Date()
        let target=calendar.date(byAdding:.day,value:offset,to:now) ?? now
        let time=calendar.dateComponents([.hour,.minute,.second],from:occurredAt)
        occurredAt=min(calendar.date(bySettingHour:time.hour ?? 12,minute:time.minute ?? 0,second:time.second ?? 0,of:target) ?? target,now)
    }
}
