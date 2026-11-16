import Foundation

/// 提醒节奏。加一种新节奏 = 加一个 case + 实现 fireTimes。
public enum Schedule: Codable, Equatable, Sendable {
    case interval(minutes: Int)
    case timesOfDay([TimeOfDay])

    public static let minimumIntervalMinutes = 5

    public func fireTimes(
        on day: Date,
        workStart: TimeOfDay,
        workEnd: TimeOfDay,
        calendar: Calendar
    ) -> [Date] {
        let start = workStart.date(on: day, calendar: calendar)
        let end = workEnd.date(on: day, calendar: calendar)
        guard start < end else { return [] }

        switch self {
        case .interval(let minutes):
            guard minutes > 0 else { return [] }
            var result: [Date] = []
            var cursor = start
            while cursor < end {
                result.append(cursor)
                guard let next = calendar.date(byAdding: .minute, value: minutes, to: cursor) else { break }
                cursor = next
            }
            return result

        case .timesOfDay(let times):
            return times.sorted().compactMap { time in
                let date = time.date(on: day, calendar: calendar)
                return (date >= start && date < end) ? date : nil
            }
        }
    }
}

/// 触发来源：本地节奏、订阅日历里的事件，或用户自己定的一串时刻。
/// 三种来源的"下一次触发"算法不同，但下游的队列、呈现、账本完全一样。
public enum SceneTrigger: Codable, Equatable, Sendable {
    case rhythm(Schedule)
    case events(leadMinutes: Int)
    /// 闹钟：触发时刻由闹钟自己带着，没有前置、没有节奏参数。
    /// 不复用 `events(leadMinutes:)`：`trigger` 参与存档容错、被当作场景身份，共用取值会被认错。
    case alarms

    public var rhythm: Schedule? {
        if case .rhythm(let schedule) = self { return schedule }
        return nil
    }

    public var leadMinutes: Int? {
        if case .events(let lead) = self { return lead }
        return nil
    }
}

/// 一个已经落在日历上的触发时刻。场景模块把「闹钟 + 通用时间」翻译成它，
/// 调度层只认时刻与身份，不知道闹钟长什么样。
public struct ScheduledMoment: Equatable, Sendable {
    /// 稳定身份（同一个闹钟每天的那一次用同一个 id，时刻不同）。
    public var id: String
    public var at: Date
    /// 一次性时刻：错过之后有补发窗口；重复时刻错过就等下一次。
    public var isOneShot: Bool

    public init(id: String, at: Date, isOneShot: Bool) {
        self.id = id
        self.at = at
        self.isOneShot = isOneShot
    }
}

/// 调度只关心这些：这个场景启用没有、今天是否已经完成、什么时候上班、是否暂停。
/// 场景私有的业务模型不进来；日程事件与闹钟时刻只是"下一次触发"的候选。
public struct SceneRuntime: Equatable, Sendable {
    public var isEnabled: Bool
    public var trigger: SceneTrigger
    public var workStart: TimeOfDay
    public var workEnd: TimeOfDay
    public var restDays: Set<Int>
    public var pausedUntil: Date?
    public var isCompletedToday: Bool
    /// 只对 `.events` 生效：订阅解析出来的事件发生。
    public var events: [EventOccurrence]
    /// 只对 `.events` 生效：已经提醒过（完成 / 中断）的事件，不重弹。
    public var handled: Set<EventKey>
    /// 只对 `.events` 生效：推迟过的事件，到点再提醒一次。
    public var snoozedUntil: [EventKey: Date]
    /// 只对 `.alarms` 生效：已经过通用时间筛过的时刻。
    public var moments: [ScheduledMoment]
    /// 只对 `.alarms` 生效：已经提醒过的时刻。
    public var handledMoments: Set<EventKey>
    /// 只对 `.alarms` 生效：推迟过的时刻，到点再提醒一次。
    public var snoozedMoments: [EventKey: Date]

