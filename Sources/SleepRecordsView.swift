import SwiftUI

struct SleepRecordsView: View {
    @EnvironmentObject var store: AppStore
    @State private var deletion: SharedSleepEntry?
    @State private var visibleCount = 30
    var body: some View {
        HStack(alignment:.bottom) {
            SectionTitle(title:store.t("睡眠记录","Sleep records"),subtitle:store.t("在搞健康或搞节奏记一次，两边自动显示。","Record once in Health or Rhythm. Both apps stay in sync."))
            Spacer()
            Button { store.syncSleepRewards() } label:{ Label(store.t("同步记录","Sync records"),systemImage:"arrow.triangle.2.circlepath") }
            Button { store.sleepEditor = true } label:{ Label(store.t("记录睡眠","Record sleep"),systemImage:"plus") }.buttonStyle(.borderedProminent).tint(Theme.purple)
        }
        SleepSummaryCard()
        VStack(alignment:.leading,spacing:10) {
            Label(store.t("睡眠也能恢复活力","Sleep restores energy, too"),systemImage:"moon.stars.fill").font(.headline).foregroundStyle(Theme.purple)
            Text(store.t("每小时恢复 3 点活力，每日最多 24 点。最近 36 小时内结束、时长 30 分钟至 24 小时的睡眠可领取一次；更早的记录仍会保留。岛屿暂停或关闭时不领奖，恢复后在有效期内自动补领。","Restore 3 energy per hour, up to 24 per day. Completed sleep of 30 minutes to 24 hours can be rewarded once within 36 hours. Older records are retained. Rewards wait while the island is paused or disabled.")).font(.callout).foregroundStyle(.secondary)
            Text(store.t("同一台 Mac 上自动同步。搞节奏未运行时，下次打开会同步到历史记录和小组件；两边已获得的奖励不会重复发放。","Sync is local to this Mac. If Rhythm is closed, its history and widgets update when it next opens. Earned rewards are not granted twice.")).font(.caption).foregroundStyle(.secondary)
        }.card()
        if let error = store.sleepSyncError {
            Label(error,systemImage:"exclamationmark.triangle").font(.callout).foregroundStyle(Theme.orange).card()
        } else if let date = store.sleepSyncedAt {
            Label(store.t("自动同步已开启 · 最近同步 ","Automatic sync · Updated ")+date.formatted(date:.omitted,time:.shortened),systemImage:"checkmark.circle").font(.caption).foregroundStyle(.secondary)
        }
        VStack(alignment:.leading,spacing:0) {
            HStack { Text(store.t("睡眠历史","Sleep history")).font(.headline); Spacer(); Text(store.t("共 \(store.sleepRecords.count) 条","\(store.sleepRecords.count) records")).font(.caption).foregroundStyle(.secondary) }.padding(.bottom,12)
            if store.sleepRecords.isEmpty {
                EmptyCard(symbol:"moon.zzz.fill",title:store.t("记录一个安稳的夜晚","A place for your nights"),detail:store.t("补记就寝和起床时间，也会自动显示在搞节奏中。","Enter bedtime and wake-up time. It will appear in Rhythm automatically."))
            }
            ForEach(Array(store.sleepRecords.prefix(visibleCount))) { record in
                HStack(spacing:14) {
                    SymbolTile(symbol:"moon.stars.fill",color:Theme.purple)
                    VStack(alignment:.leading,spacing:5) {
                        Text(record.endedAt.formatted(date:.abbreviated,time:.omitted)).font(.callout.weight(.medium))
                        Text(record.startedAt.formatted(date:.abbreviated,time:.shortened)+" → "+record.endedAt.formatted(date:.abbreviated,time:.shortened)).font(.caption).foregroundStyle(.secondary)
                        Text(record.origin == "health" ? store.t("来自搞健康","From Health") : store.t("来自搞节奏","From Rhythm")).font(.caption2).foregroundStyle(.tertiary)
                    }
                    Spacer()
                    Text(sleepDuration(record.durationSeconds,en:store.en)).font(.title3.monospacedDigit().weight(.semibold))
                    Button(role:.destructive) { deletion = record } label:{ Image(systemName:"trash") }.buttonStyle(.borderless).help(store.t("从两边删除这条记录","Delete this record from both apps"))
                }.padding(.vertical,12)
                Divider()
            }
            if visibleCount < store.sleepRecords.count {
                Button(store.t("显示更多","Show more")) { visibleCount += 30 }.padding(.top,12)
            }
        }.card()
        .alert(store.t("删除这条睡眠记录？","Delete this sleep record?"),isPresented:Binding(get:{ deletion != nil },set:{ if !$0 { deletion = nil } })) {
            Button(store.t("取消","Cancel"),role:.cancel) { deletion = nil }
            Button(store.t("从两边删除","Delete from both"),role:.destructive) { if let deletion { store.removeSleep(deletion) }; deletion = nil }
        } message:{ Text(store.t("搞健康与搞节奏会同步删除这条记录，已获得的游戏奖励不会回退。","This removes the record from Health and Rhythm. Earned game rewards are retained.")) }
    }
}

