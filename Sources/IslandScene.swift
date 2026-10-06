import SwiftUI
import SceneKit

struct IslandPreview: View {
    let island: Island
    let en: Bool
    var body:some View {
        IslandScene(island:island,en:en,overviewOnly:true)
            .allowsHitTesting(false).accessibilityHidden(true)
            .clipShape(RoundedRectangle(cornerRadius:18))
    }
}

struct IslandScene: View {
    @EnvironmentObject private var store: AppStore
    var island: Island
    var en = false
    @State private var selectedID: String?
    private let yaw = 42.0
    @State private var zoom = 8.5

    @State private var layoutMode = false
    @State private var draft: [String:IslandPoint] = [:]
    @State private var layoutNotice = ""

    private var items: [GQWorldItem] {
        [GQWorldItem(id:"__world",title:"",kind:"__world",level:island.expansionLevel,x:0,z:0,movable:false)] +
        Catalog.recipes.filter { !$0.tool && island.buildingLevel($0.id) > 0 }.map { recipe in
            let point = layoutMode ? (draft[recipe.id] ?? Engine.site(island,recipe.id)) : Engine.site(island,recipe.id)
            return GQWorldItem(id: recipe.id, title: recipe.title(en), kind: recipe.id,
                               level: island.buildingLevel(recipe.id), x: point.x, z: point.z,movable:layoutMode)
        }
    }
    private var selectedRecipe: Recipe? { Catalog.recipes.first { $0.id == selectedID && !$0.tool } }

    var overviewOnly = false
    @ViewBuilder var body: some View {
        if overviewOnly {
            GQWorldScene(mode:"island",items:items,selectedID:nil,yaw:yaw,zoom:8.5+Double(island.expansionLevel)*1.6,observationOnly:true,onSelect:{_ in},onMove:{_,_,_ in})
        } else { interactiveBody }
    }
    private var interactiveBody: some View {
        ZStack(alignment: .top) {
            GQWorldScene(mode: "island", items: items, selectedID: selectedID, yaw: yaw, zoom: zoom,
                         onSelect: { selectedID = $0 }, onMove: move,
                         onZoom:{ zoom=min(25,max(6,zoom+$0)) })
            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(en ? "THE LIVING ISLAND" : "活力之岛")
                            .font(.system(size: 11, weight: .bold, design: .monospaced)).tracking(2)
                        Text(en ? "Build a home on the island" : "在岛上亲手建一座家")
                            .font(.title2.weight(.bold))
                        Text(layoutMode ? (layoutNotice.isEmpty ? (en ? "Drag buildings · save or cancel when finished" : "拖动布置建筑 · 完成后保存或取消") : layoutNotice) : (en ? "Click a building to inspect · enter Layout to move" : "点击建筑查看和升级 · 移动建筑请进入布局模式"))
                            .font(.caption).foregroundStyle(.white.opacity(0.82))
                    }.foregroundStyle(.white).shadow(color: .black, radius: 8)
                    Spacer()
                    HStack(spacing: 6) {
                        if layoutMode {
                            Button(en ? "Cancel" : "取消") { layoutMode=false;draft=[:] }
                            Button(en ? "Save layout" : "保存布局") {
                                if store.update({ try Engine.applyLayout(&$0,placements:draft) }) { layoutMode=false }
                            }.buttonStyle(.borderedProminent)
                        } else {
                            Button { draft=Dictionary(uniqueKeysWithValues:island.buildings.map { ($0,Engine.site(island,$0)) });layoutNotice="";layoutMode=true } label: { Label(en ? "Layout" : "布局模式",systemImage:"square.and.pencil") }.buttonStyle(.bordered)
                        }
                        control("plus.magnifyingglass", en ? "Zoom in" : "放大") { zoom = max(6, zoom - 1.5) }
                        control("minus.magnifyingglass", en ? "Zoom out" : "缩小") { zoom = min(25, zoom + 1.5) }
                    }
                }.padding(18)
                Spacer()
                if !layoutMode, let recipe = selectedRecipe, island.buildingLevel(recipe.id) > 0 { selectedPanel(recipe) }
                HStack(spacing: 8) {
                    Menu {
                        ForEach(Catalog.recipes.filter { !$0.tool && island.buildingLevel($0.id) == 0 }) { recipe in
                            let problem = Engine.buildProblem(store.state, recipe)
                            Button(recipe.title(en) + (problem.map { " · \($0)" } ?? "")) { store.construct(recipe.id); selectedID = recipe.id }
                                .disabled(problem != nil)
                        }
                    } label: { Label(en ? "Build" : "建造", systemImage: "hammer.fill") }
                        .disabled(Catalog.recipes.filter { !$0.tool }.allSatisfy { island.buildingLevel($0.id) > 0 })
                    Menu {
                        ForEach(Catalog.actions) { action in
                            let problem = Engine.actionProblem(store.state, action)
                            Button(action.title(en) + (problem.map { " · \($0)" } ?? "")) { store.perform(action.id) }
                                .disabled(problem != nil)
                        }
                    } label: { Label(en ? "Gather" : "采集", systemImage: "leaf.fill") }
                    let expansionProblem = Engine.expansionProblem(store.state)
                    Button { store.expandIsland() } label: { Label(en ? "Expand" : "扩地", systemImage: "water.waves") }
                        .disabled(expansionProblem != nil).help(expansionProblem ?? "")
                    Spacer()
                    Label("Lv.\(island.level) · \(island.prosperity)", systemImage: "sparkles")
                }
                .disabled(layoutMode)
                .font(.caption.weight(.semibold)).buttonStyle(.bordered)
                .padding(12).background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                .padding([.horizontal,.bottom], 15)
            }
        }
        .onDisappear { layoutMode=false;draft=[:] }
        .frame(height: 490)
        .clipShape(RoundedRectangle(cornerRadius: 20))
    }
    private func control(_ symbol: String, _ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).frame(width: 28, height: 28) }
            .buttonStyle(.bordered).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .help(title)
    }
    private func selectedPanel(_ recipe: Recipe) -> some View {
        let level = island.buildingLevel(recipe.id)
        let problem = Engine.upgradeProblem(store.state, recipe)
        return HStack(spacing: 12) {
            Image(systemName: recipe.symbol).font(.title2).foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text(recipe.title(en) + " · Lv.\(level)").font(.headline)
                Text(en ? recipe.detailEN : recipe.detailCN).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer()
            if recipe.id == "teaHouse" {
                Button(en ? "Brew · 2 herbs" : "泡茶 · 2 药材") { store.update { try Engine.brewTea(&$0,now:Date()) } }
                    .disabled(Engine.teaProblem(store.state,now:Date()) != nil).help(Engine.teaProblem(store.state,now:Date()) ?? "")
            }
            Button(level >= 4 ? (en ? "Max level" : "已满级") : (en ? "Upgrade" : "升级外观与能力")) {
                store.upgrade(recipe.id)
            }.disabled(problem != nil).help(problem ?? "")
            Button { selectedID = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
        }.padding(12).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .padding(.horizontal, 15).padding(.bottom, 8)
    }
    private func move(_ id: String, _ x: Double, _ z: Double) {
        guard layoutMode, island.buildingLevel(id) > 0, Engine.placementAllowed(x:x,z:z,expansion:island.expansionLevel) else { return }
        guard items.filter({ $0.id != id && $0.kind != "__world" }).allSatisfy({ hypot($0.x-x, $0.z-z) > 1.5 }) else { layoutNotice=en ? "Leave space between buildings" : "建筑之间需要留出空间";return }
        draft[id]=IslandPoint(x:x,z:z);layoutNotice=""
    }
}
