import AppKit
import SwiftUI
import BargeInCore
import SceneSchedule
import SceneAlarm

struct PopoverView: View {
    let store: StateStore
    let engine: ReminderEngine
    let onOpenSettings: () -> Void

    // 本机只有 CLT，SwiftUI 的 @State 宏不可用，按住状态走 @StateObject。
    @StateObject private var press = RingPress()

    private static let holdDuration: TimeInterval = 2
    /// 按下后先不动声色，超过这个时长才进入"正在清空"的样子，避免点击时闪一下。
    private static let revealDelay: TimeInterval = 0.2

    var body: some View {
        // 每 30 秒整体刷新一次：免打扰到期、相对时间、按钮标签都要跟着走，不能只刷新某一行。
        TimelineView(.periodic(from: .now, by: 30)) { _ in
            content
        }
    }

    private var waterEnabled: Bool { store.isSceneEnabled(.water) }
    private var activityEnabled: Bool { store.isSceneEnabled(.activity) }
    private var scheduleEnabled: Bool { store.isSceneEnabled(.schedule) }
    private var alarmEnabled: Bool { store.isSceneEnabled(.alarm) }

    private var content: some View {
        VStack(alignment: .leading, spacing: 12) {
            if waterEnabled { waterSection }
            if activityEnabled { activitySection }
            if scheduleEnabled { scheduleSection }
            if alarmEnabled { alarmSection }
            if !waterEnabled && !activityEnabled && !scheduleEnabled && !alarmEnabled { emptyState }
            footer
        }
        .padding(18)
        .frame(width: 304)
        // 按住清空的倒计时跑在视图之外：popover 关掉时立刻撤掉，别在看不见的地方把进度清了。
        .onDisappear {
            press.revealTask?.cancel()
            press.revealTask = nil
            press.task?.cancel()
            press.task = nil
            press.isHolding = false
            press.holdProgress = 0
        }
    }

    // MARK: - 喝水