    public init(
        isEnabled: Bool,
        trigger: SceneTrigger,
        workStart: TimeOfDay,
        workEnd: TimeOfDay,
        restDays: Set<Int>,
        pausedUntil: Date?,
        isCompletedToday: Bool,
        events: [EventOccurrence] = [],
        handled: Set<EventKey> = [],
        snoozedUntil: [EventKey: Date] = [:],
        moments: [ScheduledMoment] = [],
        handledMoments: Set<EventKey> = [],
        snoozedMoments: [EventKey: Date] = [:]
    ) {
        self.isEnabled = isEnabled
        self.trigger = trigger
        self.workStart = workStart
        self.workEnd = workEnd
        self.restDays = restDays
        self.pausedUntil = pausedUntil
        self.isCompletedToday = isCompletedToday
        self.events = events
        self.handled = handled
        self.snoozedUntil = snoozedUntil
        self.moments = moments
        self.handledMoments = handledMoments
        self.snoozedMoments = snoozedMoments
    }
}

/// 只做一件事：给定"现在"和一个场景的触发条件，算出下一次该提醒的时刻。
public enum FirePlan {
    public static let maxLookaheadDays = 8
    /// 已经开始超过这么久的日程不再补提醒：启动、唤醒、刷新都不为开完的会弹窗。
    public static let catchUpWindow: TimeInterval = 10 * 60

    public static func next(after now: Date, runtime: SceneRuntime, calendar: Calendar) -> Date? {
        guard runtime.isEnabled else { return nil }

        let effective = max(now, runtime.pausedUntil ?? .distantPast)
        switch runtime.trigger {
        case .rhythm(let schedule):
            return nextRhythm(after: effective, schedule: schedule, runtime: runtime, calendar: calendar)
        case .events(let lead):
            return nextEvent(after: now, effective: effective, lead: lead, runtime: runtime)
        case .alarms:
            return nextMoment(after: effective, runtime: runtime)
        }
    }

    /// 闹钟：候选项已经被场景模块按通用时间筛过，这里只挑最早一个还没处理过的。
    private static func nextMoment(after effective: Date, runtime: SceneRuntime) -> Date? {
        runtime.moments.compactMap { moment -> Date? in
            let key = EventKey(uid: moment.id, start: moment.at)
            guard !runtime.handledMoments.contains(key) else { return nil }
            let fire = max(moment.at, runtime.snoozedMoments[key] ?? .distantPast)
            return fire > effective ? fire : nil
        }.min()
    }

    private static func nextRhythm(
        after effective: Date,
        schedule: Schedule,
        runtime: SceneRuntime,
        calendar: Calendar
    ) -> Date? {
        let firstDay = calendar.startOfDay(for: effective)

        for offset in 0..<maxLookaheadDays {
            guard let day = calendar.date(byAdding: .day, value: offset, to: firstDay) else { return nil }

            if runtime.restDays.contains(calendar.component(.weekday, from: day)) { continue }

            if runtime.isCompletedToday, calendar.isDate(day, inSameDayAs: effective) {
                continue
            }

            let points = schedule.fireTimes(
                on: day,
                workStart: runtime.workStart,
                workEnd: runtime.workEnd,
                calendar: calendar
            )
            if let next = points.first(where: { $0 > effective }) { return next }
        }
        return nil
    }

    /// 日程：事件开始时刻减去前置。不受工作时段与休息日约束，只受免打扰与"已经提醒过"约束。
    private static func nextEvent(
        after now: Date,
        effective: Date,
        lead: Int,
        runtime: SceneRuntime
    ) -> Date? {
        let catchUp = now.addingTimeInterval(-catchUpWindow)
        let candidates = runtime.events.compactMap { event -> Date? in
            guard !runtime.handled.contains(event.key) else { return nil }
            let snoozed = runtime.snoozedUntil[event.key]
            // 没有推迟过的、已经开完的会不补；推迟过的即便已经开始也还要提醒一次。
            guard snoozed != nil || event.start > catchUp else { return nil }
            let fire = max(
                event.start.addingTimeInterval(-Double(lead) * 60),
                snoozed ?? .distantPast
            )
            return fire > effective ? fire : nil
        }
        return candidates.min()
    }
}
