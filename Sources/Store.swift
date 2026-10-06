import AppKit
import SwiftUI
import WidgetKit
import UniformTypeIdentifiers

@MainActor final class AppStore: ObservableObject {
    @Published var state = HealthState()
    @Published var message: String?
    @Published var fatalError: String?
    @Published var selectedTab = 0
    @Published var editor: HealthRecord?
    @Published var notice: String?
    @Published var undoRecord: HealthRecord?
    @Published var undoEvent: HealthEvent?
    @Published var undoEventWasCreation = false
    @Published var undoWasCreation = false
    private var db: HealthDatabase?
    /// app 级语言（gqns.language）变化时推动界面重渲染；en 直读解析器，不依赖本字段取值。
    @Published private var languageRevision = 0
    /// 语言统一读 app 级设置中心的 gqns.language；存档里的 preferences.english 保留为旧数据字段，不再驱动界面。
    var en: Bool { GQNSLanguage.isEnglish }
    func t(_ cn: String,_ en: String) -> String { self.en ? en : cn }
    init() {
        NotificationCenter.default.addObserver(forName: UserDefaults.didChangeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.languageRevision += 1 }
        }
        NotificationCenter.default.addObserver(forName: Notification.Name("GaoSeries.rhythm.sleepSaved"), object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.syncSleepRewards() }
        }
        DistributedNotificationCenter.default().addObserver(forName: Notification.Name("GaoSeries.rhythm.sleepSaved"), object:nil, queue:.main) { [weak self] _ in
            Task { @MainActor in self?.syncSleepRewards() }
        }
        reload()
    }
    func reload() {
        do {
            if db == nil { db = try HealthDatabase() }
            if let db { state = try db.read(); Engine.settle(&state,now:Date()) }
            fatalError = nil
            // 语言统一走 app 级 gqns.language：把解析结果回写存档字段，
            // 让 Engine 游戏文案与 Widget 扩展（独立进程，只读存档）与主界面保持一致。
            if state.preferences.english != GQNSLanguage.isEnglish {
                update { $0.preferences.english = GQNSLanguage.isEnglish }
            }
            syncSleepRewards()
        } catch { fatalError = error.localizedDescription }
    }
    @discardableResult func update(request: String? = nil,_ op: (inout HealthState) throws -> Void) -> Bool {
        guard let db else { message = fatalError; return false }
        do {
            state = try db.transaction(request:request,op)
            WidgetCenter.shared.reloadAllTimelines()
            do { try db.automaticBackup() } catch { notice = t("记录已保存，自动备份失败，可在设置中手动备份。","Saved; automatic backup failed. Use manual backup in Settings.") }
            return true
        } catch { message = error.localizedDescription; return false }
    }
    func welcome() { _ = update { Engine.visit(&$0,now:Date(),welcome:true) } }
    func new(_ kind: RecordKind) {
        var r = HealthRecord(kind:kind)
        switch kind {
        case .water: r.amount = state.preferences.cup
        case .meal: r.amount = 1; r.mealSource = .canteen; r.fullnessPercent = 75; let hour=Engine.calendar(state).component(.hour,from:Date()); r.slot = min(hour<11 ? 0 : hour<16 ? 1 : 2,state.preferences.config(Engine.day(Date(),state)).slots-1)
        case .exercise: r.amount=30; r.title=t("步行","Walking")
        case .weight: r.amount=state.records.filter { $0.kind == .weight }.max(by:{ $0.occurredAt<$1.occurredAt })?.amount ?? 60
        }
        editor = r
    }
    func addWater() {
        var r = HealthRecord(kind:.water); r.amount=state.preferences.cup
        save(r)
    }
    func save(_ record: HealthRecord,template: Bool = false) {
        let previous = state.records.first { $0.id==record.id }
        if update({ s in
            try Engine.save(&s,record:record,now:Date())
            if template { s.templates.append(.init(name:record.title.isEmpty ? record.kind.title(en) : record.title,record:record)) }
        }) {
            undoEvent=nil; undoRecord = previous ?? record; undoWasCreation = previous == nil
            notice = t("已保存，可撤销最近一次操作。","Saved. You can undo your last change.")
            editor = nil
        }
    }
    func remove(_ r: HealthRecord) {
        if update({ $0.records.removeAll { $0.id==r.id } }) { undoEvent=nil; undoRecord=r; undoWasCreation=false; notice=t("已删除记录，岛屿奖励不回退。","Record deleted; island rewards retained.") }
    }
    @discardableResult func saveEvent(_ event: HealthEvent) -> Bool {
        let previous=state.events.first { $0.id == event.id }
        if update({ try EventLog.save(&$0,event) }) {
            undoRecord=nil; undoEvent=previous ?? event; undoEventWasCreation=previous == nil
            notice=t("已记录，可以撤销。","Recorded. You can undo this change.")
            return true
        }
        return false
    }
    func logEvent(_ type: HealthEventType) { saveEvent(HealthEvent(typeID:type.id)) }
    func removeEvent(_ event: HealthEvent) {
        if update({ $0.events.removeAll { $0.id == event.id } }) { undoRecord=nil; undoEvent=event; undoEventWasCreation=false; notice=t("已删除事项记录，可撤销。","Entry deleted. Undo available.") }
    }
    func undo() {
        if let event=undoEvent {
            if update({ s in
                s.events.removeAll { $0.id == event.id }
                if !undoEventWasCreation { s.events.append(event) }
            }) { undoEvent=nil; notice=t("已撤销。","Undone.") }
            return
        }
        guard let r = undoRecord else { return }
        if update({ s in
            if undoWasCreation { s.records.removeAll { $0.id==r.id } }
            else { try Engine.save(&s,record:r,now:Date()) }
        }) { undoRecord=nil; notice=t("已撤销。","Undone.") }
    }
    func useTemplate(_ template: HealthTemplate) {
        var r = template.record; r.id=UUID(); r.occurredAt=Date(); r.createdAt=Date(); r.updatedAt=Date(); r.timezone=TimeZone.current.identifier
        if r.kind == .meal {
            // Keep legacy template data intact, but new meal entries use the current source/fullness model.
            r.amount = 1; r.calories = nil; r.protein = nil; r.carbs = nil; r.fat = nil
            r.baseCalories = nil; r.baseProtein = nil; r.baseCarbs = nil; r.baseFat = nil; r.usesNutrition = false
            if r.fullnessPercent == nil { r.fullnessPercent = 75 }
        }
        if update({ s in
            try Engine.save(&s,record:r,now:Date())
            if let i=s.templates.firstIndex(where:{$0.id==template.id}) { s.templates[i].uses+=1 }
        }) { undoEvent=nil; undoRecord=r; undoWasCreation=true; notice=t("已按模板记一笔。","Recorded from template.") }
    }
    func perform(_ id: String) { if update({ try Engine.act(&$0,id:id,now:Date()) }) { notice=t("劳作完成，物资已入库。","Done. Materials added to inventory.") } }
    func construct(_ id: String) { if update({ try Engine.build(&$0,id:id,now:Date()) }) { notice=t("新成果已经出现在岛上。","A new addition to your island.") } }
    func upgrade(_ id: String) { if update({ try Engine.upgrade(&$0,id:id,now:Date()) }) { notice=t("设施已升级，岛上的样貌和收益也变了。","Building upgraded, with a new look and stronger benefits.") } }
    func expandIsland() { if update({ try Engine.expand(&$0,now:Date()) }) { notice=t("海岸已扩建，岛屿更宽阔了。","Your island has a wider shore now.") } }
    func syncSleepRewards() {
        struct SleepFile: Decodable {
            struct Entry: Decodable { let id: String; let endedAt: Date; let durationSeconds: Double }
            let sleepRecords: [Entry]
        }
        let base = FileManager.default.urls(for:.applicationSupportDirectory,in:.userDomainMask).first!
        let main = base.appendingPathComponent("GaoSeries/Rhythm/library.json")
        let mirror = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier:"5G96498KGJ.com.gaojiezou.rhythm")?.appendingPathComponent("library.json")
        guard let data = (try? Data(contentsOf:main)) ?? mirror.flatMap({ try? Data(contentsOf:$0) }),
              let entries = try? JSONDecoder().decode(SleepFile.self,from:data).sleepRecords else { return }
        let now = Date()
        let rewards = entries.map { Engine.SleepReward(id:$0.id,endedAt:$0.endedAt,durationSeconds:$0.durationSeconds) }
        guard !Engine.eligibleSleep(state,records:rewards,now:now).isEmpty else { return }
        let before=state.ledgers[Engine.day(now,state),default:DailyLedger()].sleepEnergy
        if update({ Engine.rewardSleep(&$0,records:rewards,now:now) }) {
            let gained=state.ledgers[Engine.day(now,state),default:DailyLedger()].sleepEnergy-before
            NotificationCenter.default.post(name:Notification.Name("GaoSeries.health.sleepReward"),object:nil,userInfo:["energy":gained,"paused":state.island.paused])
            DistributedNotificationCenter.default().postNotificationName(Notification.Name("GaoSeries.health.sleepReward"),object:nil,userInfo:["energy":gained,"paused":state.island.paused],deliverImmediately:true)
        }
    }
    func preferences(_ op: (inout Preferences)->Void) {
        _ = update { s in Engine.settle(&s,now:Date()); op(&s.preferences); s.island.lastSettled=Date(); s.island.lastVisit=Date() }
    }
    func backup() {
        guard let db else { return }
        let panel=NSSavePanel(); panel.nameFieldStringValue="搞健康-\(Engine.day(Date(),state)).healthbackup"; panel.allowedContentTypes=[.data]
        if panel.runModal() == .OK, let url=panel.url {
            do { try db.backupData(try db.read()).write(to:url,options:.atomic); notice=t("完整备份已保存。","Full backup saved.") }
            catch { message=error.localizedDescription }
        }
    }
    func restore() {
        let panel=NSOpenPanel(); panel.canChooseDirectories=false; panel.allowsMultipleSelection=false
        guard panel.runModal() == .OK,let url=panel.url,let db else { return }
        do {
            let (saved,date)=try HealthDatabase.decodeBackup(Data(contentsOf:url))
            let alert=NSAlert(); alert.messageText=t("恢复完整备份？","Restore full backup?")
            alert.informativeText="\(date.formatted()) · \(saved.records.count) " + t("条记录。将替换当前全部记录与岛屿，恢复前自动保留当前备份。","records. Replaces all current records and island. Current data is backed up first.")
            alert.addButton(withTitle:t("恢复","Restore")); alert.addButton(withTitle:t("取消","Cancel"))
            guard alert.runModal() == .alertFirstButtonReturn else { return }
            try db.restore(saved); reload(); undoEvent=nil; undoRecord=nil; WidgetCenter.shared.reloadAllTimelines(); notice=t("备份已恢复。","Backup restored.")
        } catch { message=error.localizedDescription }
    }
    func exportCSV() {
        let panel=NSOpenPanel(); panel.canChooseDirectories=true; panel.canChooseFiles=false; panel.canCreateDirectories=true
        guard panel.runModal() == .OK,let url=panel.url else { return }
        do {
            let folder=url.appendingPathComponent("搞健康-CSV-\(UUID().uuidString.prefix(8))")
            try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
            for kind in RecordKind.allCases { try HealthCSV.export(kind,state.records).write(to:folder.appendingPathComponent("\(kind.rawValue).csv"),atomically:true,encoding:.utf8) }
            try EventLog.export(state).write(to:folder.appendingPathComponent("custom-events.csv"),atomically:true,encoding:.utf8)
            NSWorkspace.shared.open(folder); notice=t("健康记录与快速事项已导出。","Health records and quick events exported.")
        } catch { message=error.localizedDescription }
    }
    func importCSV() {
        let panel=NSOpenPanel(); panel.canChooseDirectories=true; panel.canChooseFiles=false
        guard panel.runModal() == .OK,let url=panel.url else { return }
        var added=0, skipped=0, found=false
        if update({ s in
            for kind in RecordKind.allCases {
                guard let text=try? String(contentsOf:url.appendingPathComponent("\(kind.rawValue).csv"),encoding:.utf8) else { continue }
                found=true
                for r in HealthCSV.import(kind,text) {
                    if s.records.contains(where:{$0.id==r.id}) { skipped+=1 } else { s.records.append(r); added+=1 }
                }
            }
            if let text=try? String(contentsOf:url.appendingPathComponent("custom-events.csv"),encoding:.utf8) {
                found=true
                for e in HealthCSV.importEvents(text,state:s) {
                    if s.events.contains(where:{$0.id==e.id}) { skipped+=1 } else { s.events.append(e); added+=1 }
                }
            }
            if !found { throw HealthError(t("没有找到可导入的 CSV 文件，请选择本应用导出的文件夹。","No importable CSV found. Choose a folder exported by this app.")) }
        }) {
            notice=t("已导入 \(added) 条，跳过 \(skipped) 条重复。导入的记录不补发岛屿奖励。","Imported \(added), skipped \(skipped) duplicates. Imports grant no island rewards.")
        }
    }
    func reset(all: Bool) {
        let alert=NSAlert(); alert.alertStyle = .warning
        alert.messageText=all ? t("删除全部本地数据？","Delete all local data?") : t("重新开始岛屿？","Reset your island?")
        alert.informativeText=all ? t("将删除健康记录、岛屿和自动备份。外部导出文件需自行处理。此操作不可撤销。","Deletes records, island and local backups. External exports remain. Cannot be undone.") : t("健康记录与模板保留。岛屿归零；今日已领取的奖励额度保留，旧记录不会重新发奖。","Keeps health records, templates and today's reward limits. Resets island progress.")
        alert.addButton(withTitle:t("取消","Cancel")); alert.addButton(withTitle:all ? t("删除全部","Delete all") : t("重置岛屿","Reset island"))
        guard alert.runModal() == .alertSecondButtonReturn else { return }
        if all {
            do { try db?.erase(); reload(); undoEvent=nil; undoRecord=nil; WidgetCenter.shared.reloadAllTimelines() } catch { message=error.localizedDescription }
        } else { _ = update { s in let rewarded = s.island.rewardedSleepIDs; s.island=Island(); s.island.rewardedSleepIDs=rewarded; for i in s.records.indices { s.records[i].rewardEligible=false } }; undoRecord=nil }
    }
    func openBackups() { if let db { NSWorkspace.shared.open(db.directory.appendingPathComponent("Backups")) } }
}