    private var waterSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            waterHeadline
            ring
            waterStatusLine
        }
    }

    /// 水区只写场景名：杯数是个假单位（一次喝多少不等于一只杯子的容量），
    /// 真正的计量在环里，用 ml 就够了。
    private var waterHeadline: some View {
        Text(store.sceneTitle(.water))
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// 环本身就是喝水按钮：点一下记一杯，按住 2 秒清空今日进度。
    private var ring: some View {
        ZStack {
            Circle()
                .stroke(Color.primary.opacity(0.07), lineWidth: 10)

            Circle()
                .trim(from: 0, to: ringProgress)
                .stroke(Theme.actionGradient, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(Motion.enter, value: store.progress)

            Circle()
                .trim(from: 0, to: ringProgress)
                .stroke(Theme.warn, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .opacity(press.isHolding ? 1 : 0)

            VStack(spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(store.state.water.consumedML)")
                        .font(.system(size: 29, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("ml")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Text(ringRestText)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            .opacity(press.isHolding ? 0 : 1)

            Text("松手取消")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.warn)
                .opacity(press.isHolding ? 1 : 0)

            Text("+\(store.state.water.cupML) ml")
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(Theme.accentText)
                .offset(y: -33)
                .opacity(press.isHovering && !press.isHolding ? 1 : 0)
        }
        .frame(width: 140, height: 140)
        .contentShape(Circle())
        .onHover { press.isHovering = $0 }
        .gesture(pressGesture)
        .help("点一下记一杯 · 按住 2 秒清空今日进度")
        .animation(Motion.press, value: press.isHolding)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(
            "今日已喝 \(store.state.water.consumedML) 毫升，目标 \(store.state.water.targetML) 毫升"
        )
        .accessibilityAction(named: "记一杯 \(store.state.water.cupML) 毫升") {
            store.drink()
            engine.reschedule()
        }
        .accessibilityAction(named: "清空今日进度") {
            clearProgress()
        }
        .frame(maxWidth: .infinity)
    }

    private var ringRestText: String {
        if store.state.water.isCompleted { return "已达标" }
        let rest = max(0, store.state.water.targetML - store.state.water.consumedML)
        return "还差 \(rest.formatted()) ml"
    }

    /// 按住时环从当前进度退到 0。
    private var ringProgress: Double {
        store.progress * (1 - press.holdProgress)
    }

    private var pressGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if press.startedAt == nil { beginPress() }
                if distanceFromCenter(value.location) > 70 { cancelPress() }
            }
            .onEnded { _ in endPress() }
    }

    private func distanceFromCenter(_ point: CGPoint) -> CGFloat {
        let dx = point.x - 70
        let dy = point.y - 70
        return (dx * dx + dy * dy).squareRoot()
    }

    private func beginPress() {
        press.startedAt = Date()
        press.cancelled = false
        press.cleared = false
        // 0 ml 没有可清的，按住不演倒计时，但松手仍算一次点击。
        guard store.state.water.consumedML > 0 else { return }

        let ringState = press
        let store = self.store
        let engine = self.engine

        // 露头：按住够久才换掉环里的数字，并把环转成琥珀色往下退。
        press.revealTask?.cancel()
        press.revealTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.revealDelay))
            guard !Task.isCancelled, ringState.startedAt != nil, !ringState.cancelled else { return }
            ringState.isHolding = true
            withAnimation(.linear(duration: Self.holdDuration - Self.revealDelay)) {
                ringState.holdProgress = 1
            }
        }

        press.task?.cancel()
        press.task = Task { @MainActor in
            try? await Task.sleep(for: .seconds(Self.holdDuration))
            guard !Task.isCancelled else { return }
            ringState.cleared = true
            ringState.isHolding = false
            ringState.holdProgress = 0
            store.clearWaterProgress()
            engine.reschedule()
        }
    }

    private func cancelPress() {
        guard press.startedAt != nil, !press.cleared else { return }
        press.cancelled = true
        press.revealTask?.cancel()
        press.revealTask = nil
        press.task?.cancel()
        press.task = nil
        press.isHolding = false
        withAnimation(Motion.press) { press.holdProgress = 0 }
    }

    private func endPress() {
        let started = press.startedAt
        let cancelled = press.cancelled
        press.startedAt = nil
        press.cancelled = false
        press.revealTask?.cancel()
        press.revealTask = nil
        press.task?.cancel()
        press.task = nil

        if press.cleared {
            press.cleared = false
            return
        }
        press.isHolding = false
        guard !cancelled else {
            withAnimation(Motion.press) { press.holdProgress = 0 }
            return
        }
        let elapsed = started.map { Date().timeIntervalSince($0) } ?? 1
        press.holdProgress = 0
        guard elapsed < Self.revealDelay else { return }
        store.drink()
        engine.reschedule()
    }

    /// 只清今日毫升数；账本跳过数与免打扰都不动，清完立刻恢复喝水调度。
    private func clearProgress() {
        press.revealTask?.cancel()
        press.revealTask = nil
        press.task?.cancel()
        press.task = nil
        press.cleared = true
        press.isHolding = false
        press.holdProgress = 0
        store.clearWaterProgress()
        engine.reschedule()
    }

    private var waterStatusLine: some View {
        HStack(spacing: 6) {
            Image(systemName: waterStatusIcon(at: Date()))
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(waterStatusTint)
            Text(waterStatusText(at: Date()))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    // MARK: - 活动

    private var activitySection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: store.descriptor(.activity).completionSymbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.accentText)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(store.sceneTitle(.activity))
                            .font(.system(size: 12, weight: .semibold))
                        Text("今天 \(store.activityDoneToday) 次")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                    Text(activityStatusText(at: Date()))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)

                QuietButton(title: store.descriptor(.activity).completionLabel, height: 30, emphasized: true) {
                    store.completeActivity()
                    engine.reschedule()
                }
                .frame(width: 78)
            }
            .padding(10)
            .cardChrome(fill: Theme.cardFill)
        }
    }

    // MARK: - 日程

    private var scheduleSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: store.descriptor(.schedule).completionSymbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.accentText)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(store.sceneTitle(.schedule))
                            .font(.system(size: 12, weight: .semibold))
                        Text("今天 \(todayEventCount) 场")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                    Text(scheduleStatusText(at: Date()))
                        .font(.system(size: 10.5))
                        .foregroundStyle(scheduleStatusIsWarning ? Theme.warn : Color.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)
            }
            .padding(10)
            .cardChrome(fill: Theme.cardFill)
        }
    }

    private var todayEventCount: Int {
        let now = Date()
        return store.scheduleEvents.filter { store.isSameDay($0.start, now) }.count
    }

    private var scheduleStatusIsWarning: Bool {
        store.state.schedule.subscriptions.contains { $0.isEnabled && $0.lastError != nil }
    }

    private func scheduleStatusText(at now: Date) -> String {
        if let until = store.state.pausedUntil, until > now { return "免打扰中" }
        guard store.hasEnabledSubscription else { return "还没配置订阅" }
        if let error = store.state.schedule.subscriptions
            .first(where: { $0.isEnabled && $0.lastError != nil })?
            .lastError {
            return "\(error.message) · 数据可能已过期"
        }
        guard let event = store.nextEvent(after: now) else { return "今天没有日程了" }
        // 隔几天才有的事只说「N 天后」：四位数分钟数一眼读不出还有多久。
        let tail = event.start > now ? RelativeTime.distance(from: now, to: event.start) : "开始了"
        return "\(event.title) · \(tail)"
    }

    // MARK: - 闹钟

    private var alarmSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: store.descriptor(.alarm).completionSymbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.accentText)
                    .frame(width: 22)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 5) {
                        Text(store.sceneTitle(.alarm))
                            .font(.system(size: 12, weight: .semibold))
                        Text("今天 \(store.alarmsScheduledToday().count) 条")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                    Text(alarmStatusText(at: Date()))
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 6)
            }
            .padding(10)
            .cardChrome(fill: Theme.cardFill)
        }
    }

    /// 只读：到点由提醒层接管，这里不提供动作。
    private func alarmStatusText(at now: Date) -> String {
        if let until = store.state.pausedUntil, until > now { return "免打扰中" }
        if store.alarms.isEmpty { return "还没有闹钟" }
        guard let next = store.nextAlarm(after: now) else { return "今天没有会响的闹钟" }
        if store.isSameDay(next.at, now) {
            return "\(next.alarm.displayTitle) · \(AlarmPolicy.timeText(next.at, calendar: .current))"
        }
        return "\(next.alarm.displayTitle) · \(RelativeTime.when(next.at, now: now))"
    }

    private var emptyState: some View {
        HStack(spacing: 7) {
            Image(systemName: "moon.zzz.fill")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Text("提醒已全部停用")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 6)
    }

    private var footer: some View {
        VStack(spacing: 0) {
            Divider()
                .opacity(0.6)
                .padding(.bottom, 8)

            // 设置与退出各靠一边、免打扰居中：这两个整宽项原来并排，点快了就把设置点成退出。
            HStack(spacing: 2) {
                footerButton("设置", icon: "gearshape") {
                    onOpenSettings()
                }
                Spacer(minLength: 6)
                if waterEnabled || activityEnabled || scheduleEnabled || alarmEnabled {
                    pauseButton
                }
                Spacer(minLength: 6)
                footerButton("退出", icon: "power") {
                    NSApplication.shared.terminate(nil)
                }
            }
        }
    }

    // MARK: - 文案与状态

    private var isPaused: Bool {
        guard let until = store.state.pausedUntil else { return false }
        return until > Date()
    }

    private func waterStatusText(at now: Date) -> String {
        if let until = store.state.pausedUntil, until > now {
            return "免打扰至 \(RelativeTime.clock(until)) · \(RelativeTime.distance(from: now, to: until))恢复"
        }
        // 达标这件事由环里的"已达标"和绿勾说完了，状态行回到日程本身
        if store.state.water.isCompleted, engine.nextFireDates[.water] == nil { return "今天已达标" }
        guard let next = engine.nextFireDates[.water] else { return "当前设置不会触发提醒" }
        return "下次 \(RelativeTime.when(next, now: now))"
    }

    private func waterStatusIcon(at now: Date) -> String {
        if let until = store.state.pausedUntil, until > now { return "moon.fill" }
        if store.state.water.isCompleted { return "checkmark.circle.fill" }
        if engine.nextFireDates[.water] == nil { return "moon.fill" }
        return "clock.fill"
    }

    private var waterStatusTint: Color {
        if isPaused { return Theme.accent }
        if store.state.water.isCompleted { return Theme.success }
        if engine.nextFireDates[.water] == nil { return .secondary }
        return Theme.accent
    }

    private func activityStatusText(at now: Date) -> String {
        if let until = store.state.pausedUntil, until > now { return "免打扰中" }
        guard let next = engine.nextFireDates[.activity] else { return "今天不会提醒" }
        return "下次 \(RelativeTime.when(next, now: now))"
    }

    /// 免打扰是全局动作，原来那个 36pt 整宽按钮比真正的主动作还重，现在收进底栏。
    private var pauseButton: some View {
        let paused = isPaused
        return Button {
            engine.setPaused(until: paused ? nil : Date().addingTimeInterval(3600))
        } label: {
            Label(paused ? "恢复提醒" : "免打扰 1 小时", systemImage: paused ? "play.fill" : "moon.fill")
                .font(.system(size: 11))
                .foregroundStyle(paused ? Theme.accentText : Color.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
        }
        .buttonStyle(FooterButtonStyle())
    }

    private func footerButton(_ title: String, icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 7)
                .padding(.vertical, 5)
                .contentShape(Rectangle())
        }
        .buttonStyle(FooterButtonStyle())
    }
}

/// 环上按住的交互状态：点击、按住倒计时、松手取消都只动这里。
private final class RingPress: ObservableObject {
    @Published var holdProgress: Double = 0
    @Published var isHolding = false
    @Published var isHovering = false

    var revealTask: Task<Void, Never>?
    var task: Task<Void, Never>?
    var startedAt: Date?
    var cancelled = false
    var cleared = false
}

private struct FooterButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.primary.opacity(configuration.isPressed ? 0.08 : 0))
            )
            .animation(Motion.press, value: configuration.isPressed)
    }
}
