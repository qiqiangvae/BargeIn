import Foundation
import BargeInCore

/// 一条闹钟：你自己定下的时刻加一句内容。
public struct Alarm: Codable, Equatable, Identifiable, Sendable {
    /// 重复只有两种：每天（每个非休息日）或仅一次（未来 7 天内的一天）。
    /// 星期只有一个来源，就是通用的休息日，所以这里不提供"选星期几"。
    public enum Repeat: Codable, Equatable, Sendable {
        case daily
        case once(Date)
    }

    public var id: UUID
    /// 一句话内容。空的时候界面用时刻顶上。
    public var title: String
    public var time: TimeOfDay
    public var recurrence: Repeat
    public var isEnabled: Bool

    public init(
        id: UUID = UUID(),
        title: String = "",
        time: TimeOfDay,
        recurrence: Repeat = .daily,
        isEnabled: Bool = true
    ) {
        self.id = id
        self.title = title
        self.time = time
        self.recurrence = recurrence
        self.isEnabled = isEnabled
    }

    public var isRepeatingDaily: Bool {
        if case .daily = recurrence { return true }
        return false
    }

    public var onceDay: Date? {
        if case .once(let day) = recurrence { return day }
        return nil
    }

    /// 界面上显示的那句话：内容为空就用时刻。
    public var displayTitle: String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? time.formatted() : title
    }

    /// 逐字段容错：闹钟没有外部身份，字段缺哪补哪；整条都读不出来由外层按条丢掉。
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = container.tolerant(UUID.self, forKey: .id, or: UUID())
        title = container.tolerant(String.self, forKey: .title, or: "")
        time = container.tolerant(TimeOfDay.self, forKey: .time, or: .nineAM)
        recurrence = container.tolerant(Repeat.self, forKey: .recurrence, or: .daily)
        isEnabled = container.tolerant(Bool.self, forKey: .isEnabled, or: true)
    }
}

/// 闹钟在当前通用时间下为什么不会响。
public enum AlarmIssue: Equatable, Sendable {
    case outsideWorkHours
    case restDay

    public var message: String {
        switch self {
        case .outsideWorkHours: "不在工作时段内，不会响"
        case .restDay: "那天是休息日，不会响"
        }
    }
}

/// 闹钟的判定与文案。全是纯函数：无效是派生的，改一次工作时段或休息日就重算，不落盘。
public enum AlarmPolicy {
    /// 一次性闹钟只受理未来 7 天：更远的事该进日历，由日程场景打断你。
    public static let horizonDays = 7

    public static func issue(
        for alarm: Alarm,
        workStart: TimeOfDay,
        workEnd: TimeOfDay,
        restDays: Set<Int>,
        calendar: Calendar
    ) -> AlarmIssue? {
        guard alarm.time >= workStart, alarm.time < workEnd else { return .outsideWorkHours }
        if let day = alarm.onceDay,
           restDays.contains(calendar.component(.weekday, from: day)) {
            return .restDay
        }
        return nil
    }

    public static func repeatText(_ alarm: Alarm, calendar: Calendar) -> String {
        switch alarm.recurrence {
        case .daily: return "每天"
        case .once(let day): return "仅一次 · \(dayText(day, calendar: calendar))"
        }
    }

    public static func dayText(_ day: Date, calendar: Calendar) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "M月d日"
        let weekday = calendar.component(.weekday, from: day)
        return "\(formatter.string(from: day)) · \(weekdayNames[(weekday - 1) % 7])"
    }

    /// 到点那一刻的 `HH:mm`。推迟过的提醒也用原定时刻，别让文案跟着推迟一起漂。
    public static func timeText(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
    }

    private static let weekdayNames = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]

    /// 一次性闹钟可选的那几天：今天起 7 天。
    public static func dateRange(now: Date, calendar: Calendar) -> ClosedRange<Date> {
        let today = calendar.startOfDay(for: now)
        let last = calendar.date(byAdding: .day, value: horizonDays - 1, to: today) ?? today
        return today...last
    }

    public static func clamp(_ day: Date, now: Date, calendar: Calendar) -> Date {
        let range = dateRange(now: now, calendar: calendar)
        let start = calendar.startOfDay(for: day)
        if start < range.lowerBound { return range.lowerBound }
        if start > range.upperBound { return range.upperBound }
        return start
    }
}

/// 闹钟场景自己的业务状态：列表与已提醒过的时刻（按天清理）。
/// 推迟时刻是进程内状态，不落盘。
public struct AlarmState: Codable, Equatable, Sendable {
    public var alarms: [Alarm]
    /// `EventKey.storageKey` → 处理时间。
    public var handled: [String: Date]

    public init(alarms: [Alarm] = [], handled: [String: Date] = [:]) {
        self.alarms = alarms
        self.handled = handled
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        alarms = container.tolerantArray(Alarm.self, forKey: .alarms)
        handled = container.tolerant([String: Date].self, forKey: .handled, or: [:])
    }
}