struct SleepSummaryCard: View {
    @EnvironmentObject var store: AppStore
    private var today: [SharedSleepEntry] { store.sleepRecords.filter { Engine.day($0.endedAt,store.state) == Engine.day(Date(),store.state) } }
    var body: some View {
        HStack(spacing:16) {
            SymbolTile(symbol:"moon.stars.fill",color:Theme.purple)
            VStack(alignment:.leading,spacing:4) {
                Text(store.t("今日睡眠","Today's sleep")).font(.headline)
                Text(store.t("按起床日期统计 · 与搞节奏共享记录","Grouped by wake-up date · Shared with Rhythm")).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(today.isEmpty ? "—" : sleepDuration(today.reduce(0) { $0+$1.durationSeconds },en:store.en)).font(.title2.monospacedDigit().weight(.semibold))
            Button(store.t("记录睡眠","Record sleep")) { store.sleepEditor = true }.tint(Theme.purple)
            if store.selectedTab != 10 { Button(store.t("查看记录","View records")) { store.selectedTab = 10 } }
        }.card()
    }
}

struct SleepRecordEditor: View {
    @EnvironmentObject var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var startedAt = Date().addingTimeInterval(-8*3600)
    @State private var endedAt = Date()
    private var valid: Bool { (1800...86400).contains(endedAt.timeIntervalSince(startedAt)) && endedAt <= Date() }
    var body: some View {
        VStack(alignment:.leading,spacing:20) {
            Label(store.t("记录睡眠","Record sleep"),systemImage:"moon.stars.fill").font(.title2.weight(.semibold)).foregroundStyle(Theme.purple)
            Text(store.t("填写已经结束的睡眠，两边只需记录一次。","Enter completed sleep once for both apps.")).foregroundStyle(.secondary)
            DatePicker(store.t("就寝时间","Bedtime"),selection:$startedAt,in:...Date(),displayedComponents:[.date,.hourAndMinute])
            DatePicker(store.t("起床时间","Wake-up time"),selection:$endedAt,in:...Date(),displayedComponents:[.date,.hourAndMinute])
            Text(valid ? sleepDuration(endedAt.timeIntervalSince(startedAt),en:store.en) : store.t("就寝须早于起床，时长 30 分钟至 24 小时。","Bedtime must precede waking by 30 minutes to 24 hours.")).font(.callout).foregroundStyle(valid ? Theme.purple : Theme.orange)
            Text(store.t("保存后自动同步。近期有效睡眠按每小时 3 点恢复岛屿活力，每日最多 24 点。","Automatically syncs on save. Recent eligible sleep restores 3 island energy per hour, up to 24 per day.")).font(.caption).foregroundStyle(.secondary)
            HStack { Spacer(); Button(store.t("取消","Cancel")) { dismiss() }.keyboardShortcut(.cancelAction); Button(store.t("保存并同步","Save and sync")) { _ = store.addSleep(start:startedAt,end:endedAt) }.buttonStyle(.borderedProminent).tint(Theme.purple).disabled(!valid).keyboardShortcut(.defaultAction) }
        }.padding(28).frame(width:480)
    }
}

private func sleepDuration(_ seconds: Double, en: Bool) -> String {
    let minutes = Int(max(0,seconds)/60)
    return en ? "\(minutes/60)h \(minutes%60)m" : "\(minutes/60) 小时 \(minutes%60) 分钟"
}
