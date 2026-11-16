import Foundation

public struct TimeOfDay: Codable, Equatable, Hashable, Comparable, Sendable {
    public var hour: Int
    public var minute: Int

    public init(hour: Int, minute: Int) {
        self.hour = hour
        self.minute = minute
    }

    public var minutesSinceMidnight: Int { hour * 60 + minute }

    public static func < (lhs: TimeOfDay, rhs: TimeOfDay) -> Bool {
        lhs.minutesSinceMidnight < rhs.minutesSinceMidnight
    }

    public static let nineAM = TimeOfDay(hour: 9, minute: 0)
    public static let sixPM = TimeOfDay(hour: 18, minute: 0)

    public func formatted() -> String {
        String(format: "%02d:%02d", hour, minute)
    }

    /// 当天该时刻的绝对时间。DST 边界上交给 Calendar 处理。
    public func date(on day: Date, calendar: Calendar) -> Date {
        calendar.date(bySettingHour: hour, minute: minute, second: 0, of: day) ?? day
    }
}
