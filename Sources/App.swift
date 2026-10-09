import SwiftUI
import AppKit

// 独立 App 入口（HealthApp 与 AppDelegate）已随整合版移除；
// 模块视图由 Health/Module.swift 的 HealthModuleView 承载。
struct ContentView: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.colorScheme) private var scheme
    @Environment(\.scenePhase) private var phase
    /// 侧栏隐藏/显示（场景级记忆；键全 app 唯一）。只有 隐藏↔显示 两态，无「收起成图标栏」。
    @SceneStorage("gqns.sidebarHidden.health") private var sidebarHidden = false
    /// 自绘侧栏导航行的 hover 跟踪（浅灰反馈，与词元一致）。
    @State private var hoveredTab: Int?
    var body: some View {
        // 侧栏重设计（对齐词元 2.2/2.3 标杆）：弃用系统 NavigationSplitView 列表侧栏，
        // 改 HStack 自绘——品牌头部 + 浮动卡片选中态导航行 + hover 反馈 + 状态底卡。
        // 统一工具栏契约：.navigation 恰好一个 28×28 侧栏切换按钮（⌃⌘S）；
        // 原有 trailing「记一笔」菜单保留，包在固定宽 360 的右对齐容器里。
        HStack(spacing:0) {
            if !sidebarHidden {
                sidebar
                // 自绘发丝线替代系统 Divider：避免 Tahoe 统一标题栏下系统 separator 冷启动首帧误渲染成灰带
                Rectangle().fill(Color.primary.opacity(0.12)).frame(width: 1).frame(maxHeight: .infinity)
            }
            VStack(spacing:0) {
            if let fatal=store.fatalError {
                VStack(spacing:16) { EmptyCard(symbol:"externaldrive.badge.exclamationmark",title:store.t("暂时无法读取数据","Data unavailable"),detail:fatal); HStack { Button(store.t("重试","Retry")) { store.reload() }; Button(store.t("从备份恢复","Restore backup")) { store.restore() } } }.frame(maxWidth:.infinity,maxHeight:.infinity)
            } else {
                ScrollView {
                    VStack(alignment:.leading,spacing:20) {
                        switch store.selectedTab {
                        case 10: SleepRecordsView()
                        case 5: QuickEventsView()
                        case 0: TodayView()
                        case 2: TrendsView()
                        case 3: IslandView()
                        case 6: RecordsView(kind:.water)
                        case 7: RecordsView(kind:.meal)
                        case 8: RecordsView(kind:.exercise)
                        case 9: if store.state.preferences.hideWeight { TodayView() } else { RecordsView(kind:.weight) }
                        default: SettingsView()
                        }
                    }.padding(28).frame(maxWidth:1250).frame(maxWidth:.infinity)
                }.id(store.selectedTab)
            }
            if let notice=store.notice {
                HStack { Image(systemName:"checkmark.circle.fill").foregroundStyle(Theme.teal); Text(notice).font(.caption); Spacer(); if store.undoRecord != nil || store.undoEvent != nil { Button(store.t("撤销","Undo")) { store.undo() }.buttonStyle(.link) }; Button { store.notice=nil; store.undoRecord=nil; store.undoEvent=nil } label:{ Image(systemName:"xmark") }.buttonStyle(.plain).help(store.t("关闭提示","Dismiss")) }.padding(.horizontal,24).padding(.vertical,10).background(Theme.teal.opacity(0.07))
            }
            }
            .background(Theme.background(scheme == .dark,store.state.preferences.backgroundHex))
        }
        .frame(minWidth:1000,minHeight:680)
        .animation(.easeInOut(duration:0.22),value:sidebarHidden)
        .toolbar {
            toolbarItemNoChrome(.navigation) {
                Button {
                    withAnimation(.easeInOut(duration:0.22)) { sidebarHidden.toggle() }
                } label: {
                    SidebarToggleIcon()
                }
                .buttonStyle(.plain)
                .keyboardShortcut("s",modifiers:[.command,.control])
                .help(store.t(sidebarHidden ? "显示侧边栏" : "隐藏侧边栏",sidebarHidden ? "Show Sidebar" : "Hide Sidebar"))
            }
            toolbarItemNoChrome(.primaryAction) {
                HStack(spacing:12) {
                    Menu {
                        Button(store.t("睡眠记录","Sleep")) { store.newSleep() }
                        ForEach(RecordKind.allCases) { kind in Button(kind.title(store.en)) { store.new(kind) } }
                    } label: { Label(store.t("记一笔","Record"),systemImage:"plus") }
                    BackfillRecordMenu()
                }
                .frame(width:360,alignment:.trailing)
            }
        }
        .sheet(isPresented:$store.sleepEditor) { SleepRecordEditor().environmentObject(store) }
        .sheet(item:$store.editor) { record in RecordEditor(record:record).environmentObject(store) }
        .alert(store.t("操作未完成","Action failed"),isPresented:Binding(get:{ store.message != nil },set:{ if !$0 { store.message=nil } })) { Button(store.t("好","OK")) { store.message=nil } } message:{ Text(store.message ?? "") }
        .onChange(of:phase) { _,p in if p == .active { store.reload() } }
        .onChange(of:store.selectedTab) { _,tab in if tab==3 { store.welcome() } else { store.reload() } }
        .onChange(of:store.notice) { _,current in
            guard let current else { return }
            Task { @MainActor in
                try? await Task.sleep(for:.seconds(8))
                if store.notice == current { store.notice=nil; store.undoRecord=nil; store.undoEvent=nil }
            }
        }
    }

    // MARK: 自绘侧边栏（词元标杆）：品牌头部 + 浮动卡片选中态导航行 + 状态底卡

    private var sidebar: some View {
        VStack(spacing:0) {
            brandHeader
            ScrollView {
                VStack(alignment:.leading,spacing:20) {
                    sidebarSection(store.t("健康管理","Health")) {
                        sidebarRow(0,title:store.t("今日概览","Today"),symbol:"sun.max")
                        sidebarRow(5,title:store.t("快速事项","Quick events"),symbol:"square.grid.3x3.fill")
                        sidebarRow(6,title:store.t("喝水记录","Water"),symbol:"drop.fill")
                        sidebarRow(10,title:store.t("睡眠记录","Sleep"),symbol:"moon.stars.fill")
                        sidebarRow(7,title:store.t("饮食记录","Meals"),symbol:"fork.knife")
                        sidebarRow(8,title:store.t("运动记录","Activity"),symbol:"figure.walk")
                        if !store.state.preferences.hideWeight { sidebarRow(9,title:store.t("体重记录","Weight"),symbol:"scalemass.fill") }
                        sidebarRow(2,title:store.t("统计趋势","Trends"),symbol:"chart.xyaxis.line")
                    }
                    sidebarSection(store.t("奖励系统","Rewards")) {
                        sidebarRow(3,title:store.t("荒岛生活","Island"),symbol:"tree")
                    }
                }
                .padding(.horizontal,14)
                .padding(.vertical,14)
                .frame(maxWidth:.infinity,alignment:.leading)
            }
            statusFooter
        }
        .frame(width:236)
        .frame(maxHeight:.infinity)
        .background(.regularMaterial)
    }
    private var brandHeader: some View {
        HStack(spacing:10) {
            if let image = NSImage(contentsOf:HealthBundle.bundle.url(forResource:"GaoJianKangCalligraphy",withExtension:"png") ?? URL(fileURLWithPath:"")) {
                Image(nsImage:image).resizable()
                    .interpolation(.high)
                    .frame(width:38,height:38)
                    .clipShape(RoundedRectangle(cornerRadius:9,style:.continuous))
                    .accessibilityHidden(true)
            }
            VStack(alignment:.leading,spacing:2) {
                Text(store.t("搞健康","Gao Health")).font(.headline)
                Text(store.t("喝水、睡眠、饮食与运动","Water, sleep, meals and activity")).font(.caption2).foregroundStyle(.secondary)
            }
            Spacer(minLength:0)
        }
        .padding(.horizontal,14)
        .padding(.top,14)
        .padding(.bottom,10)
        .frame(maxWidth:.infinity)
    }
    @ViewBuilder private func sidebarSection<Rows: View>(_ title:String,@ViewBuilder rows: () -> Rows) -> some View {
        VStack(alignment:.leading,spacing:4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.tertiary)
                .padding(.horizontal,10)
                .padding(.bottom,2)
            rows()
        }
    }
    /// 浮动卡片选中态导航行：accent 底白字 + 柔和投影（深色下投影 opacity 调高），hover 浅灰反馈。
    private func sidebarRow(_ tab:Int,title:String,symbol:String) -> some View {
        let selected = store.selectedTab == tab
        let hovered = hoveredTab == tab
        return Button { store.selectedTab = tab } label: {
            HStack(spacing:10) {
                Image(systemName:symbol)
                    .font(.callout)
                    .frame(width:20)
                Text(title)
                    .font(.callout.weight(selected ? .semibold : .regular))
                    .lineLimit(1)
                Spacer(minLength:0)
            }
            .padding(.horizontal,10)
            .frame(maxWidth:.infinity,minHeight:32)
            .foregroundStyle(selected ? Color.white : Color.primary)
            .background {
                if selected {
                    RoundedRectangle(cornerRadius:9,style:.continuous)
                        .fill(Theme.teal)
                        .shadow(color:Theme.teal.opacity(scheme == .dark ? 0.45 : 0.32),radius:5,y:2)
                } else if hovered {
                    RoundedRectangle(cornerRadius:9,style:.continuous)
                        .fill(Color.primary.opacity(0.06))
                }
            }
            .contentShape(RoundedRectangle(cornerRadius:9,style:.continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in hoveredTab = hovering ? tab : nil }
    }
    /// 状态底卡（词元 statusFooter 风格）：今日记录数 + 存储说明。
    private var statusFooter: some View {
        let todayCount = store.state.records.filter { Calendar.current.isDateInToday($0.occurredAt) }.count + store.sleepRecords.filter { Calendar.current.isDateInToday($0.endedAt) }.count
        return VStack(alignment:.leading,spacing:7) {
            HStack(spacing:7) {
                Circle().fill(Theme.teal).frame(width:7,height:7)
                Text(store.t("今日 \(todayCount) 条记录","\(todayCount) records today")).font(.caption)
                Spacer(minLength:0)
            }
            Text(store.t("数据保存在本机","Stored on this Mac")).font(.system(size:10)).foregroundStyle(.tertiary)
        }
        .padding(12)
        .background(Color.primary.opacity(0.04),in:RoundedRectangle(cornerRadius:12,style:.continuous))
        .padding(.horizontal,14)
        .padding(.vertical,12)
    }
}

// MARK: - 工具栏项 chrome 隐藏（macOS 26 起工具栏项带 sharedBackground 玻璃胶囊，
// 自绘的侧栏切换按钮与固定宽 360 trailing 容器会被罩上多余色块；只去底色，不改几何与交互）
@ToolbarContentBuilder
private func toolbarItemNoChrome<Content: View>(
    _ placement: ToolbarItemPlacement,
    @ViewBuilder content: @escaping () -> Content
) -> some ToolbarContent {
    if #available(macOS 26.0, *) {
        ToolbarItem(placement: placement, content: content)
            .sharedBackgroundVisibility(.hidden)
    } else {
        ToolbarItem(placement: placement, content: content)
    }
}

/// 侧栏切换按钮图标：chrome 隐藏后补轻量 hover 底色，保证图标清晰、反馈合理。
private struct SidebarToggleIcon: View {
    @State private var hovering = false
    var body: some View {
        Image(systemName: "sidebar.left")
            .frame(width: 28, height: 28)
            .background(
                Color.primary.opacity(hovering ? 0.08 : 0),
                in: RoundedRectangle(cornerRadius: 6)
            )
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .animation(.easeInOut(duration: 0.12), value: hovering)
    }
}
