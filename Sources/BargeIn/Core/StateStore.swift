import Foundation
import Observation
import BargeInCore
import SceneWater
import SceneActivity
import SceneSchedule
import SceneAlarm

/// 唯一状态源：所有读写都走这里，写入即落盘。
@MainActor
@Observable
final class StateStore {
    private(set) var state: AppState

    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let calendar: Calendar
    @ObservationIgnored private static let key = "AppState"

    init(defaults: UserDefaults? = nil, calendar: Calendar = .current) {
        self.defaults = defaults ?? StateStore.sharedDefaults
        self.calendar = calendar
        self.state = Self.load(from: self.defaults)
        refreshDay()
    }

    // MARK: - 场景

    func descriptor(_ scene: SceneID) -> SceneDescriptor { SceneRegistry.descriptor(scene) }

    func sceneTitle(_ scene: SceneID) -> String { descriptor(scene).title }

    func config(_ scene: SceneID) -> SceneConfig { state.config(scene) }

    func isSceneEnabled(_ scene: SceneID) -> Bool { config(scene).isEnabled }

    func setSceneEnabled(_ enabled: Bool, for scene: SceneID) {
        updateScene(scene) { $0.isEnabled = enabled }
    }

    func trigger(for scene: SceneID) -> SceneTrigger { config(scene).trigger }

    func setTrigger(_ trigger: SceneTrigger, for scene: SceneID) {
        updateScene(scene) { $0.trigger = trigger }
    }

    /// 前置只有一个真相：日程场景自己的 trigger。
    var leadMinutes: Int { trigger(for: .schedule).leadMinutes ?? 5 }

    func setLeadMinutes(_ minutes: Int) {
        setTrigger(.events(leadMinutes: max(1, min(60, minutes))), for: .schedule)
    }

    private func updateScene(_ scene: SceneID, _ mutate: (inout SceneConfig) -> Void) {
        update { state in
            var config = state.config(scene)
            mutate(&config)
            state.setConfig(config, for: scene)
        }
    }

    // MARK: - 预设实例

    func activeInstance(for scene: SceneID) -> PresetInstance {
        let config = config(scene)
        return config.instances.first { $0.id == config.activeInstanceID } ?? config.instances[0]
    }

    /// 只改激活项，不动卡片顺序：点一张卡不该让它在网格里跳位。
    func activate(_ id: UUID, in scene: SceneID) {
        guard config(scene).instances.contains(where: { $0.id == id }) else { return }
        updateScene(scene) { $0.activeInstanceID = id }
    }

    /// 复制一张同场景的实例卡片：深拷贝配置，但不自动切换当前提醒。
    @discardableResult
    func duplicate(_ id: UUID, in scene: SceneID) -> UUID? {
        let config = config(scene)
        guard let source = config.instances.first(where: { $0.id == id }) else { return nil }
        let copy = PresetInstance(
            preset: source.preset,
            name: uniqueName(from: source.name, in: scene),
            intensity: source.intensity,
            copyOverrides: source.copyOverrides
        )
        updateScene(scene) { $0.instances.append(copy) }
        return copy.id
    }

    /// 内置两张不可删；删掉正在用的副本时回落到「大字墙 · 标准」。
    func delete(_ id: UUID, in scene: SceneID) {
        guard let target = config(scene).instances.first(where: { $0.id == id }), !target.builtIn else { return }
        updateScene(scene) { config in
            config.instances.removeAll { $0.id == id }
            guard config.activeInstanceID == id else { return }
            guard let index = config.instances.firstIndex(where: { $0.preset == Catalog.defaultActive }) else {
                config.activeInstanceID = config.instances[0].id
                return
            }
            config.instances[index].intensity = .standard
            config.activeInstanceID = config.instances[index].id
        }
    }

