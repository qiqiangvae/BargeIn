import Foundation
import BargeInCore

/// 一条只读日历来源：一条日历地址，或一套 CalDAV 凭据连同其中被选中的日历。
/// 密码永远不在这里——它只进 Keychain。
public struct Subscription: Codable, Equatable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case ics
        case caldav
    }

    public var id: UUID
    public var kind: Kind
    public var name: String
    /// ICS：日历地址；CalDAV：服务器地址（如 `https://calendar.dingtalk.com`）。
    public var url: URL
    public var username: String?
    /// 只有 CalDAV 有：添加时发现并选定的日历集合。
    public var calendars: [CalendarRef]
    public var isEnabled: Bool
    public var lastFetchedAt: Date?
    public var lastError: FeedError?

    public init(
        id: UUID = UUID(),
        kind: Kind,
        name: String,
        url: URL,
        username: String? = nil,
        calendars: [CalendarRef] = [],
        isEnabled: Bool = true,
        lastFetchedAt: Date? = nil,
        lastError: FeedError? = nil
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.url = url
        self.username = username
        self.calendars = calendars
        self.isEnabled = isEnabled
        self.lastFetchedAt = lastFetchedAt
        self.lastError = lastError
    }

    public var dedupeKey: String {
        "\(kind.rawValue)|\(url.absoluteString)|\(username ?? "")"
    }

    /// 逐字段容错：`kind` 与 `url` 是这条来源的身份，读不出来就丢掉这一条（上层按条容错）；
    /// 其余字段缺哪补哪，别让新增字段吞掉用户已经配好的日历。
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        kind = try container.decode(Kind.self, forKey: .kind)
        url = try container.decode(URL.self, forKey: .url)
        id = container.tolerant(UUID.self, forKey: .id, or: UUID())
        name = container.tolerant(String.self, forKey: .name, or: "")
        username = container.tolerantOptional(String.self, forKey: .username)
        calendars = container.tolerantArray(CalendarRef.self, forKey: .calendars)
        isEnabled = container.tolerant(Bool.self, forKey: .isEnabled, or: true)
        lastFetchedAt = container.tolerantOptional(Date.self, forKey: .lastFetchedAt)
        lastError = container.tolerantOptional(FeedError.self, forKey: .lastError)
    }

    /// 规范化用户粘贴的地址：去空白，`webcal://` / `webcals://` 当成 `https://`，只接受 https。
    public static func normalize(_ raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }
        if text.hasPrefix("webcals://") {
            text = "https://" + text.dropFirst("webcals://".count)
        } else if text.hasPrefix("webcal://") {
            text = "https://" + text.dropFirst("webcal://".count)
        }
        if !text.contains("://") { text = "https://" + text }
        guard let url = URL(string: text),
              url.scheme?.lowercased() == "https",
              let host = url.host, !host.isEmpty
        else { return nil }
        return url
    }
}

public struct CalendarRef: Codable, Equatable, Hashable, Sendable {
    /// DAV 返回的 href，可能是绝对路径，也可能是完整 URL。
    public var href: String
    public var displayName: String

    public init(href: String, displayName: String) {
        self.href = href
        self.displayName = displayName
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        href = container.tolerant(String.self, forKey: .href, or: "")
        displayName = container.tolerant(String.self, forKey: .displayName, or: "")
    }
}

/// 取数失败的四种原因。认证、网络、格式要分开说，别让用户对着一句"网络错误"猜。
public enum FeedError: String, Codable, Error, Sendable {
    case badURL
    case auth
    case network
    case format

    public var message: String {
        switch self {
        case .badURL: "地址无效，只支持 https"
        case .auth: "认证失败，检查账号或密码"
        case .network: "连不上，数据可能已过期"
        case .format: "返回的不是日历数据"
        }
    }
}

/// 日程场景自己的业务状态：订阅、已提醒过的事件、前置分钟。
public struct ScheduleState: Codable, Equatable, Sendable {
    public var subscriptions: [Subscription]
    /// `EventKey.storageKey` → 处理时间。按天清理。
    public var handled: [String: Date]

    public init(
        subscriptions: [Subscription] = [],
        handled: [String: Date] = [:]
    ) {
        self.subscriptions = subscriptions
        self.handled = handled
    }

    /// 逐字段容错：11/12 那版存档里还没有 `subscriptions` 这个键，
    /// 以前它会让整份存档解码失败、回出厂；现在只是订阅为空。
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        subscriptions = container.tolerantArray(Subscription.self, forKey: .subscriptions)
        handled = container.tolerant([String: Date].self, forKey: .handled, or: [:])
    }

    public var hasEnabledSubscription: Bool {
        subscriptions.contains { $0.isEnabled }
    }
}

/// 日程场景给文案模板提供的变量。事件不同，值就不同，所以不能像喝水那样存在 State 上。
public enum ScheduleValues {
    public static func values(
        for event: EventOccurrence,
        now: Date,
        calendar: Calendar
    ) -> [String: String] {
        var result: [String: String] = [
            "title": event.title,
            "start": startText(event.start, calendar: calendar),
            "minutes": "\(max(0, Int((event.start.timeIntervalSince(now) / 60).rounded(.up))))",
        ]
        if let location = event.location, !location.isEmpty {
            result["location"] = location
        }
        return result
    }

    public static func startText(_ date: Date, calendar: Calendar) -> String {
        let components = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
    }
}
