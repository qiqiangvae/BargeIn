import Foundation

/// RRULE 里我们确实会用到的那些字段。
public struct RecurrenceRule: Equatable, Sendable {
    public enum Frequency: String, Sendable {
        case daily = "DAILY"
        case weekly = "WEEKLY"
        case monthly = "MONTHLY"
    }

    public var frequency: Frequency
    public var interval: Int
    public var count: Int?
    public var until: Date?
    /// 1 = 周日 … 7 = 周六。只在 WEEKLY 里展开。
    public var byDay: [Int]

    public init(
        frequency: Frequency,
        interval: Int = 1,
        count: Int? = nil,
        until: Date? = nil,
        byDay: [Int] = []
    ) {
        self.frequency = frequency
        self.interval = interval
        self.count = count
        self.until = until
        self.byDay = byDay
    }

    static func parse(_ text: String) -> RecurrenceRule? {
        var fields: [String: String] = [:]
        for part in text.split(separator: ";") {
            let pair = part.split(separator: "=", maxSplits: 1).map(String.init)
            guard pair.count == 2 else { continue }
            fields[pair[0].uppercased()] = pair[1].uppercased()
        }
        guard let rawFrequency = fields["FREQ"],
              let frequency = Frequency(rawValue: rawFrequency)
        else { return nil }

        let interval = max(1, Int(fields["INTERVAL"] ?? "") ?? 1)
        let count = Int(fields["COUNT"] ?? "")
        var until: Date?
        if let raw = fields["UNTIL"] {
            until = IcsParser.parseDate(raw, params: [:])?.date
        }
        let byDay = (fields["BYDAY"] ?? "")
            .split(separator: ",")
            .compactMap { token -> Int? in
                let letters = token.suffix(2)
                switch letters {
                case "SU": return 1
                case "MO": return 2
                case "TU": return 3
                case "WE": return 4
                case "TH": return 5
                case "FR": return 6
                case "SA": return 7
                default: return nil
                }
            }
        return RecurrenceRule(
            frequency: frequency,
            interval: interval,
            count: count,
            until: until,
            byDay: byDay
        )
    }
}

/// RRULE 展开：只展开窗口内的发生，最多走 4000 步。
/// 系统自带的 `Calendar.RecurrenceRule` 是 macOS 15+ 才有，本项目最低 14，所以自己写。
public enum Recurrence {
    private static let iterationLimit = 4000

    public static func occurrences(
        of event: IcsEvent,
        in window: DateInterval,
        calendar: Calendar
    ) -> [Date] {
        guard let rule = event.rule else {
            return window.contains(event.start) && !isExcluded(event.start, event) ? [event.start] : []
        }
        switch rule.frequency {
        case .daily:
            return daily(event, rule, window, calendar)
        case .weekly:
            return weekly(event, rule, window, calendar)
        case .monthly:
            return monthly(event, rule, window, calendar)
        }
    }

    private static func daily(
        _ event: IcsEvent,
        _ rule: RecurrenceRule,
        _ window: DateInterval,
        _ calendar: Calendar
    ) -> [Date] {
        var current = event.start
        var produced = 0
        if rule.count == nil, window.start > event.start {
            let step = Double(rule.interval) * 86_400
            let gap = window.start.timeIntervalSince(event.start)
            let periods = Int(gap / step)
            if periods > 0,
               let skipped = calendar.date(byAdding: .day, value: periods * rule.interval, to: event.start) {
                current = skipped
                produced = periods
            }
        }

        var result: [Date] = []
        var steps = 0
        while current <= window.end.addingTimeInterval(86_400), steps < iterationLimit {
            steps += 1
            if let until = rule.until, current > until { break }
            produced += 1
            if let count = rule.count, produced > count { break }
            if current >= window.start, current >= event.start, !isExcluded(current, event) {
                result.append(current)
            }
            guard let next = calendar.date(byAdding: .day, value: rule.interval, to: current) else { break }
            current = next
        }
        return result
    }