    func rename(_ id: UUID, in scene: SceneID, to name: String) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        updateScene(scene) { config in
            guard let index = config.instances.firstIndex(where: { $0.id == id }) else { return }
            config.instances[index].name = trimmed
        }
    }

    func setIntensity(_ id: UUID, in scene: SceneID, _ intensity: Intensity?) {
        guard let instance = config(scene).instances.first(where: { $0.id == id }) else { return }
        let allowed = Catalog.theme(for: instance.preset).intensities
        guard intensity.map({ allowed.contains($0) }) ?? allowed.isEmpty else { return }
        updateScene(scene) { config in
            guard let index = config.instances.firstIndex(where: { $0.id == id }) else { return }
            config.instances[index].intensity = intensity
        }
    }

    // MARK: - 文案

    /// 场景自己的变量值；活动没有变量。
    func copyValues(for scene: SceneID) -> [String: String] {
        switch scene {
        case .water: return state.water.copyValues
        case .activity: return state.activity.copyValues
        case .schedule: return [:]
        case .alarm: return [:]
        }
    }

    /// 日程的变量取决于当前这一条提醒是哪个事件，所以按队列键取。
    func copyValues(for key: ReminderKey) -> [String: String] {
        switch key.scene {
        case .water: return state.water.copyValues
        case .activity: return state.activity.copyValues
        case .schedule:
            guard let eventKey = key.event, let event = event(for: eventKey) else { return [:] }
            return ScheduleValues.values(for: event, now: Date(), calendar: calendar)
        case .alarm:
            guard let eventKey = key.event,
                  let id = UUID(uuidString: eventKey.uid),
                  let alarm = alarm(id)
            else { return [:] }
            return [
                "title": alarm.displayTitle,
                "start": AlarmPolicy.timeText(eventKey.start, calendar: calendar),
            ]
        }
    }

    func hasOverride(_ id: UUID, in scene: SceneID, slot: CopySlot) -> Bool {
        overrideText(id, in: scene, slot: slot) != nil
    }

    func overrideText(_ id: UUID, in scene: SceneID, slot: CopySlot) -> String? {
        guard let instance = config(scene).instances.first(where: { $0.id == id }),
              let value = instance.copyOverrides[slot.rawValue], !value.isEmpty
        else { return nil }
        return value
    }

    /// 编辑器里显示的模板本身：改过的显示改动，没改的显示场景默认文案。
    func template(_ id: UUID, in scene: SceneID, slot: CopySlot) -> String {
        guard let instance = config(scene).instances.first(where: { $0.id == id }) else {
            return CopyText.defaultText(slot, scene: descriptor(scene))
        }
        return CopyText.template(slot, instance: instance, scene: descriptor(scene))
    }

    /// 写空等于撤销这次覆盖。
    func setCopy(_ id: UUID, in scene: SceneID, slot: CopySlot, to text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        updateScene(scene) { config in
            guard let index = config.instances.firstIndex(where: { $0.id == id }) else { return }
            if trimmed.isEmpty {
                config.instances[index].copyOverrides.removeValue(forKey: slot.rawValue)
            } else {
                config.instances[index].copyOverrides[slot.rawValue] = trimmed
            }
        }
    }

    func resetCopy(_ id: UUID, in scene: SceneID) {
        updateScene(scene) { config in
            guard let index = config.instances.firstIndex(where: { $0.id == id }) else { return }
            config.instances[index].copyOverrides = [:]
        }
    }

    /// 模板里出现了当前场景不提供的变量：整段会回落成默认文案，界面要提示。
    func hasUnknownVariables(_ id: UUID, in scene: SceneID) -> Bool {
        guard let instance = config(scene).instances.first(where: { $0.id == id }) else { return false }
        let sceneDescriptor = descriptor(scene)
        return Catalog.theme(for: instance.preset).slots.contains { slot in
            CopyText.hasUnknownVariables(
                CopyText.template(slot, instance: instance, scene: sceneDescriptor),
                scene: sceneDescriptor
            )
        }
    }

    // MARK: - 喝水、活动与账本

    var progress: Double { state.water.progress }

    var activityDoneToday: Int { state.activity.doneToday }

    func isCompleted(_ scene: SceneID) -> Bool {
        scene == .water && state.water.isCompleted
    }

    /// 按设置里的单杯量记一杯。
    func drink() {
        let added = state.water.cupML
        guard added > 0 else { return }
        update { state in
            state.water.consumedML += added
            state.lastActiveDate = Date()
        }
    }

    /// 清空今日喝水进度：只归零毫升数，账本与免打扰都不动。
    func clearWaterProgress() {
        update { state in
            state.water.consumedML = 0
            state.lastActiveDate = Date()
        }
    }

    func completeActivity() {
        update { state in
            state.activity.doneToday += 1
            state.lastActiveDate = Date()
        }
    }

    /// 中断与推迟都记一次跳过；只记录，不改变下一次提醒。
    func recordSkip(_ scene: SceneID) {
        update { state in
            var config = state.config(scene)
            config.skipsToday += 1
            state.setConfig(config, for: scene)
            state.lastActiveDate = Date()
        }
    }

    /// 跨日重置：懒执行，在启动、每次读取与每次触发前调用。
    func refreshDay(now: Date = Date()) {
        guard !calendar.isDate(state.lastActiveDate, inSameDayAs: now) else { return }
        update { state in
            state.water.consumedML = 0
            state.activity.doneToday = 0
            state.waterConfig.skipsToday = 0
            state.activityConfig.skipsToday = 0
            state.scheduleConfig.skipsToday = 0
            state.alarmConfig.skipsToday = 0
            // 已经提醒过的事件只需要记住两天：窗口本身就是一个来回。
            let cutoff = now.addingTimeInterval(-2 * 86_400)
            state.schedule.handled = state.schedule.handled.filter { $0.value >= cutoff }
            state.alarm.handled = state.alarm.handled.filter { $0.value >= cutoff }
            // 一次性闹钟过了那一天就作废，不管响没响过。
            let today = calendar.startOfDay(for: now)
            state.alarm.alarms.removeAll { alarm in
                guard let day = alarm.onceDay else { return false }
                return day < today
            }
            state.lastActiveDate = now
        }
    }

    // MARK: - 日程

    /// 订阅解析出来的事件；不落盘，启动时从缓存文件重新解析。
    private(set) var events: [EventOccurrence] = []
    /// 推迟过的事件：进程内，不落盘。
    private var snoozes: [EventKey: Date] = [:]

    var subscriptions: [Subscription] { state.schedule.subscriptions }

    var hasEnabledSubscription: Bool { state.schedule.hasEnabledSubscription }

    private var enabledSubscriptionIDs: Set<UUID> {
        Set(state.schedule.subscriptions.filter(\.isEnabled).map(\.id))
    }

    var scheduleEvents: [EventOccurrence] {
        let ids = enabledSubscriptionIDs
        return events.filter { ids.contains($0.subscriptionID) }
    }

    var handledEventKeys: Set<EventKey> {
        Set(state.schedule.handled.keys.compactMap(EventKey.init(storageKey:)))
    }

    func event(for key: EventKey) -> EventOccurrence? {
        events.first { $0.key == key }
    }

    /// 一条事件到点的时刻：开始减前置；推迟过的取更晚的那个。
    func fireTime(for event: EventOccurrence) -> Date {
        let base = event.start.addingTimeInterval(-Double(leadMinutes) * 60)
        if let snoozed = snoozes[event.key], snoozed > base { return snoozed }
        return base
    }

    func setEvents(_ newEvents: [EventOccurrence]) {
        events = newEvents
        let keys = Set(newEvents.map(\.key))
        snoozes = snoozes.filter { keys.contains($0.key) }
    }

    func upsert(_ subscription: Subscription) {
        update { state in
            if let index = state.schedule.subscriptions.firstIndex(where: { $0.id == subscription.id }) {
                state.schedule.subscriptions[index] = subscription
            } else if !state.schedule.subscriptions.contains(where: { $0.dedupeKey == subscription.dedupeKey }) {
                state.schedule.subscriptions.append(subscription)
            }
        }
    }

    func removeSubscription(_ id: UUID) {
        update { state in
            state.schedule.subscriptions.removeAll { $0.id == id }
        }
        events.removeAll { $0.subscriptionID == id }
        let remaining = Set(events.map(\.key))
        snoozes = snoozes.filter { remaining.contains($0.key) }
    }

    func setSubscriptionEnabled(_ enabled: Bool, for id: UUID) {
        update { state in
            guard let index = state.schedule.subscriptions.firstIndex(where: { $0.id == id }) else { return }
            state.schedule.subscriptions[index].isEnabled = enabled
        }
    }

    func markSynced(_ id: UUID, at date: Date = Date()) {
        update { state in
            guard let index = state.schedule.subscriptions.firstIndex(where: { $0.id == id }) else { return }
            state.schedule.subscriptions[index].lastFetchedAt = date
            state.schedule.subscriptions[index].lastError = nil
        }
    }

    func setFeedError(_ error: FeedError?, for id: UUID) {
        update { state in
            guard let index = state.schedule.subscriptions.firstIndex(where: { $0.id == id }) else { return }
            state.schedule.subscriptions[index].lastError = error
        }
    }

    /// 日程提醒结束：完成与中断都算"处理过"，重启不重弹。
    func markHandled(_ key: EventKey, at now: Date = Date()) {
        update { state in
            state.schedule.handled[key.storageKey] = now
        }
        snoozes[key] = nil
    }

    func snooze(_ key: EventKey, minutes: Int) {
        snoozes[key] = Date().addingTimeInterval(TimeInterval(minutes * 60))
    }

    /// 已经到点、尚未呈现的事件；已经开始超过 10 分钟的、没有推迟过的不补。
    func dueEvents(for scene: SceneID, at now: Date) -> [EventOccurrence] {
        guard scene == .schedule, isSceneEnabled(.schedule) else { return [] }
        if let paused = state.pausedUntil, paused > now { return [] }
        let handled = handledEventKeys
        let catchUp = now.addingTimeInterval(-FirePlan.catchUpWindow)
        return scheduleEvents.filter { event in
            guard !handled.contains(event.key) else { return false }
            guard snoozes[event.key] != nil || event.start > catchUp else { return false }
            return fireTime(for: event) <= now
        }.sorted { $0.start < $1.start }
    }

    /// 设置里「今日 N 场」用：某条订阅在某一天的事件，按开始时间排。
    /// 不看启用开关——停用的订阅也允许查看今天有什么。
    func events(for subscriptionID: UUID, on day: Date = Date()) -> [EventOccurrence] {
        events
            .filter { $0.subscriptionID == subscriptionID && calendar.isDate($0.start, inSameDayAs: day) }
            .sorted { $0.start < $1.start }
    }

    /// popover 上显示的那一场：还没开始、也还没提醒过的最近一条。
    func nextEvent(after now: Date = Date()) -> EventOccurrence? {
        let handled = handledEventKeys
        let catchUp = now.addingTimeInterval(-FirePlan.catchUpWindow)
        return scheduleEvents
            .filter { !handled.contains($0.key) && (snoozes[$0.key] != nil || $0.start > catchUp) }
            .min { $0.start < $1.start }
    }

    func completeSchedule(_ key: EventKey, at now: Date = Date()) {
        markHandled(key, at: now)
        update { $0.lastActiveDate = now }
    }

    // MARK: - 闹钟

    var alarms: [Alarm] { state.alarm.alarms }

    func alarm(_ id: UUID) -> Alarm? {
        state.alarm.alarms.first { $0.id == id }
    }

    @discardableResult
    func addAlarm(_ alarm: Alarm) -> UUID {
        update { $0.alarm.alarms.append(alarm) }
        return alarm.id
    }

    func updateAlarm(_ id: UUID, _ mutate: (inout Alarm) -> Void) {
        update { state in
            guard let index = state.alarm.alarms.firstIndex(where: { $0.id == id }) else { return }
            mutate(&state.alarm.alarms[index])
        }
    }

    func deleteAlarm(_ id: UUID) {
        update { $0.alarm.alarms.removeAll { $0.id == id } }
    }

    func setAlarmEnabled(_ enabled: Bool, for id: UUID) {
        updateAlarm(id) { $0.isEnabled = enabled }
    }

    /// 无效是派生的：同一份闹钟随通用时间变化随时重判，不落盘。
    func alarmIssue(_ alarm: Alarm) -> AlarmIssue? {
        AlarmPolicy.issue(
            for: alarm,
            workStart: state.workStart,
            workEnd: state.workEnd,
            restDays: state.restDays,
            calendar: calendar
        )
    }

    /// 推迟时刻只活在进程内，和日程那份分开存：日历刷新不该清掉闹钟的推迟。
    private var alarmSnoozes: [EventKey: Date] = [:]

    var alarmHandledKeys: Set<EventKey> {
        Set(state.alarm.handled.keys.compactMap(EventKey.init(storageKey:)))
    }

    /// 闹钟的候选时刻：只留启用且通过通用时间的条目。每天铺 8 天，一次性只铺那一天。
    func alarmMoments(after now: Date = Date()) -> [ScheduledMoment] {
        let firstDay = calendar.startOfDay(for: now)
        let handled = alarmHandledKeys
        var result: [ScheduledMoment] = []
        for alarm in state.alarm.alarms where alarm.isEnabled && alarmIssue(alarm) == nil {
            switch alarm.recurrence {
            case .daily:
                for offset in 0..<FirePlan.maxLookaheadDays {
                    guard let day = calendar.date(byAdding: .day, value: offset, to: firstDay) else { continue }
                    // 每天 = 每个非休息日：休息日由通用设置决定，闹钟不另有一套星期。
                    if state.restDays.contains(calendar.component(.weekday, from: day)) { continue }
                    let at = alarm.time.date(on: day, calendar: calendar)
                    guard !handled.contains(EventKey(uid: alarm.id.uuidString, start: at)) else { continue }
                    result.append(ScheduledMoment(id: alarm.id.uuidString, at: at, isOneShot: false))
                }
            case .once(let day):
                let at = alarm.time.date(on: day, calendar: calendar)
                guard !handled.contains(EventKey(uid: alarm.id.uuidString, start: at)) else { continue }
                result.append(ScheduledMoment(id: alarm.id.uuidString, at: at, isOneShot: true))
            }
        }
        return result
    }

    /// 到点、尚未呈现的闹钟。重复的错过就等下一次；一次性的有一个补发窗口，
    /// 窗口被当天工作时段结束封顶——下班之后不该再弹一条工作提醒。
    func dueAlarms(at now: Date = Date()) -> [(key: ReminderKey, at: Date)] {
        guard isSceneEnabled(.alarm) else { return [] }
        if let paused = state.pausedUntil, paused > now { return [] }
        return alarmMoments(after: now).compactMap { moment in
            let key = EventKey(uid: moment.id, start: moment.at)
            let fire = max(moment.at, alarmSnoozes[key] ?? .distantPast)
            guard fire <= now else { return nil }
            var window: TimeInterval = FirePlan.catchUpWindow
            if moment.isOneShot {
                let dayEnd = state.workEnd.date(on: moment.at, calendar: calendar)
                window = max(60, min(60 * 60, dayEnd.timeIntervalSince(fire)))
            }
            guard now.timeIntervalSince(fire) <= window else { return nil }
            return (ReminderKey(scene: .alarm, event: key), fire)
        }
    }

    func markAlarmHandled(_ key: EventKey, at now: Date = Date()) {
        update { $0.alarm.handled[key.storageKey] = now }
        alarmSnoozes[key] = nil
    }

    /// popover 用：今天还会响的闹钟（启用、有效、落在今天）。
    func alarmsScheduledToday(at now: Date = Date()) -> [Alarm] {
        state.alarm.alarms
            .filter { alarm in
                guard alarm.isEnabled, alarmIssue(alarm) == nil else { return false }
                switch alarm.recurrence {
                case .daily:
                    return !state.restDays.contains(calendar.component(.weekday, from: now))
                case .once(let day):
                    return calendar.isDate(day, inSameDayAs: now)
                }
            }
            .sorted { $0.time < $1.time }
    }

    /// 下一条还会响的闹钟（启用时才有意义）。
    func nextAlarm(after now: Date = Date()) -> (alarm: Alarm, at: Date)? {
        guard isSceneEnabled(.alarm),
              let moment = alarmMoments(after: now).filter({ $0.at > now }).min(by: { $0.at < $1.at }),
              let id = UUID(uuidString: moment.id),
              let alarm = alarm(id)
        else { return nil }
        return (alarm, moment.at)
    }

    func snoozeAlarm(_ key: EventKey, minutes: Int, at now: Date = Date()) {
        alarmSnoozes[key] = now.addingTimeInterval(TimeInterval(minutes * 60))
    }

    /// 一条闹钟结束：记处理；一次性的随后从列表消失。
    func finishAlarm(_ key: EventKey, at now: Date = Date()) {
        markAlarmHandled(key, at: now)
        if let id = UUID(uuidString: key.uid), alarm(id)?.onceDay != nil {
            deleteAlarm(id)
        }
        update { $0.lastActiveDate = now }
    }

    // MARK: - 调度

    /// 下一次该提醒的时刻。
    func nextFireDate(for scene: SceneID, after now: Date = Date()) -> Date? {
        FirePlan.next(after: now, runtime: runtime(for: scene), calendar: calendar)
    }

    func runtime(for scene: SceneID) -> SceneRuntime {
        let config = config(scene)
        let isSchedule = scene == .schedule
        let isAlarm = scene == .alarm
        return SceneRuntime(
            isEnabled: config.isEnabled,
            trigger: config.trigger,
            workStart: state.workStart,
            workEnd: state.workEnd,
            restDays: state.restDays,
            pausedUntil: state.pausedUntil,
            isCompletedToday: isCompleted(scene),
            events: isSchedule ? scheduleEvents : [],
            handled: isSchedule ? handledEventKeys : [],
            snoozedUntil: isSchedule ? snoozes : [:],
            moments: isAlarm ? alarmMoments() : [],
            handledMoments: isAlarm ? alarmHandledKeys : [],
            snoozedMoments: isAlarm ? alarmSnoozes : [:]
        )
    }

    /// 唤醒后的“补一次”只在同一天、工作时段内、未暂停时成立。
    func isWithinActiveWindow(at date: Date) -> Bool {
        let weekday = calendar.component(.weekday, from: date)
        guard !state.restDays.contains(weekday) else { return false }
        if let paused = state.pausedUntil, paused > date { return false }
        let components = calendar.dateComponents([.hour, .minute], from: date)
        let time = TimeOfDay(hour: components.hour ?? 0, minute: components.minute ?? 0)
        return time >= state.workStart && time < state.workEnd
    }

    func isSameDay(_ lhs: Date, _ rhs: Date) -> Bool {
        calendar.isDate(lhs, inSameDayAs: rhs)
    }

    /// 首次启动的一个选择同时落到两个场景：找到同款内置卡设为激活。
    func applyPresetToAllScenes(_ preset: Preset) {
        update { state in
            for scene in SceneID.allCases {
                var config = state.config(scene)
                let instance = config.instances.first { $0.preset == preset && $0.builtIn }
                    ?? config.instances.first { $0.preset == preset }
                if let instance { config.activeInstanceID = instance.id }
                state.setConfig(config, for: scene)
            }
        }
    }

    /// 供设置界面按 keyPath 写入全局字段。
    func set<T>(_ keyPath: WritableKeyPath<AppState, T>, _ value: T) {
        update { $0[keyPath: keyPath] = value }
    }

    // MARK: - 内部

    private func uniqueName(from name: String, in scene: SceneID) -> String {
        var stem = name
        if let range = stem.range(of: " 副本", options: .backwards) {
            stem = String(stem[stem.startIndex..<range.lowerBound])
        }
        let existing = Set(config(scene).instances.map(\.name))
        var candidate = "\(stem) 副本"
        var index = 2
        while existing.contains(candidate) {
            candidate = "\(stem) 副本 \(index)"
            index += 1
        }
        return candidate
    }

    private func update(_ mutate: (inout AppState) -> Void) {
        mutate(&state)
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(state) else { return }
        defaults.set(data, forKey: Self.key)
    }

    /// 存档落在哪个域。`swift run` 跑的是裸二进制，没有 bundle id 会落到以进程名命名的另一个域，
    /// 让人误以为"重新打包安装之后数据丢了"；无 bundle 时统一回打包版的域。
    /// ponytail: 域名字面量与 `Info.plist` 的 `CFBundleIdentifier` 重复，改 bundle id 时两处一起改。
    @ObservationIgnored static let sharedDomainName = Bundle.main.bundleIdentifier ?? "com.bargein.app"

    @ObservationIgnored static let sharedDefaults: UserDefaults =
        Bundle.main.bundleIdentifier == nil
            ? (UserDefaults(suiteName: sharedDomainName) ?? .standard)
            : .standard

    /// 坏档留档目录：`Application Support/BargeIn/`，与订阅缓存同一个根。
    @ObservationIgnored static var backupDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("BargeIn", isDirectory: true)
    }

    private static func load(from defaults: UserDefaults) -> AppState {
        guard let data = defaults.data(forKey: key) else { return AppState() }
        do {
            return try JSONDecoder().decode(AppState.self, from: data)
        } catch {
            // 连逐字段容错都救不回来：先把这一份原样留档，再用出厂值启动。
            // 静默丢档是上一次丢数据的直接原因，这里绝不重犯。
            backUp(data)
            NSLog("[BargeIn] AppState 解码失败，旧档已另存到 %@：%@", backupDirectory.path, "\(error)")
            return AppState()
        }
    }

    private static func backUp(_ data: Data) {
        try? FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let file = backupDirectory.appendingPathComponent("state-unreadable-\(stamp).json")
        try? data.write(to: file)
    }
}
