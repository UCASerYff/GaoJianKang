import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject var store: AppStore
    @State private var cup="250"
    @State private var goal=""
    @State private var slots=3
    @State private var rest=23
    @State private var hex=""
    var body: some View {
        SectionTitle(title:store.t("设置","Make it yours"),subtitle:store.t("按自己的节奏来，数据始终留在本机。","Your pace. Your data. Everything stays on this Mac."))
        LazyVGrid(columns:[GridItem(.adaptive(minimum:380,maximum:620),spacing:20,alignment:.top)],alignment:.leading,spacing:20) {
                VStack(alignment:.leading,spacing:18) {
                    Label(store.t("记录偏好","Recording preferences"),systemImage:"slider.horizontal.3").font(.headline)
                    HStack { Text(store.t("快捷杯量","Quick glass")); Spacer(); TextField("250",text:$cup).frame(width:70); Text("mL"); Button(store.t("保存","Save")) { if let n=Double(cup),n>0,n<=10000 { store.preferences{$0.cup=n}; store.notice=store.t("快捷杯量已保存。","Quick glass saved.") } else { store.message=store.t("请输入 0–10000 之间的杯量（不含 0）。","Enter a glass size greater than 0 and up to 10000.") } } }
                    Divider()
                    HStack { Text(store.t("可选饮水目标","Optional water goal")); Spacer(); TextField(store.t("不设置","None"),text:$goal).frame(width:90); Text("mL") }
                    Stepper(store.t("每天 \(slots) 个用餐槽","\(slots) meal slots per day"),value:$slots,in:1...4)
                    HStack { Text(store.t("岛屿休息开始","Island rest starts")); Spacer(); Picker("",selection:$rest) { ForEach(0..<24,id:\.self) { Text(String(format:"%02d:00",$0)).tag($0) } }.frame(width:100) }
                    Text(store.t("目标和日程明日起生效；岛屿休息时段为 8 小时，不是睡眠记录。饮水目标与游戏奖励无关。","Goals and schedule apply tomorrow. Island rest lasts 8 hours and is not a sleep record. Water goals do not affect rewards.")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                    Button(store.t("保存明日计划","Save tomorrow's plan")) { savePlan() }.buttonStyle(.borderedProminent).tint(Theme.teal)
                }.textFieldStyle(.roundedBorder).card()
                VStack(alignment:.leading,spacing:18) {
                    Label(store.t("显示与外观","Appearance"),systemImage:"paintpalette").font(.headline)
                    Toggle(store.t("隐藏热量","Hide calories"),isOn:pref(\.hideCalories))
                    Toggle(store.t("隐藏体重","Hide weight"),isOn:pref(\.hideWeight))
                    HStack { Text(store.t("背景色","Background")); TextField("#2AA187",text:$hex).textFieldStyle(.roundedBorder).frame(width:95); Button(store.t("应用","Apply")) { if hex.isEmpty || (hex.count==7 && hex.hasPrefix("#") && UInt32(hex.dropFirst(),radix:16) != nil) { store.preferences{$0.backgroundHex=hex} } else { store.message=store.t("请输入 #RRGGBB 颜色。","Enter a #RRGGBB color.") } }; Button(store.t("默认","Default")) { hex=""; store.preferences{$0.backgroundHex=""} } }
                    Toggle(store.t("开启荒岛经营","Enable island game"),isOn:pref(\.gameEnabled))
                    Text(store.t("关闭后为纯记录模式，岛屿暂停，记录不发放游戏奖励。","Turning this off pauses the island and disables game rewards. All recording features remain available.")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                }.card()
                VStack(alignment:.leading,spacing:16) {
                    Label(store.t("数据与备份","Data & backups"),systemImage:"externaldrive").font(.headline)
                    Text(store.t("无需账号，没有云端同步。本页的岛屿备份包含饮水、饮食、运动、体重、快速事项、模板与岛屿进度。共享睡眠请使用设置「数据」页的完整资料 ZIP 备份。","No account or cloud sync. Island backups on this page include health entries, templates and island progress. Use the full ZIP backup in Settings → Data to include shared sleep.")).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                    HStack { Button(store.t("导出 CSV","Export CSV")) { store.exportCSV() }; Button(store.t("导入 CSV","Import CSV")) { store.importCSV() }; Button(store.t("岛屿与健康备份","Island & health backup")) { store.backup() } }
                    HStack { Button(store.t("恢复备份","Restore backup")) { store.restore() }; Button(store.t("自动备份目录","Automatic backups")) { store.openBackups() } }
                    Text(store.t("每日首次成功写入后备份，保留最近 7 份。CSV 供阅读，共享睡眠不在 .healthbackup 中，完整迁移请使用资料 ZIP 备份。导入仅识别本应用导出的 CSV，按 id 去重，不补发岛屿奖励。","A daily backup after the first successful write; latest 7 retained. Shared sleep is separate from .healthbackup; use a full ZIP for migration. Import accepts only CSVs exported by this app; duplicates by id are skipped and imports grant no island rewards.")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                    Divider()
                    Button(store.t("重置岛屿（保留健康记录）","Reset island (keep records)"),role:.destructive) { store.reset(all:false) }
                    Button(store.t("删除全部数据与自动备份","Delete all data and local backups"),role:.destructive) { store.reset(all:true) }
                }.card()
                VStack(alignment:.leading,spacing:14) {
                    Label(store.t("桌面小组件","Desktop widgets"),systemImage:"rectangle.3.group").font(.headline)
                    Text(store.t("在桌面空白处右键 → 编辑小组件 → 搜索“搞健康”，添加小号、中号或大号小组件。","Right-click your desktop → Edit Widgets → search for Gao Health / 搞健康. Choose small, medium or large.")).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                    Text(store.t("可以直接记水；记餐与运动会打开快捷面板。刷新由系统管理，不必保持 App 窗口打开。","Record water directly. Meal and activity links open quick entry. Refresh timing is managed by macOS.")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true)
                }.card()
                VStack(alignment:.leading,spacing:12) {
                    HStack { Label(store.t("常用模板与食物","Favorite meals & activities"),systemImage:"star").font(.headline); Spacer(); Button { store.new(.meal) } label:{Image(systemName:"plus")} }
                    if store.state.templates.isEmpty { Text(store.t("在录入时勾选“同时保存为常用模板”。饮食模板会记住饮食方式和饱食程度。","Save a template from the entry form. Meal templates remember source and fullness.")).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal:false,vertical:true) }
                    ForEach(store.state.templates) { t in
                        HStack { Image(systemName:t.record.kind.symbol).foregroundStyle(Theme.color(t.record.kind)); Text(t.name).lineLimit(1); Spacer(); Button(store.t("记一笔","Record")) { store.useTemplate(t) }; Button(role:.destructive) { _ = store.update { $0.templates.removeAll{$0.id==t.id} } } label:{Image(systemName:"trash")} }.font(.caption)
                    }
                }.card()
                Text("搞健康 V\(Bundle.main.object(forInfoDictionaryKey:"CFBundleShortVersionString") as? String ?? "1.7")\n" + store.t("原生 macOS · 本地记录 · 永续小岛","Native macOS · Local journal · An island that grows")).font(.caption).foregroundStyle(.tertiary).padding(.horizontal,5)
        }
        .onAppear {
            cup=number(store.state.preferences.cup); hex=store.state.preferences.backgroundHex
            let next=Engine.calendar(store.state).date(byAdding:.day,value:1,to:Date())!
            let cfg=store.state.preferences.config(Engine.day(next,store.state)); goal=cfg.waterGoal.map(number) ?? ""; slots=cfg.slots; rest=cfg.restHour
        }
    }
    private func pref<T>(_ key:WritableKeyPath<Preferences,T>)->Binding<T> { Binding(get:{store.state.preferences[keyPath:key]},set:{ v in store.preferences{$0[keyPath:key]=v} }) }
    private func savePlan() {
        let text=goal.trimmingCharacters(in:.whitespacesAndNewlines)
        let value=text.isEmpty ? nil : Double(text)
        guard text.isEmpty || (value != nil && value!>0 && value!<=10000) else { store.message=store.t("目标请填写有效 mL 数字，或留空。","Enter a valid goal in mL or leave blank."); return }
        let next=Engine.calendar(store.state).date(byAdding:.day,value:1,to:Date())!
        let key=Engine.day(next,store.state)
        store.preferences { prefs in prefs.configs.removeAll{$0.effectiveDay==key}; prefs.configs.append(.init(effectiveDay:key,waterGoal:value,slots:slots,restHour:rest)) }
        store.notice=store.t("新计划将于明日生效。","Your new plan starts tomorrow.")
    }
}