    private static func weekly(
        _ event: IcsEvent,
        _ rule: RecurrenceRule,
        _ window: DateInterval,
        _ calendar: Calendar
    ) -> [Date] {
        guard let anchorWeek = calendar.dateInterval(of: .weekOfYear, for: event.start)?.start else {
            return []
        }
        let interval = max(1, rule.interval)
        var weekStart = anchorWeek
        var weekIndex = 0
        if rule.count == nil, window.start > anchorWeek {
            let gapWeeks = Int(window.start.timeIntervalSince(anchorWeek) / (7 * 86_400))
            if gapWeeks > 0 {
                let aligned = (gapWeeks / interval) * interval
                if let skipped = calendar.date(byAdding: .weekOfYear, value: aligned, to: anchorWeek) {
                    weekStart = skipped
                    weekIndex = aligned
                }
            }
        }

        let time = calendar.dateComponents([.hour, .minute, .second], from: event.start)
        let weekdays = rule.byDay.isEmpty
            ? [calendar.component(.weekday, from: event.start)]
            : rule.byDay.sorted()

        var result: [Date] = []
        var produced = 0
        var steps = 0
        while weekStart <= window.end.addingTimeInterval(7 * 86_400), steps < iterationLimit {
            steps += 1
            if weekIndex % interval == 0 {
                for weekday in weekdays {
                    guard let day = date(ofWeekday: weekday, inWeek: weekStart, calendar: calendar),
                          let occurrence = combine(day, time: time, calendar: calendar),
                          occurrence >= event.start
                    else { continue }
                    if let until = rule.until, occurrence > until { continue }
                    produced += 1
                    if let count = rule.count, produced > count { return result }
                    if occurrence >= window.start, occurrence <= window.end, !isExcluded(occurrence, event) {
                        result.append(occurrence)
                    }
                }
            }
            weekIndex += 1
            guard let nextWeek = calendar.date(byAdding: .weekOfYear, value: 1, to: weekStart) else { break }
            weekStart = nextWeek
        }
        return result
    }

    private static func monthly(
        _ event: IcsEvent,
        _ rule: RecurrenceRule,
        _ window: DateInterval,
        _ calendar: Calendar
    ) -> [Date] {
        var current = event.start
        var produced = 0
        if rule.count == nil, window.start > event.start {
            let gap = window.start.timeIntervalSince(event.start)
            let months = Int(gap / (28 * 86_400))
            let aligned = (months / max(1, rule.interval)) * max(1, rule.interval)
            if aligned > 0,
               let skipped = calendar.date(byAdding: .month, value: aligned, to: event.start) {
                current = skipped
                produced = aligned
            }
        }

        var result: [Date] = []
        var steps = 0
        while current <= window.end.addingTimeInterval(31 * 86_400), steps < iterationLimit {
            steps += 1
            if let until = rule.until, current > until { break }
            produced += 1
            if let count = rule.count, produced > count { break }
            if current >= window.start, current >= event.start, !isExcluded(current, event) {
                result.append(current)
            }
            guard let next = calendar.date(byAdding: .month, value: rule.interval, to: current) else { break }
            current = next
        }
        return result
    }

    private static func date(ofWeekday weekday: Int, inWeek weekStart: Date, calendar: Calendar) -> Date? {
        let base = calendar.component(.weekday, from: weekStart)
        var delta = weekday - base
        if delta < 0 { delta += 7 }
        return calendar.date(byAdding: .day, value: delta, to: weekStart)
    }

    private static func combine(_ day: Date, time: DateComponents, calendar: Calendar) -> Date? {
        calendar.date(
            bySettingHour: time.hour ?? 0,
            minute: time.minute ?? 0,
            second: time.second ?? 0,
            of: day
        )
    }

    private static func isExcluded(_ date: Date, _ event: IcsEvent) -> Bool {
        event.exdates.contains { abs($0.timeIntervalSince(date)) < 1 }
    }
}
