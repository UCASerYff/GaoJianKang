import SwiftUI
import Foundation

public final class HealthBundleMarker: NSObject {}
enum HealthBundle {
    static let bundle = Bundle(for: HealthBundleMarker.self)
}

@MainActor private enum HealthRuntime {
    static let store = AppStore()
}

public struct HealthModuleView: View {
    @ObservedObject private var store = HealthRuntime.store
    private let route: URL?
    private let routeRevision: Int
    @State private var handledRevision = 0
    public init(route: URL? = nil, routeRevision: Int = 0) {
        self.route = route
        self.routeRevision = routeRevision
    }
    public var body: some View {
        ContentView()
            .environmentObject(store)
            .environment(\.locale, Locale(identifier: store.en ? "en_US" : "zh_CN"))
            .onAppear { store.syncSleepRewards(); handleRoute() }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("GaoSeries.health.game"))) { _ in store.selectedTab = 3 }
            .onChange(of: routeRevision) { _, _ in handleRoute() }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("GaoSeries.health.new"))) { _ in store.new(.meal) }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("GaoSeries.health.water"))) { _ in store.addWater() }
            // 备份导出/恢复收拢到 app 级「数据」页：模块内入口已移除，能力经通知触发。
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("GaoSeries.health.export"))) { _ in store.backup() }
            .onReceive(NotificationCenter.default.publisher(for: Notification.Name("GaoSeries.health.import"))) { _ in store.restore() }
    }
    private func handleRoute() {
        guard routeRevision > handledRevision, let route, route.scheme == "gaojiankang" else { return }
        handledRevision = routeRevision
        if route.host == "events" { store.selectedTab = 5 }
        else if let kind = RecordKind(rawValue: route.host ?? "") { store.new(kind) }
        else { store.selectedTab = 0 }
    }
}

/// 搞健康设置页（app 级设置中心嵌入用）：内容与模块原「设置」侧栏页一致，
/// store 由 framework 内 singleton 注入，外部嵌入无需提供环境对象。
public struct HealthSettingsView: View {
    @ObservedObject private var store = HealthRuntime.store
    public init() {}
    public var body: some View {
        SettingsView()
            .environmentObject(store)
            .environment(\.locale, Locale(identifier: store.en ? "en_US" : "zh_CN"))
    }
}

@MainActor public enum HealthModuleRuntime {
    public static func syncSleep() { HealthRuntime.store.syncSleepRewards() }
}
