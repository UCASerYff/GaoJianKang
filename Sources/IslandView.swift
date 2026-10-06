import SwiftUI

struct IslandView: View {
    @EnvironmentObject var store: AppStore
    var body: some View {
        HStack {
            SectionTitle(title:store.t("荒岛","Your island"),subtitle:store.t("没有终点，只有慢慢长成的家。","No finish line. Just a place that grows with you."))
            Spacer()
            if store.state.preferences.gameEnabled {
                Button(store.state.island.paused ? store.t("结束休整","Resume island") : store.t("让岛屿休整","Rest island")) {
                    if store.update({ s in Engine.settle(&s,now:Date()); s.island.paused.toggle(); s.island.lastSettled=Date(); s.island.lastVisit=Date() }) { store.syncSleepRewards() }
                }
            }
        }
        if !store.state.preferences.gameEnabled {
            EmptyCard(symbol:"moon.zzz",title:store.t("正在使用纯记录模式","Journal-only mode"),detail:store.t("需要时在设置中开启岛屿，所有健康记录始终保留。","Enable your island in Settings whenever you like. Your records are always yours."))
        } else {
            ReservesView()
            IslandScene(island:store.state.island,en:store.en)
            let island=store.state.island
            if let next=island.nextThreshold {
                let previous=Island.levelMarks[island.level-1]
                VStack(spacing:9) {
                    HStack { Text("Lv.\(island.level)").font(.callout.weight(.semibold)); Spacer(); Text(store.t("繁荣度 \(island.prosperity) · 距下一级还需 \(next-island.prosperity)","\(island.prosperity) prosperity · \(next-island.prosperity) to the next level")).font(.caption).foregroundStyle(.secondary) }
                    GeometryReader { geo in ZStack(alignment:.leading) { Capsule().fill(Theme.teal.opacity(0.12)); Capsule().fill(Theme.teal).frame(width:max(0,geo.size.width*Double(island.prosperity-previous)/Double(next-previous))) } }.frame(height:5)
                }.card(16)
            } else {
                HStack { Image(systemName:"crown.fill").foregroundStyle(Theme.orange); Text(store.t("已是传奇之岛 · 繁荣度 \(island.prosperity)","A legendary island · \(island.prosperity) prosperity")).font(.callout.weight(.medium)); Spacer() }.card(16)
            }
            let ledger=store.state.ledgers[Engine.day(Date(),store.state),default:DailyLedger()]
            VStack(alignment:.leading,spacing:14) {
                HStack { Text(store.t("今日健康转化","Powered by today's records")).font(.headline); Spacer(); Text(store.t("每日额度在零点重置","Daily limits reset at midnight")).font(.caption).foregroundStyle(.secondary) }
                LazyVGrid(columns:[GridItem(.adaptive(minimum:170),spacing:16)],spacing:16) {
                    conversion(store.t("喝水 → 水分","Water"),ledger.water,80,"drop.fill",Theme.blue)
                    conversion(store.t("三餐 → 饱食","Meals"),ledger.food,75,"fork.knife",Theme.orange)
                    conversion(store.t("运动 → 活力","Activity"),ledger.activity,Double(18+max(0,island.buildingLevel("training")-1)*3),"bolt.fill",Theme.green)
                    conversion(store.t("睡眠 → 活力","Sleep"),ledger.sleepEnergy,24,"moon.stars.fill",Theme.purple)
                }
                Text(store.t("搞节奏完成睡眠后自动恢复活力：每小时 +3，每日最多 +24；最近 36 小时的记录可补领一次。","Completed sleep in Rhythm restores 3 energy per hour, up to 24 per day. Records from the last 36 hours can be claimed once.")).font(.caption).foregroundStyle(.secondary)
            }.card()
            LazyVGrid(columns:[GridItem(.adaptive(minimum:150),spacing:12)],spacing:12) {
                ForEach(Catalog.materials,id:\.self) { key in
                    HStack(spacing:10) { SymbolTile(symbol:Catalog.symbol(key),color:key=="ration" ? Theme.orange : Theme.teal); VStack(alignment:.leading,spacing:2) { Text("\(store.state.island.inventory[key,default:0])").font(.title3.weight(.semibold)).monospacedDigit(); Text(Catalog.name(key,store.en)).font(.caption).foregroundStyle(.secondary) }; Spacer() }.card(14)
                }
            }
            HStack {
                Button(store.t("食用补给 +\(5+3*island.buildingLevel("kitchen")) 饱食","Eat supplies +\(5+3*island.buildingLevel("kitchen")) food")) { _ = store.update { try Engine.supply(&$0,now:Date()) } }.disabled(store.state.island.paused || store.state.island.inventory["ration",default:0]==0 || store.state.island.food>=100 || store.state.ledgers[Engine.day(Date(),store.state),default:DailyLedger()].supplies>=3).help(store.t("消耗 1 干粮，每日最多 3 次","Costs 1 ration; 3 times per day"))
                Spacer()
            }
            HStack { Text(store.t("到岛上忙一会儿","A little island work")).font(.title3.weight(.semibold)); Spacer(); Text(store.state.island.buildings.contains("campfire") ? store.t("劳作消耗三维产出材料，材料换来更好的家","Work turns reserves into materials, materials into a better home") : store.t("先收集 6 木材 + 2 石材，就能点起篝火","Your first campfire: 6 wood + 2 stone")).font(.caption).foregroundStyle(.secondary) }
            LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible()),GridItem(.flexible())],spacing:14) {
                ForEach(Catalog.actions) { a in
                    let problem=Engine.actionProblem(store.state,a)
                    VStack(alignment:.leading,spacing:12) {
                        HStack { SymbolTile(symbol:a.symbol,color:Theme.teal); Text(a.title(store.en)).font(.headline); Spacer(); Text("+\(Engine.yield(store.state,a))").font(.title3.weight(.semibold)).foregroundStyle(Theme.teal) }
                        Text(Catalog.name(a.output,store.en) + (a.id=="coconut" ? store.t(" · 饱食 +3"," · +3 food") : "")).font(.caption).foregroundStyle(.secondary)
                        HStack(spacing:9) {
                            Label("−\(Int(a.energy))",systemImage:"bolt.fill").foregroundStyle(Theme.green)
                            if a.food>0 { Label("−\(Int(a.food))",systemImage:"fork.knife").foregroundStyle(Theme.orange) }
                            if a.water>0 { Label("−\(Int(a.water))",systemImage:"drop.fill").foregroundStyle(Theme.blue) }
                            Spacer()
                        }.font(.caption)
                        Button { store.perform(a.id) } label:{ Text(problem ?? store.t("出发","Let's go")).frame(maxWidth:.infinity) }.buttonStyle(.bordered).disabled(problem != nil).accessibilityLabel(a.title(store.en) + " · " + (problem ?? store.t("出发","Go")))
                    }.card(17)
                }
            }
            Text(store.t("建造一个家","Build a place to stay")).font(.title3.weight(.semibold))
            LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible()),GridItem(.flexible())],spacing:14) {
                ForEach(Catalog.recipes) { r in
                    let owned=Engine.has(store.state,r.id)
                    let problem=Engine.buildProblem(store.state,r)
                    VStack(alignment:.leading,spacing:12) {
                        HStack { SymbolTile(symbol:r.symbol,color:r.tool ? Theme.blue : Theme.orange); Text(r.title(store.en)).font(.headline); Spacer(); if owned { Image(systemName:"checkmark.seal.fill").foregroundStyle(Theme.teal) } }
                        Text(store.en ? r.detailEN : r.detailCN).font(.caption).foregroundStyle(.secondary).frame(height:28,alignment:.leading)
                        Text(Catalog.materials.compactMap { key in r.cost[key].map{"\(Catalog.name(key,store.en)) \($0)"} }.joined(separator:" · ")).font(.caption)
                        Button { store.construct(r.id) } label:{ Text(problem ?? store.t(r.tool ? "打造" : "建造",r.tool ? "Craft" : "Build")).frame(maxWidth:.infinity) }.buttonStyle(.bordered).tint(Theme.teal).disabled(problem != nil).accessibilityLabel(r.title(store.en) + " · " + (problem ?? store.t("建造","Build")))
                    }.card(17)
                }
            }
            VStack(alignment:.leading,spacing:14) {
                HStack { Image(systemName:"water.waves").foregroundStyle(Theme.blue); Text(store.t("扩建岛屿","Expand the island")).font(.title3.weight(.semibold)); Spacer(); Text("\(island.expansionLevel) / 3").font(.headline.monospacedDigit()) }
                Text(store.t("开拓新的海岸，每次扩建增加 30 繁荣度；沙滩、栈桥和海湾会逐步出现在岛上。","Open new shores. Each expansion adds 30 prosperity and changes the island scene.")).font(.callout).foregroundStyle(.secondary)
                if island.expansionLevel < 3 {
                    let stage=island.expansionLevel
                    Text(store.t("第 \(stage+1) 阶段 · 需要繁荣度 \(Engine.expansionRequirements[stage])","Stage \(stage+1) · Requires \(Engine.expansionRequirements[stage]) prosperity")).font(.caption.weight(.medium))
                    Text(costText(Engine.expansionCosts[stage])).font(.caption).foregroundStyle(.secondary)
                    let problem=Engine.expansionProblem(store.state)
                    Button(problem ?? store.t("开拓海岸","Expand shore")) { store.expandIsland() }.disabled(problem != nil)
                } else {
                    Label(store.t("海岸已全部开拓","All shores opened"),systemImage:"checkmark.seal.fill").foregroundStyle(Theme.teal)
                }
            }.card()
            Text(store.t("升级设施","Upgrade buildings")).font(.title3.weight(.semibold))
            Text(store.t("每座建筑可升至 4 级。升级增加繁荣度，也会强化每日产出或劳作收益。","Each building has four levels. Upgrades add prosperity and improve daily or work rewards.")).font(.callout).foregroundStyle(.secondary)
            LazyVGrid(columns:[GridItem(.flexible()),GridItem(.flexible())],spacing:14) {
                ForEach(Catalog.recipes.filter { !$0.tool && island.buildings.contains($0.id) }) { r in
                    let level=island.buildingLevel(r.id)
                    let problem=Engine.upgradeProblem(store.state,r)
                    VStack(alignment:.leading,spacing:10) {
                        HStack { SymbolTile(symbol:r.symbol,color:Theme.orange); Text(r.title(store.en)).font(.headline); Spacer(); Text("Lv.\(level) / 4").font(.caption.weight(.semibold)).foregroundStyle(Theme.teal) }
                        HStack(spacing:4) { ForEach(1...4,id:\.self) { tier in Capsule().fill(tier<=level ? Theme.orange : Theme.orange.opacity(0.12)).frame(height:5) } }
                        Text(upgradeEffect(r.id,level:level)).font(.caption).foregroundStyle(.secondary)
                        if level < 4 { Text(costText(Engine.upgradeCost(r,to:level+1))).font(.caption) }
                        Button(problem ?? store.t("升级至 \(level+1) 级","Upgrade to level \(level+1)")) { store.upgrade(r.id) }.buttonStyle(.bordered).tint(Theme.orange).disabled(problem != nil)
                    }.card(17)
                }
            }
            if !store.state.island.logs.isEmpty {
                VStack(alignment:.leading,spacing:12) {
                    Text(store.t("岛屿日志","Island journal")).font(.headline)
                    ForEach(store.state.island.logs.suffix(8).reversed()) { log in HStack { Text(log.description).font(.caption); Spacer(); Text(log.date,style:.time).font(.caption).foregroundStyle(.secondary) } }
                }.card()
            }
            Text(store.t("离线最多结算 24 小时衰减；休整暂停经营。今天没运动，也可以慢慢建设。","Offline decay stops after 24 hours. Rest mode pauses gameplay. No workout is required to keep building.")).font(.caption).foregroundStyle(.secondary)
        }
    }
    private func conversion(_ title:String,_ value:Double,_ cap:Double,_ symbol:String,_ color:Color)->some View {
        VStack(alignment:.leading,spacing:8) {
            HStack(spacing:8) { Image(systemName:symbol).foregroundStyle(color); Text(title).font(.caption).foregroundStyle(.secondary) }
            HStack(alignment:.firstTextBaseline,spacing:3) { Text("+\(number(value))").font(.title3.weight(.semibold)).monospacedDigit(); Text("/ \(number(cap))").font(.caption).foregroundStyle(.tertiary) }
            GeometryReader { geo in ZStack(alignment:.leading) { Capsule().fill(color.opacity(0.10)); Capsule().fill(color).frame(width:max(0,geo.size.width*min(1,value/cap))) } }.frame(height:4)
        }.frame(maxWidth:.infinity,alignment:.leading)
    }
    private func costText(_ cost:[String:Int])->String {
        Catalog.materials.compactMap { key in cost[key].map { "\(Catalog.name(key,store.en)) \($0)" } }.joined(separator:" · ")
    }
    private func upgradeEffect(_ id:String,level:Int)->String {
        let n=level
        switch id {
        case "garden": return store.t("每日 +\(n+1) 干粮","+\(n+1) rations daily")
        case "farm": return store.t("每日 +\(3+2*n) 干粮","+\(3+2*n) rations daily")
        case "clinic": return store.t("每日 +\(2+3*n) 活力","+\(2+3*n) energy daily")
        case "training": return store.t("运动奖励 ×\(String(format:"%.2f",1.25+Double(n-1)*0.1))，每日上限 \(18+(n-1)*3)","Activity ×\(String(format:"%.2f",1.25+Double(n-1)*0.1)), daily cap \(18+(n-1)*3)")
        case "shelter": return store.t("休息时衰减进一步降低","Less decay while resting")
        case "well": return store.t("水分衰减进一步降低","Less water decay")
        case "campfire": return store.t("叉鱼额外 +\(n-1)","Fishing +\(n-1) extra")
        case "herbGarden": return store.t("采药额外 +\(n-1)","Herbs +\(n-1) extra")
        case "rainCollector": return store.t("每日 +\(6*n) 水分","+\(6*n) water daily")
        case "orchard": return store.t("每日 +\(2*n) 干粮","+\(2*n) rations daily")
        case "workshop": return store.t("采集活力消耗降低 \(5*n)%","Gathering energy −\(5*n)%")
        case "windmill": return store.t("采麻额外 +\(n) 纤维","Fiber gathering +\(n)")
        case "kitchen": return store.t("每份干粮 +\(5+3*n) 饱食","Each ration +\(5+3*n) food")
        case "teaHouse": return store.t("泡茶 +\(8+4*n) 活力，每日 2 次","Tea +\(8+4*n) energy, twice daily")
        default: return ""
        }
    }
}
