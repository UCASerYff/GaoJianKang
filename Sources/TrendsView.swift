import SwiftUI
import Charts

struct TrendsView: View {
    @EnvironmentObject var store: AppStore
    @State private var days=7
    struct Point: Identifiable { var id:String; var date:Date; var value:Double }
    private var dates:[Date] {
        let c=Engine.calendar(store.state); let start=c.startOfDay(for:Date())
        return (0..<days).reversed().compactMap{ c.date(byAdding:.day,value:-$0,to:start) }
    }
    private var records:[HealthRecord] { store.state.records.filter { $0.occurredAt >= (dates.first ?? Date()) && $0.occurredAt<=Date() } }
    func points(_ kind:RecordKind,calories:Bool=false)->[Point] {
        dates.compactMap { date in
            let key=Engine.day(date,store.state)
            let rows=records.filter{$0.kind==kind && Engine.day($0.occurredAt,store.state)==key}
            guard !rows.isEmpty else { return nil }
            if kind == .weight { return .init(id:key,date:date,value:rows.max(by:{$0.occurredAt<$1.occurredAt})!.amount) }
            if calories { let values=rows.compactMap(\.calories); guard !values.isEmpty else{return nil}; return .init(id:key,date:date,value:values.reduce(0,+)) }
            return .init(id:key,date:date,value:rows.reduce(0){$0+$1.amount})
        }
    }
    private var weightAverage:[Point] {
        let c=Engine.calendar(store.state)
        let byDay=Dictionary(grouping:store.state.records.filter{$0.kind == .weight},by:{Engine.day($0.occurredAt,store.state)}).mapValues{$0.max(by:{$0.occurredAt<$1.occurredAt})!.amount}
        return dates.compactMap { date in
            var values:[Double]=[]
            for back in 0..<7 { if let d=c.date(byAdding:.day,value:-back,to:date), let v=byDay[Engine.day(d,store.state)] { values.append(v) } }
            guard !values.isEmpty else { return nil }
            return Point(id:Engine.day(date,store.state),date:date,value:values.reduce(0,+)/Double(values.count))
        }
    }
    var body: some View {
        HStack { SectionTitle(title:store.t("统计","Trends"),subtitle:store.t("看见积累，不必追逐完美曲线。","Notice the pattern. No perfect curve required.")); Spacer(); Picker("",selection:$days) { Text(store.t("今日","Today")).tag(1); Text(store.t("近 7 天","7 days")).tag(7); Text(store.t("近 30 天","30 days")).tag(30) }.pickerStyle(.segmented).frame(width:250) }
        HStack(spacing:14) {
            summary(store.t("饮水总量","Water logged"),"\(number(records.filter{$0.kind == .water}.reduce(0){$0+$1.amount})) mL","drop.fill",Theme.blue)
            summary(store.t("活动总时长","Active minutes"),"\(number(records.filter{$0.kind == .exercise}.reduce(0){$0+$1.amount})) min","figure.walk",Theme.green)
            summary(store.t("记录天数","Days with entries"),"\(Set(records.map{Engine.day($0.occurredAt,store.state)}).count) / \(days)","calendar",Theme.teal)
        }
        LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:18) {
            chart(store.t("饮水量","Water"),points(.water),"mL",Theme.blue,false)
            chart(store.t("运动时长","Activity"),points(.exercise),"min",Theme.green,false)
            if !store.state.preferences.hideCalories { chart(store.t("已记录摄入","Recorded intake"),points(.meal,calories:true),"kcal",Theme.orange,false); chart(store.t("已记录运动消耗","Recorded activity energy"),points(.exercise,calories:true),"kcal",Theme.purple,false) }
            if !store.state.preferences.hideWeight { chart(store.t("体重实测 · 青线为 7 日均线","Weight · teal line is the 7-day average"),points(.weight),"kg",Theme.purple,true,weightAverage) }
            nutrition
        }
        VStack(alignment:.leading,spacing:8) {
            Text(goalSummary).font(.callout)
            Text(store.t("缺失日期保留为空；未填营养或消耗不按 0 计算。摄入与运动消耗分开展示，不代表真实热量缺口。","Missing days stay empty. Missing nutrition or activity energy is not zero. Intake and activity energy do not represent a calorie deficit.")).font(.caption).foregroundStyle(.secondary)
            Text(store.t("统计日期时区：","Reporting timezone: ")+store.state.preferences.timezone).font(.caption).foregroundStyle(.secondary)
        }.card()
    }
    var goalSummary:String {
        let valid=dates.filter { store.state.preferences.config(Engine.day($0,store.state)).waterGoal != nil }
        let hit=valid.filter { date in let d=Engine.day(date,store.state); let total=records.filter{$0.kind == .water && Engine.day($0.occurredAt,store.state)==d}.reduce(0){$0+$1.amount}; return total >= (store.state.preferences.config(d).waterGoal ?? .infinity) }.count
        return valid.isEmpty ? store.t("尚未设置饮水目标，按实际记录展示。","No water goal set. Showing your records as they are.") : store.t("饮水达标：\(hit) / \(valid.count) 天（仅统计设置了目标的日期，含今日）","Water goal: \(hit) / \(valid.count) days with a configured goal, including today")
    }
    private func summary(_ title:String,_ value:String,_ symbol:String,_ color:Color)->some View {
        HStack { SymbolTile(symbol:symbol,color:color); VStack(alignment:.leading,spacing:5) { Text(value).font(.title3.weight(.semibold)); Text(title).font(.caption).foregroundStyle(.secondary) }; Spacer() }.card()
    }
    private func chart(_ title:String,_ data:[Point],_ unit:String,_ color:Color,_ weight:Bool,_ average:[Point]=[])->some View {
        VStack(alignment:.leading,spacing:14) {
            HStack { Text(title).font(.headline); Spacer(); Text(unit).font(.caption).foregroundStyle(.secondary) }
            if data.isEmpty { VStack(spacing:8) { Image(systemName:"chart.xyaxis.line").font(.title2); Text(store.t("还没有记录","No data yet")).font(.caption) }.foregroundStyle(.tertiary).frame(maxWidth:.infinity).frame(height:165) }
            else {
                Chart {
                    ForEach(data) { p in
                        if weight { PointMark(x:.value("Date",p.date),y:.value(unit,p.value)).foregroundStyle(color).symbolSize(40) }
                        else { BarMark(x:.value("Date",p.date,unit:.day),y:.value(unit,p.value)).foregroundStyle(color.opacity(0.8)).cornerRadius(3) }
                    }
                    ForEach(average) { p in
                        LineMark(x:.value("Date",p.date),y:.value(unit,p.value)).foregroundStyle(Theme.teal).interpolationMethod(.catmullRom).lineStyle(.init(lineWidth:2))
                    }
                }.chartXScale(domain:(dates.first ?? Date())...(Engine.calendar(store.state).date(byAdding:.day,value:1,to:dates.last ?? Date())!)).chartXAxis { AxisMarks(values:.stride(by:.day,count:max(1,days/5))) { _ in AxisValueLabel(format:.dateTime.month().day()); AxisGridLine() } }.frame(height:165)
            }
        }.card()
    }
    private var nutrition:some View {
        let meals=records.filter{$0.kind == .meal}
        let complete=meals.filter{$0.protein != nil && $0.carbs != nil && $0.fat != nil}
        let p=complete.reduce(0){$0+($1.protein ?? 0)},c=complete.reduce(0){$0+($1.carbs ?? 0)},f=complete.reduce(0){$0+($1.fat ?? 0)}
        return VStack(alignment:.leading,spacing:16) {
            Text(store.t("营养素记录","Nutrition logged")).font(.headline)
            Text(store.t("完整条目 \(complete.count) / \(meals.count) · 仅汇总完整条目","Complete entries \(complete.count) / \(meals.count) · complete entries only")).font(.caption).foregroundStyle(.secondary)
            ForEach(Array(zip([store.t("蛋白质","Protein"),store.t("碳水化合物","Carbs"),store.t("脂肪","Fat")],[p,c,f])),id:\.0) { title,n in HStack { Text(title); Spacer(); Text(complete.isEmpty ? "—" : "\(number(n)) g").monospacedDigit() }.font(.callout) }
            Spacer(minLength:0)
        }.frame(height:200,alignment:.topLeading).card()
    }
}
