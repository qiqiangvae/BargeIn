import SwiftUI
import BargeInCore
import SceneSchedule
import SceneAlarm

@MainActor
@Observable
final class LaunchAtLoginModel {
    var isEnabled: Bool

    init() {
        isEnabled = LaunchAtLogin.isEnabled
    }

    func set(_ enabled: Bool) {
        LaunchAtLogin.set(enabled)
        isEnabled = LaunchAtLogin.isEnabled
    }
}

/// 设置窗口的 tab 与编辑态。本机只有 CLT，@State 宏不可用，所以用 @Observable。
@MainActor
@Observable
final class SettingsModel {
    enum Page {
        /// 场景 tab；是喝水、活动还是日程由 selectedScene 决定。
        case scene
        /// 时间、开机自启这类跨场景与 App 级设置。
        case app
    }

    let onboarding: Bool
    var page: Page
    var selectedScene: SceneID
    var editingID: UUID?

    /// 改名草稿：写透到 store，同时保留输入中的原文，
    /// 免得清空重打时字段被旧名字弹回去。
    var renameDraft = ""

    // 添加订阅的表单状态。连接与保存都会打网络，所以状态留在模型里，
    // 视图重绘不打断一次进行中的连接。
    enum SubscriptionMode: Int {
        case caldav = 0
        case ics = 1
    }

    var addingSubscription = false
    var subscriptionMode: SubscriptionMode = .caldav
    var serverDraft = "https://calendar.dingtalk.com"
    var usernameDraft = ""
    var passwordDraft = ""
    var urlDraft = ""
    var isConnecting = false
    var connectError: String?
    var discovered: [CalendarRef] = []
    var selectedCalendars: Set<String> = []
    /// 当前展开「今日列表」的订阅；同时只展开一条。
    var expandedSubscriptionID: UUID?
    /// 哪个删除入口在等第二下确认。同一时刻只有一个，切页、切场景或点别的入口即复位。
    var confirmingDelete: String?

    /// 正在内联编辑的闹钟（同时只展开一条）与它的内容草稿。
    var editingAlarmID: UUID?
    var alarmTitleDraft = ""

    func resetSubscriptionDraft() {
        addingSubscription = false
        isConnecting = false
        connectError = nil
        discovered = []
        selectedCalendars = []
        usernameDraft = ""
        passwordDraft = ""
        urlDraft = ""
        serverDraft = "https://calendar.dingtalk.com"
    }

    @ObservationIgnored private let store: StateStore

    init(
        store: StateStore,
        onboarding: Bool,
        page: Page = .scene,
        selectedScene: SceneID = .water
    ) {
        self.store = store
        self.onboarding = onboarding
        self.page = page
        self.selectedScene = selectedScene
    }

    /// 顶部四段：喝水 | 活动 | 日程 | 通用。通用不是场景，所以排在场景后面。
    var tabIndex: Int {
        switch page {
        case .app: SceneID.allCases.count
        case .scene: Self.sceneIndex(of: selectedScene)
        }
    }

    func selectTab(_ index: Int) {
        if index < SceneID.allCases.count {
            selectScene(SceneID.allCases[index])
        } else {
            leaveScene(.app)
        }
    }

    /// 切场景时收起编辑面板：编辑面板只属于一个场景。
    func selectScene(_ scene: SceneID) {
        page = .scene
        guard scene != selectedScene else { return }
        selectedScene = scene
        editingID = nil
        editingAlarmID = nil
        confirmingDelete = nil
    }

    /// 离开场景 tab 同样收起编辑面板。
    private func leaveScene(_ page: Page) {
        self.page = page
        editingID = nil
        editingAlarmID = nil
        confirmingDelete = nil
    }

    func beginEditAlarm(_ alarm: Alarm) {
        editingAlarmID = editingAlarmID == alarm.id ? nil : alarm.id
        alarmTitleDraft = editingAlarmID == nil ? "" : alarm.title
    }

