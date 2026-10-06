import SwiftUI

struct ReservesView: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        HStack(spacing:16) {
            meter(store.t("水分","Water"),store.state.island.water,"drop.fill",Theme.blue)
            meter(store.t("饱食","Food"),store.state.island.food,"fork.knife",Theme.orange)
            meter(store.t("活力","Energy"),store.state.island.energy,"bolt.fill",Theme.green)
        }
    }
    private func meter(_ title:String,_ value:Double,_ symbol:String,_ color:Color)->some View {
        VStack(alignment:.leading,spacing:14) {
            HStack { SymbolTile(symbol:symbol,color:color); VStack(alignment:.leading,spacing:2) { Text(title).font(.callout.weight(.medium)); Text(store.t("岛民状态","Island reserve")).font(.caption2).foregroundStyle(.secondary) }; Spacer(); Text(number(value)).font(.system(size:24,weight:.semibold,design:.rounded)).monospacedDigit(); Text("/100").font(.caption).foregroundStyle(.tertiary) }
            GeometryReader { geo in ZStack(alignment:.leading) { Capsule().fill(color.opacity(0.10)); Capsule().fill(color).frame(width:max(0,geo.size.width*value/100)) } }.frame(height:5)
        }.card(17)
    }
}
struct TodayView: View {
    @EnvironmentObject var store: AppStore
    var today: [HealthRecord] { store.state.records.filter { Engine.day($0.occurredAt,store.state)==Engine.day(Date(),store.state) }.sorted { $0.occurredAt>$1.occurredAt } }
    var body: some View {
        HStack(alignment:.bottom) {
            SectionTitle(title:store.t("把照顾自己，变成小小日常。","Small moments. A healthier rhythm."),subtitle:Date().formatted(.dateTime.year().month(.wide).day().weekday(.wide)))
            Spacer()
            let streak=Engine.streak(store.state,now:Date())
            if streak>1 { Label(store.t("已连续记录 \(streak) 天","\(streak)-day streak"),systemImage:"flame.fill").font(.caption.weight(.medium)).foregroundStyle(Theme.orange).padding(.horizontal,12).padding(.vertical,7).background(Theme.orange.opacity(0.10),in:Capsule()).padding(.bottom,6) }
        }
        if !store.state.preferences.onboarding {
            HStack(spacing:16) {
                SymbolTile(symbol:"sparkles",color:Theme.teal)
                VStack(alignment:.leading,spacing:4) { Text(store.t("欢迎来到你的岛","Welcome to your island")).font(.headline); Text(store.t("不必先设目标。记一杯水，或到荒岛点起第一堆篝火。","No targets needed. Record a glass of water or build your first campfire.")).font(.callout).foregroundStyle(.secondary) }
                Spacer(); Button(store.t("开始记录","Let's begin")) { store.preferences { $0.onboarding=true }; store.addWater() }.buttonStyle(.borderedProminent).tint(Theme.teal)
                Button { store.preferences { $0.onboarding=true } } label:{ Image(systemName:"xmark") }.buttonStyle(.plain)
            }.card()
        }
        HStack { Text(store.t("今日记录","Today’s records")).font(.title3.weight(.semibold)); Spacer(); Text(store.t("只记录事实，不给自己打分","A journal, not a scorecard")).font(.caption).foregroundStyle(.secondary) }
        HStack(spacing:14) {
            let waterTotal=today.filter{$0.kind == .water}.reduce(0){$0+$1.amount}
            let goal=store.state.preferences.config(Engine.day(Date(),store.state)).waterGoal
            quick(.water,value:"\(number(waterTotal)) mL",detail:goal.map { store.t("目标 \(number($0)) mL · 一键记录","Goal \(number($0)) mL · quick add") } ?? store.t("+\(number(store.state.preferences.cup)) mL · 一键记录","+\(number(store.state.preferences.cup)) mL · quick add"),progress:goal.map { min(1,waterTotal/$0) },progressColor:Theme.blue) { store.addWater() }
            let meals=today.filter{$0.kind == .meal}
            quick(.meal,value:"\(meals.count) " + store.t("笔","entries"),detail:store.t("选择饮食方式和饱食程度","Choose a meal source and fullness")) { store.new(.meal) }
            quick(.exercise,value:"\(number(today.filter{$0.kind == .exercise}.reduce(0){$0+$1.amount})) min",detail:store.t("步行也是日常运动","A walk counts, too")) { store.new(.exercise) }
            if !store.state.preferences.hideWeight { quick(.weight,value:today.first(where:{$0.kind == .weight}).map{ "\(number($0.amount)) kg" } ?? "— kg",detail:store.t("按自己的节奏记录","At your own pace")) { store.new(.weight) } }
        }
        if store.state.preferences.gameEnabled {
            HStack(spacing:18) {
                IslandPreview(island:store.state.island,en:store.en).frame(maxWidth:.infinity).frame(height:165)
                VStack(alignment:.leading,spacing:10) {
                    Text(store.t("记录一点，生长一点","One record at a time")).font(.title3.weight(.semibold))
                    Text(store.state.island.paused ? store.t("岛屿正在休整，记录照常保存。","Your island is resting. Health records still work.") : store.t("生活的每一小步，\n都能让这里多一点生机。","Every small step brings\na little more life here.")).font(.callout).foregroundStyle(.secondary).lineSpacing(5)
                    Spacer(minLength:0)
                    HStack { Image(systemName:"house.and.flag"); Text(store.t("已建成 \(store.state.island.buildings.count) / \(Catalog.recipes.filter { !$0.tool }.count) 座建筑","\(store.state.island.buildings.count) / \(Catalog.recipes.filter { !$0.tool }.count) buildings")) }.font(.caption).foregroundStyle(.secondary)
                    Button { store.selectedTab=3 } label:{ HStack { Text(store.t("去岛上看看","Visit your island")); Image(systemName:"arrow.right") } }.buttonStyle(.borderedProminent).tint(Theme.teal).controlSize(.large)
                }.padding(14).frame(width:245,height:165).background(Color(nsColor:.controlBackgroundColor),in:RoundedRectangle(cornerRadius:14))
            }
            ReservesView()
        }
        if !store.state.templates.isEmpty {
            VStack(alignment:.leading,spacing:12) {
                Text(store.t("常用模板 · 点击即记","Favorites · one-click record")).font(.headline)
                LazyVGrid(columns:[GridItem(.adaptive(minimum:175))],alignment:.leading,spacing:10) {
                    ForEach(store.state.templates.sorted{$0.uses>$1.uses}.prefix(8)) { t in Button { store.useTemplate(t) } label:{ Label(t.name,systemImage:t.record.kind.symbol).frame(maxWidth:.infinity,alignment:.leading).padding(10) }.buttonStyle(.bordered).help(store.t("立即保存今天的记录，可撤销","Save now for today; undo available")) }
                }
            }.card()
        }
        VStack(spacing:0) {
            if today.isEmpty { EmptyCard(symbol:"leaf",title:store.t("今天，从一笔小记录开始","A fresh page for today"),detail:store.t("喝水、吃饭、散步，都值得被看见。","Water, meals, movement. Make a little space for yourself.")) }
            else { ForEach(today) { record in RecordRow(record:record); if record.id != today.last?.id { Divider().padding(.leading,58) } } }
        }.card(12)
        if store.state.preferences.gameEnabled { Text(store.t("三维是岛民的游戏状态，不代表你的身体状态。","Island reserves are game values, not a measure of your health.")).font(.caption).foregroundStyle(.tertiary) }
    }
    private func quick(_ kind:RecordKind,value:String,detail:String,progress:Double?=nil,progressColor:Color=Theme.teal,action:@escaping()->Void)->some View {
        Button(action:action) {
            VStack(alignment:.leading,spacing:12) {
                HStack { Image(systemName:kind.symbol).foregroundStyle(Theme.color(kind)); Text(kind.title(store.en)).font(.callout); Spacer(); Image(systemName:"plus.circle").foregroundStyle(.tertiary) }
                Text(value).font(.system(size:23,weight:.semibold,design:.rounded)).monospacedDigit()
                if let progress { GeometryReader { geo in ZStack(alignment:.leading) { Capsule().fill(progressColor.opacity(0.12)); Capsule().fill(progressColor).frame(width:max(0,geo.size.width*progress)) } }.frame(height:4) }
                Text(detail).font(.system(size:10)).foregroundStyle(.secondary).lineLimit(1)
            }.card(17)
        }.buttonStyle(.plain)
    }
}
struct RecordRow: View {
    @EnvironmentObject var store: AppStore
    let record: HealthRecord
    var body: some View {
        HStack(spacing:12) {
            SymbolTile(symbol:record.kind.symbol,color:Theme.color(record.kind))
            VStack(alignment:.leading,spacing:4) {
                Text(record.title.isEmpty ? record.kind.title(store.en) : record.title).font(.callout.weight(.medium))
                Text(record.occurredAt.formatted(.dateTime.month().day().hour().minute()) + (record.note.isEmpty ? "" : " · \(record.note)")).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(value).font(.callout.weight(.semibold)).monospacedDigit()
            Button { store.editor=record } label:{ Image(systemName:"pencil") }.buttonStyle(.borderless).help(store.t("编辑记录","Edit record"))
            Menu { Button(store.t("删除记录","Delete record"),role:.destructive) { store.remove(record) } } label:{ Image(systemName:"ellipsis") }.menuStyle(.borderlessButton).fixedSize()
        }.padding(10)
    }
    private var value:String {
        if record.kind == .meal {
            guard let fullness = record.fullnessPercent else { return store.t("旧记录 · 按原规则","Earlier entry · original rule") }
            let source = record.mealSource?.title(store.en) ?? store.t("未分类","Unspecified")
            return "\(source) · \(fullness)%"
        }
        return "\(number(record.amount)) \(record.kind.unit)"
    }
}
struct RecordsView: View {
    @EnvironmentObject var store: AppStore
    var kind: RecordKind
    @State private var query=""
    @State private var range=30
    @State private var page=0
    private var results:[HealthRecord] {
        let cutoff=Calendar.current.date(byAdding:.day,value:-range,to:Date()) ?? .distantPast
        return store.state.records.filter { $0.kind == kind && (range==0 || $0.occurredAt>=cutoff) && (query.isEmpty || ($0.title+" "+$0.note).localizedCaseInsensitiveContains(query)) }.sorted{$0.occurredAt>$1.occurredAt}
    }
    private var heading: String { kind.title(store.en)+store.t("记录"," journal") }
    var body: some View {
        SectionTitle(title:heading,subtitle:store.t("每一笔都可以补记、更正或删除。","Add, edit or remove any entry. Your journal belongs to you."))
        HStack {
            Spacer()
            TextField(store.t("搜索名称或备注","Search names or notes"),text:$query).textFieldStyle(.roundedBorder).frame(width:200)
            Picker("",selection:$range) { Text(store.t("近 7 天","7 days")).tag(7); Text(store.t("近 30 天","30 days")).tag(30); Text(store.t("全部时间","All time")).tag(0) }.frame(width:130)
        }
        VStack(spacing:0) {
            if results.isEmpty { EmptyCard(symbol:"tray",title:store.t("还没有匹配的记录","No matching records"),detail:store.t("调整筛选，或点击右上角“记一笔”。","Change your filters or add a record.")) }
            else { let shown=Array(results.dropFirst(page*100).prefix(100)); ForEach(shown) { r in RecordRow(record:r); if r.id != shown.last?.id { Divider().padding(.leading,58) } } }
        }.card(12)
        GQHistoryPager(page:$page,count:results.count).onChange(of:query) { _,_ in page=0 }.onChange(of:range) { _,_ in page=0 }.onChange(of:kind) { _,_ in page=0 }
        Text(store.t("共 \(results.count) 条记录 · 编辑不会回退已获得的岛屿成果","\(results.count) records · Editing never removes island progress")).font(.caption).foregroundStyle(.secondary)
    }
}
