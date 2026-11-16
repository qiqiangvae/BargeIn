import Foundation
import BargeInCore

/// iCalendar 里的一个 VEVENT，还没展开重复规则。
public struct IcsEvent: Equatable, Sendable {
    public var uid: String
    public var start: Date
    public var title: String
    public var location: String?
    public var rule: RecurrenceRule?
    public var exdates: [Date]
    public var isAllDay: Bool
    /// 这一条是重复事件里"被单独改期/改地点"的那一次：值是被替换掉的原始开始时刻。
    public var recurrenceID: Date?

    public init(
        uid: String,
        start: Date,
        title: String,
        location: String?,
        rule: RecurrenceRule?,
        exdates: [Date],
        isAllDay: Bool,
        recurrenceID: Date? = nil
    ) {
        self.uid = uid
        self.start = start
        self.title = title
        self.location = location
        self.rule = rule
        self.exdates = exdates
        self.isAllDay = isAllDay
        self.recurrenceID = recurrenceID
    }
}

/// 只实现"够用"的 iCalendar 子集：行折叠与转义、VEVENT、DTSTART 的三种形态、
/// RRULE 的四种字段、EXDATE。其余一律忽略，不为脏数据抛错。
public enum IcsParser {
    public static func parse(_ text: String, calendar: Calendar) -> [IcsEvent] {
        let lines = unfold(text)
        var events: [IcsEvent] = []
        var current: Builder?

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed == "BEGIN:VEVENT" {
                current = Builder()
                continue
            }
            if trimmed == "END:VEVENT" {
                if let builder = current, let event = builder.build(calendar: calendar) {
                    events.append(event)
                }
                current = nil
                continue
            }
            guard current != nil, let property = splitProperty(trimmed) else { continue }
            current?.consume(property)
        }
        return events
    }

    /// 把多段 VCALENDAR 拼起来的事件文本展开成事件发生。
    ///
    /// 钉钉这类服务器会把重复事件里被单独改期/改地点的实例也下发成独立 VEVENT：
    /// `DTSTART` 是新时间，`RECURRENCE-ID` 指向被替换的那一次。主事件按规则展开时，
    /// 被覆盖的那一次要让位给覆盖体，否则同一天会出现两行（一行还是旧时间）。
    public static func occurrences(
        from text: String,
        subscriptionID: UUID,
        window: DateInterval,
        calendar: Calendar
    ) -> [EventOccurrence] {
        let events = parse(text, calendar: calendar)
        let overridden = Set(events.compactMap(\.recurrenceID))
        var result: [EventOccurrence] = []
        var seen = Set<EventKey>()
        for event in events where !event.isAllDay {
            for start in Recurrence.occurrences(of: event, in: window, calendar: calendar) {
                if event.recurrenceID == nil, overridden.contains(start) { continue }
                let occurrence = EventOccurrence(
                    subscriptionID: subscriptionID,
                    uid: event.uid,
                    start: start,
                    title: event.title,
                    location: event.location
                )
                // 服务器把同一次发生重复下发时只留一条，别让它提醒两遍。
                if seen.insert(occurrence.key).inserted { result.append(occurrence) }
            }
        }
        return result.sorted { $0.start < $1.start }
    }

    // MARK: - 行处理

    /// RFC 5545 折行：下一行以空格或制表符开头表示续行。
    ///
    /// 先把 CRLF / CR 统一成 LF 再切：Swift 把 `\r\n` 当成**一个** Character，
    /// 直接按 `"\n"` 切会切不开 CRLF 的日历文件（钉钉、Google 都是 CRLF）。
    public static func unfold(_ text: String) -> [String] {
        let normalized = text
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var lines: [String] = []
        var buffer = ""
        for line in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix(" ") || line.hasPrefix("\t") {
                buffer += line.dropFirst()
            } else {
                if !buffer.isEmpty { lines.append(buffer) }
                buffer = String(line)
            }
        }
        if !buffer.isEmpty { lines.append(buffer) }
        return lines
    }

    struct Property {
        var name: String
        var params: [String: String]
        var value: String
    }

    static func splitProperty(_ line: String) -> Property? {
        guard let colon = line.firstIndex(of: ":") else { return nil }
        let head = String(line[line.startIndex..<colon])
        let value = String(line[line.index(after: colon)...])
        var parts = head.split(separator: ";", omittingEmptySubsequences: false).map(String.init)
        guard let name = parts.first, !name.isEmpty else { return nil }
        parts.removeFirst()
        var params: [String: String] = [:]
        for part in parts {
            let pair = part.split(separator: "=", maxSplits: 1).map(String.init)
            guard pair.count == 2 else { continue }
            var value = pair[1]
            if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
                value = String(value.dropFirst().dropLast())
            }
            params[pair[0].uppercased()] = value
        }
        return Property(name: name.uppercased(), params: params, value: value)
    }

    static func unescape(_ text: String) -> String {
        var result = ""
        var iterator = text.makeIterator()
        while let character = iterator.next() {
            guard character == "\\" else {
                result.append(character)
                continue
            }
            guard let next = iterator.next() else { break }
            switch next {
            case "n", "N": result.append("\n")
            case ",": result.append(",")
            case ";": result.append(";")
            case "\\": result.append("\\")
            default: result.append(next)
            }
        }
        return result
    }

    /// DTSTART 的三种形态：`;VALUE=DATE`（全天）、UTC 的 `Z`、带 `TZID` 或浮动本地时间。
    static func parseDate(_ value: String, params: [String: String]) -> (date: Date, isAllDay: Bool)? {
        let text = value.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return nil }
        if params["VALUE"] == "DATE" || (text.count == 8 && !text.contains("T")) {
            guard let date = formatter("yyyyMMdd", timeZone: .current).date(from: text) else { return nil }
            return (date, true)
        }
        let isUTC = text.hasSuffix("Z")
        let core = isUTC ? String(text.dropLast()) : text
        guard let timeZone = isUTC
            ? TimeZone(identifier: "UTC")
            : params["TZID"].flatMap(TimeZone.init(identifier:)) ?? .current
        else { return nil }
        guard let date = formatter("yyyyMMdd'T'HHmmss", timeZone: timeZone).date(from: core) else { return nil }
        return (date, false)
    }

    static func parseDateList(_ value: String, params: [String: String]) -> [Date] {
        value.split(separator: ",").compactMap { parseDate(String($0), params: params)?.date }
    }

    private static func formatter(_ format: String, timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = format
        formatter.timeZone = timeZone
        return formatter
    }

    // MARK: - 单条事件

    private struct Builder {
        var fields: [String: Property] = [:]
        var exdates: [Date] = []

        mutating func consume(_ property: Property) {
            if property.name == "EXDATE" {
                exdates.append(contentsOf: IcsParser.parseDateList(property.value, params: property.params))
                return
            }
            fields[property.name] = property
        }

        func build(calendar: Calendar) -> IcsEvent? {
            guard let startProperty = fields["DTSTART"],
                  let start = IcsParser.parseDate(startProperty.value, params: startProperty.params)
            else { return nil }

            let title = fields["SUMMARY"].map { IcsParser.unescape($0.value) } ?? ""
            let location = fields["LOCATION"].map { IcsParser.unescape($0.value) }
            let uid = fields["UID"].map { $0.value.trimmingCharacters(in: .whitespaces) }
                .flatMap { $0.isEmpty ? nil : $0 }
                ?? "synthetic|\(title)|\(Int(start.date.timeIntervalSince1970))"
            let rule = fields["RRULE"].flatMap { RecurrenceRule.parse($0.value) }
            let recurrenceID = fields["RECURRENCE-ID"].flatMap {
                IcsParser.parseDate($0.value, params: $0.params)?.date
            }

            return IcsEvent(
                uid: uid,
                start: start.date,
                title: title.isEmpty ? "日程" : title,
                location: location,
                rule: rule,
                exdates: exdates,
                isAllDay: start.isAllDay,
                recurrenceID: recurrenceID
            )
        }
    }
}