    static func sceneIndex(of scene: SceneID) -> Int {
        SceneID.allCases.firstIndex(of: scene) ?? 0
    }

    func beginRename(_ instance: PresetInstance) {
        renameDraft = instance.name
    }

    func rename(_ instance: PresetInstance, to text: String) {
        renameDraft = text
        store.rename(instance.id, in: selectedScene, to: text)
    }

    /// Esc 逐级退的下一步。
    enum Escape {
        case closeEditor
        case closeWindow
    }

    var escape: Escape {
        (editingID != nil || editingAlarmID != nil) ? .closeEditor : .closeWindow
    }
}

struct SettingsView: View {
    let store: StateStore
    let engine: ReminderEngine
    let feeds: FeedService
    let model: SettingsModel
    let onPreview: (SceneID, PresetInstance) -> Void
    let onFinishOnboarding: () -> Void

    private let login = LaunchAtLoginModel()

    private static let windowWidth: CGFloat = 640

    private static let weekdayOrder = [2, 3, 4, 5, 6, 7, 1]
    private static let weekdayNames: [Int: String] = [
        2: "一", 3: "二", 4: "三", 5: "四", 6: "五", 7: "六", 1: "日",
    ]

    var body: some View {
        Group {
            if model.onboarding {
                onboardingPage
            } else {
                VStack(spacing: 0) {
                    tabBar
                    ScrollViewReader { proxy in
                        ScrollView {
                            pageContent
                        }
                        .onChange(of: model.editingID) { _, id in
                            guard let id else { return }
                            // 编辑面板在这一轮更新里才插进布局，等它落位后再滚。
                            DispatchQueue.main.async {
                                withAnimation(.easeOut(duration: 0.25)) {
                                    proxy.scrollTo(id, anchor: .bottom)
                                }
                            }
                        }
                    }
                    footer
                }
            }
        }
        .frame(width: Self.windowWidth)
        .frame(maxHeight: .infinity)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    // MARK: - 页面

    @ViewBuilder
    private var pageContent: some View {
        VStack(alignment: .leading, spacing: 14) {
            if model.onboarding {
                onboardingHeader
                presetsCard(showsActions: false)
                Text("点「就用这个」会先给你看一次提醒长什么样。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                switch model.page {
                case .scene:
                    sceneBar
                    presetsCard(showsActions: true)
                    if model.selectedScene == .schedule {
                        ScheduleSettingsSection(
                            store: store,
                            model: model,
                            feeds: feeds
                        ) {
                            engine.feedsChanged()
                        }
                        Text("日程不受工作时段与休息日约束；免打扰仍然生效")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 2)
                    } else if model.selectedScene == .alarm {
                        AlarmSettingsSection(store: store, model: model) {
                            engine.reschedule()
                        }
                        Text("闹钟受工作时段与休息日约束；免打扰仍然生效")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.top, 2)
                    } else {
                        rhythmCard
                        if model.selectedScene == .water {
                            waterCard
                        }
                    }
                case .app:
                    timeCard
                    generalCard
                    privacyLine
                }
            }
        }
        .padding(20)
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            SegmentedControl(
                labels: SceneID.allCases.map { store.sceneTitle($0) } + ["通用"],
                selected: model.tabIndex
            ) { index in
                model.selectTab(index)
            }
            .frame(width: 400)
            Spacer(minLength: 0)
        }
        .padding(.top, 14)
        .padding(.bottom, 8)
    }

    private var privacyLine: some View {
        Text("零权限 · 数据只保存在本机；日程订阅是唯一联网功能，只读")
            .font(.system(size: 10.5))
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity)
            .padding(.top, 2)
    }

    // MARK: - 当前场景

    private var currentConfig: SceneConfig { store.config(model.selectedScene) }

    /// 场景条只留一句说明和开关：场景名已经在 tab 上出现过一次。
    private var sceneBar: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(store.descriptor(model.selectedScene).summary)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Toggle(isOn: sceneEnabledBinding) {
                Text("启用")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .toggleStyle(.switch)
            .controlSize(.small)
            .padding(.leading, 4)
        }
        .padding(.horizontal, 2)
        .padding(.top, 2)
    }

    private var sceneEnabledBinding: Binding<Bool> {
        Binding(
            get: { store.isSceneEnabled(model.selectedScene) },
            set: {
                store.setSceneEnabled($0, for: model.selectedScene)
                engine.reschedule()
            }
        )
    }

    // MARK: - 提醒预设

    private var onboardingHeader: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("选一种提醒方式")
                .font(.system(size: 20, weight: .semibold))
            Text("四个场景都先用它，之后可以在设置里各自换掉。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
        }
        .padding(.bottom, 2)
    }

    private func presetsCard(showsActions: Bool) -> some View {
        let scene = model.selectedScene
        return SettingsCard(title: "提醒预设") {
            VStack(alignment: .leading, spacing: 12) {
                PresetGrid(
                    store: store,
                    model: model,
                    scene: scene,
                    instances: store.config(scene).instances,
                    showsActions: showsActions,
                    editingID: showsActions ? model.editingID : nil,
                    onSelect: select,
                    onEdit: toggleEditor,
                    onPreview: { onPreview(scene, $0) },
                    onCopy: copy,
                    onDelete: delete,
                    editor: { PresetEditor(store: store, model: model, scene: scene, instance: $0) }
                )
            }
        }
    }

    // MARK: - 预设动作

    private func select(_ instance: PresetInstance) {
        model.confirmingDelete = nil
        model.editingID = nil
        store.activate(instance.id, in: model.selectedScene)
        engine.reschedule()
    }

    private func toggleEditor(_ instance: PresetInstance) {
        model.confirmingDelete = nil
        guard model.editingID != instance.id else {
            model.editingID = nil
            return
        }
        model.editingID = instance.id
        model.beginRename(instance)
    }

    private func copy(_ instance: PresetInstance) {
        model.confirmingDelete = nil
        store.duplicate(instance.id, in: model.selectedScene)
        model.editingID = nil
    }

    private func delete(_ instance: PresetInstance) {
        model.confirmingDelete = nil
        store.delete(instance.id, in: model.selectedScene)
        if model.editingID == instance.id {
            model.editingID = nil
        }
        engine.reschedule()
    }

    private func finishOnboarding() {
        // 首启的一个选择同时落到三个场景，之后各场景可独立改。
        let preset = store.activeInstance(for: .water).preset
        store.applyPresetToAllScenes(preset)
        store.set(\.hasOnboarded, true)
        onFinishOnboarding()
    }

    private var onboardingPage: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            pageContent
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button(action: finishOnboarding) {
                    Text("就用这个")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 150, height: 40)
                        .background(
                            Theme.accent,
                            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
                        )
                }
                .buttonStyle(PressableStyle())
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 20)
        }
    }

    // MARK: - 喝水

    private var waterCard: some View {
        SettingsCard(title: "喝水") {
            SettingsRow(title: "日目标") {
                AmountStepper(value: store.state.water.targetML, range: 500...5000, step: 250, unit: "ml") {
                    store.set(\.water.targetML, $0)
                    engine.reschedule()
                }
            }
            SettingsRow(title: "单杯量") {
                AmountStepper(value: store.state.water.cupML, range: 50...1000, step: 50, unit: "ml") {
                    store.set(\.water.cupML, $0)
                    engine.reschedule()
                }
            }
            Text("达标后当天不再提醒，次日 0 点自动重置。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 节奏

    private var rhythmCard: some View {
        SettingsCard(title: "节奏") {
            SegmentedControl(labels: ["固定间隔", "指定时刻"], selected: isFixedTimes ? 1 : 0) { index in
                if index == 1 {
                    setSchedule(.timesOfDay(fixedTimes.isEmpty ? [TimeOfDay(hour: 10, minute: 0)] : fixedTimes))
                } else {
                    setSchedule(.interval(minutes: 60))
                }
            }

            if isFixedTimes {
                if !fixedTimes.isEmpty {
                    VStack(spacing: 0) {
                        ForEach(Array(fixedTimes.enumerated()), id: \.offset) { index, time in
                            timeRow(time, at: index, isLast: index == fixedTimes.count - 1)
                        }
                    }
                    .cardChrome(radius: 10, fill: Color.primary.opacity(0.03))
                }

                if fixedTimes.isEmpty {
                    InlineWarning(text: "还没有指定时刻，提醒不会触发。")
                } else {
                    let outside = fixedTimes.filter { $0 < store.state.workStart || $0 >= store.state.workEnd }
                    if !outside.isEmpty {
                        InlineWarning(
                            text: "\(outside.map { $0.formatted() }.joined(separator: "、")) 不在工作时段内，不会提醒。"
                        )
                    }
                }

                Button {
                    addTime()
                } label: {
                    Label("添加时刻", systemImage: "plus")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .frame(height: 30)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .strokeBorder(Theme.stroke, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
            } else {
                SettingsRow(title: "间隔") {
                    AmountStepper(value: intervalMinutes, range: 5...240, step: 5, unit: "分钟") {
                        setSchedule(.interval(minutes: $0))
                    }
                }
                Text("从工作时段开始按间隔铺开，最后一个点不会越过结束时间。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// 指定时刻的一行：时间和删除同属一行，行间用分隔线连起来，不是左右两截。
    private func timeRow(_ time: TimeOfDay, at index: Int, isLast: Bool) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                TimePicker(label: "", time: time, bordered: false) { newTime in
                    setTime(newTime, at: index)
                }
                Spacer(minLength: 8)
                ConfirmDeleteButton(
                    form: .quiet,
                    label: "删除 \(time.formatted())",
                    confirming: model.confirmingDelete == "time:\(index)",
                    onArm: { model.confirmingDelete = "time:\(index)" }
                ) {
                    model.confirmingDelete = nil
                    removeTime(at: index)
                }
            }
            .padding(.vertical, 7)
            .padding(.leading, 10)
            .padding(.trailing, 8)

            if !isLast {
                Divider().opacity(0.6)
            }
        }
    }

    // MARK: - 时间

    private var timeCard: some View {
        SettingsCard(title: "时间", footnote: durationText) {
            HStack(spacing: 18) {
                TimePicker(label: "开始", time: store.state.workStart) { setWorkTime(\.workStart, $0) }
                TimePicker(label: "结束", time: store.state.workEnd) { setWorkTime(\.workEnd, $0) }
                Spacer()
            }

            if store.state.workStart >= store.state.workEnd {
                InlineWarning(text: "结束时间必须晚于开始时间，当前不会触发提醒。")
            }

            Divider()
                .opacity(0.7)

            HStack(spacing: 12) {
                Text("休息日")
                    .font(.system(size: 13))
                Spacer(minLength: 8)
                HStack(spacing: 5) {
                    ForEach(Self.weekdayOrder, id: \.self) { weekday in
                        DayPill(
                            label: Self.weekdayNames[weekday] ?? "?",
                            selected: store.state.restDays.contains(weekday),
                            accessibilityLabel: "周\(Self.weekdayNames[weekday] ?? "?")"
                        ) {
                            var days = store.state.restDays
                            if days.contains(weekday) {
                                days.remove(weekday)
                            } else {
                                days.insert(weekday)
                            }
                            store.set(\.restDays, days)
                            engine.reschedule()
                        }
                    }
                }
            }

            Text("喝水与活动共用这套时间；日程按事件自己的时间提醒，不受这里约束。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - 通用

    private var generalCard: some View {
        SettingsCard(title: "通用") {
            SettingsRow(title: "开机时启动", hint: "登录后在菜单栏静默启动，不打开窗口") {
                Toggle("开机时启动", isOn: Binding(
                    get: { login.isEnabled },
                    set: { login.set($0) }
                ))
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)
            }
        }
    }

    // MARK: - 底部状态

    private var footer: some View {
        TimelineView(.periodic(from: .now, by: 30)) { context in
            HStack(spacing: 8) {
                Circle()
                    .fill(footerTint(at: context.date))
                    .frame(width: 6, height: 6)
                Text(footerText(at: context.date))
                    .font(.system(size: 12, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 12)
                Text("改动即时生效")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 11)
        .background(Color(nsColor: .windowBackgroundColor))
        .overlay(alignment: .top) { Divider() }
    }

    private func footerText(at now: Date) -> String {
        if let until = store.state.pausedUntil, until > now {
            return "免打扰至 \(RelativeTime.clock(until))"
        }
        let enabled = SceneID.allCases.filter { store.isSceneEnabled($0) }
        guard !enabled.isEmpty else { return "提醒已全部停用" }
        let candidates = enabled.compactMap { scene in
            engine.nextFireDates[scene].map { (scene, $0) }
        }
        guard let nearest = candidates.min(by: { $0.1 < $1.1 }) else {
            return "当前设置不会触发提醒"
        }
        return "下一次提醒 · \(store.sceneTitle(nearest.0)) \(RelativeTime.when(nearest.1, now: now))"
    }

    private func footerTint(at now: Date) -> Color {
        if store.state.pausedUntil.map({ $0 > now }) == true { return Theme.accent }
        if !SceneID.allCases.contains(where: { store.isSceneEnabled($0) }) { return Theme.warn }
        if engine.nextFireDates.isEmpty { return Theme.warn }
        return Theme.accent
    }

    // MARK: - 绑定

    private func setWorkTime(_ keyPath: WritableKeyPath<AppState, TimeOfDay>, _ time: TimeOfDay) {
        store.set(keyPath, time)
        engine.reschedule()
    }

    private func setTime(_ time: TimeOfDay, at index: Int) {
        var times = fixedTimes
        guard index < times.count else { return }
        times[index] = time
        setSchedule(.timesOfDay(times))
    }

    // MARK: - 数据

    private var rhythm: Schedule? { currentConfig.trigger.rhythm }

    private var isFixedTimes: Bool {
        guard let rhythm, case .timesOfDay = rhythm else { return false }
        return true
    }

    private var fixedTimes: [TimeOfDay] {
        guard let rhythm, case .timesOfDay(let times) = rhythm else { return [] }
        return times
    }

    private var intervalMinutes: Int {
        guard let rhythm, case .interval(let minutes) = rhythm else { return 60 }
        return minutes
    }

    private var durationText: String {
        let minutes = store.state.workEnd.minutesSinceMidnight - store.state.workStart.minutesSinceMidnight
        guard minutes > 0 else { return "未生效" }
        let hours = minutes / 60
        let rest = minutes % 60
        if hours == 0 { return "\(rest) 分钟" }
        return rest == 0 ? "\(hours) 小时" : "\(hours) 小时 \(rest) 分"
    }

    private func setSchedule(_ schedule: Schedule) {
        store.setTrigger(.rhythm(schedule), for: model.selectedScene)
        engine.reschedule()
    }

    private func addTime() {
        setSchedule(.timesOfDay((fixedTimes + [TimeOfDay(hour: 15, minute: 0)]).sorted()))
    }

    private func removeTime(at index: Int) {
        var times = fixedTimes
        guard index < times.count else { return }
        times.remove(at: index)
        setSchedule(.timesOfDay(times))
    }
}

// MARK: - 设置专用控件

private struct DayPill: View {
    let label: String
    let selected: Bool
    let accessibilityLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 12, weight: selected ? .semibold : .regular))
                .foregroundStyle(selected ? Theme.accentText : Color.secondary)
                .frame(width: 30, height: 28)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(selected ? Theme.accent.opacity(0.14) : Color.primary.opacity(0.04))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(selected ? Theme.accent.opacity(0.45) : Theme.stroke, lineWidth: 1)
                )
        }
        .buttonStyle(PressableStyle(scale: 0.94))
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(selected ? .isSelected : AccessibilityTraits())
    }
}
