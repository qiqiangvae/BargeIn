import AppKit
import Observation
import BargeInCore

/// 同一时刻多个场景到点时，按到点时间排队。
/// 喝水与活动每个场景最多一条；日程按事件各一条，不静默丢弃。
enum ReminderQueue {
    static func sorted(_ items: [(key: ReminderKey, at: Date)]) -> [ReminderKey] {
        items
            .sorted { lhs, rhs in
                if lhs.at != rhs.at { return lhs.at < rhs.at }
                if lhs.key.scene != rhs.key.scene { return order(lhs.key.scene) < order(rhs.key.scene) }
                switch (lhs.key.event, rhs.key.event) {
                case let (left?, right?): return left < right
                case (nil, _?): return true
                case (_?, nil): return false
                case (nil, nil): return false
                }
            }
            .map(\.key)
    }

    static func enqueue(_ keys: [ReminderKey], into pending: inout [ReminderKey]) {
        for key in keys where !pending.contains(key) {
            pending.append(key)
        }
    }

    private static func order(_ scene: SceneID) -> Int {
        SceneID.allCases.firstIndex(of: scene) ?? 0
    }
}

/// 定时驱动：只在需要的时候挂一个一次性 Timer，其余靠唤醒、时钟变化与订阅刷新重算。
@MainActor
@Observable
final class ReminderEngine {
    /// 每个启用场景的下一次触发时刻，UI 读它。
    private(set) var nextFireDates: [SceneID: Date] = [:]
    /// 已到点尚未呈现的提醒，先到先呈现。
    private(set) var pending: [ReminderKey] = []

    @ObservationIgnored private let store: StateStore
    @ObservationIgnored private let presence: Presence
    @ObservationIgnored private var timer: Timer?
    /// 本地节奏的"推迟 5 分钟"，只活在进程内。
    @ObservationIgnored private var overrides: [SceneID: Date] = [:]
    @ObservationIgnored var onPendingChanged: (() -> Void)?

    init(store: StateStore, presence: Presence) {
        self.store = store
        self.presence = presence
        observeSystemEvents()
        reschedule()
    }

    var pendingCount: Int { pending.count }

    func dequeue() -> ReminderKey? {
        pending.isEmpty ? nil : pending.removeFirst()
    }

    func setPaused(until date: Date?) {
        if date != nil { overrides.removeAll() }
        store.set(\.pausedUntil, date)
        // 恢复提醒时先补一次采集：免打扰期间到点的一次性闹钟还在补发窗口里。
        if date == nil {
            systemChanged()
        } else {
            reschedule()
        }
    }

    /// 推迟只活在进程内：重启后回到原有节奏，5 分钟的临时偏执不值得落盘。
    /// 日程推迟的是那条事件本身，即便是最后一次提醒。
    func postpone(_ key: ReminderKey, minutes: Int) {
        if key.scene == .alarm, let moment = key.event {
            store.snoozeAlarm(moment, minutes: minutes)
        } else if let event = key.event {
            store.snooze(event, minutes: minutes)
        } else {
            overrides[key.scene] = Date().addingTimeInterval(TimeInterval(minutes * 60))
        }
        reschedule()
    }

    func reschedule(now: Date = Date()) {
        timer?.invalidate()
        timer = nil

        store.refreshDay(now: now)

        for scene in SceneID.allCases where !store.isSceneEnabled(scene) {
            overrides[scene] = nil
        }
        if store.isCompleted(.water) { overrides[.water] = nil }
        for (scene, date) in overrides where date <= now {
            overrides[scene] = nil
        }

        var dates: [SceneID: Date] = [:]
        for scene in SceneID.allCases {
            if let override = overrides[scene] {
                dates[scene] = override
            } else if let next = store.nextFireDate(for: scene, after: now) {
                dates[scene] = next
            }
        }
        nextFireDates = dates

        // 免打扰结束那一刻也要醒来：期间到点的提醒不会排在"下一次触发"里，
        // 得靠这次唤醒把它们按补发窗口收回来。
        var earliest = dates.values.min()
        if let paused = store.state.pausedUntil, paused > now {
            earliest = min(earliest ?? .distantFuture, paused)
        }
        guard let earliest else { return }
        let delay = max(0, earliest.timeIntervalSince(now))
        let timer = Timer(timeInterval: delay, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.fire() }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func fire() {
        let now = Date()
        store.refreshDay(now: now)
        collectDue(now: now)
        reschedule(now: now)
    }

    /// 人离开时队列作废：回来不补离开前到点的那几条。
    /// 日程事件没被标记处理过，回到在场后由它自己的「开始后 10 分钟」窗口重新收。
    func abandonPending() {
        pending.removeAll()
    }

    /// 唤醒、解锁、时钟跳变：定时器可能没来得及响，补一次到点。
    func systemChanged() {
        let now = Date()
        store.refreshDay(now: now)
        collectDue(now: now)
        reschedule(now: now)
    }

    /// 订阅刷新完也要立刻重算：新事件可能就在几分钟之后。
    func feedsChanged() {
        systemChanged()
    }

    private func collectDue(now: Date) {
        // 人不在（锁屏 / 屏幕睡眠 / 切到别的用户）就不采集：这一拍直接作废，回来不补。
        guard presence.isPresent else { return }

        var items: [(key: ReminderKey, at: Date)] = []

        for scene in SceneID.allCases where store.isSceneEnabled(scene) {
            switch store.trigger(for: scene) {
            case .rhythm:
                // 本地节奏只收同一天、工作时段内、未暂停、到点后还没过太久的点。
                guard store.isWithinActiveWindow(at: now),
                      let next = nextFireDates[scene],
                      next <= now,
                      now.timeIntervalSince(next) <= FirePlan.catchUpWindow,
                      store.isSameDay(next, now)
                else { continue }
                items.append((.sceneOnly(scene), next))
            case .events:
                // 日程不受工作时段与休息日约束，由 dueEvents 自己判断。
                for event in store.dueEvents(for: scene, at: now) {
                    items.append((ReminderKey(scene: scene, event: event.key), store.fireTime(for: event)))
                }
            case .alarms:
                // 闹钟的候选时刻与补发窗口都由场景状态自己算好。
                for due in store.dueAlarms(at: now) {
                    items.append((due.key, due.at))
                }
            }
        }

        enqueue(due: ReminderQueue.sorted(items))
    }

    private func enqueue(due: [ReminderKey]) {
        guard !due.isEmpty else { return }
        ReminderQueue.enqueue(due, into: &pending)
        onPendingChanged?()
    }

    private func observeSystemEvents() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.systemChanged() }
        }

        NotificationCenter.default.addObserver(
            forName: .NSSystemClockDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.systemChanged() }
        }
    }
}
