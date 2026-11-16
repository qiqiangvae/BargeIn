import Foundation

/// 两种传输的请求构造与响应解析。网络调用留给 App 层：这里只管"发什么、怎么读"。
public enum CalendarProtocol {
    /// 取一条日历地址。看似多余，但把 URLSession 挡在外面，解析与协议就能单独检查。
    public static func icsRequest(url: URL, username: String?, password: String?) -> URLRequest {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        authorize(&request, username: username, password: password)
        return request
    }

    /// CalDAV 发现：不同服务器的 home set 位置不一样，挨个试。
    /// 钉钉固定是 `/dav/{username}/`；其余先试 well-known，再试根路径。
    public static func discoveryRequests(server: URL, username: String) -> [URLRequest] {
        var urls: [URL] = []
        let base = server.absoluteString.hasSuffix("/") ? server.absoluteString : server.absoluteString + "/"
        if let url = URL(string: base + ".well-known/caldav") { urls.append(url) }
        if let url = URL(string: base) { urls.append(url) }
        if let encoded = username.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) {
            if let url = URL(string: base + "dav/" + encoded + "/") { urls.append(url) }
            if let url = URL(string: base + "dav/users/" + encoded + "/") { urls.append(url) }
        }

        let body = """
        <?xml version="1.0" encoding="utf-8"?>
        <d:propfind xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav" xmlns:cs="http://calendarserver.org/ns/">
          <d:prop>
            <d:resourcetype/>
            <d:displayname/>
            <c:supported-calendar-component-set/>
            <cs:getctag/>
          </d:prop>
        </d:propfind>
        """
        return urls.map { url in
            var request = URLRequest(url: url)
            request.httpMethod = "PROPFIND"
            request.httpBody = Data(body.utf8)
            request.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
            request.setValue("1", forHTTPHeaderField: "Depth")
            return request
        }
    }

    /// 拉某个日历集合在窗口内的事件。回来的是 ICS 文本，交给同一个解析器。
    public static func reportRequest(
        href: String,
        server: URL,
        username: String?,
        password: String?,
        window: DateInterval
    ) -> URLRequest? {
        guard let url = resolve(href, server: server) else { return nil }
        let body = """
        <?xml version="1.0" encoding="utf-8"?>
        <c:calendar-query xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:caldav">
          <d:prop>
            <d:getetag/>
            <c:calendar-data/>
          </d:prop>
          <c:filter>
            <c:comp-filter name="VCALENDAR">
              <c:comp-filter name="VEVENT">
                <c:time-range start="\(stamp(window.start))" end="\(stamp(window.end))"/>
              </c:comp-filter>
            </c:comp-filter>
          </c:filter>
        </c:calendar-query>
        """
        var request = URLRequest(url: url)
        request.httpMethod = "REPORT"
        request.httpBody = Data(body.utf8)
        request.setValue("application/xml; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("1", forHTTPHeaderField: "Depth")
        authorize(&request, username: username, password: password)
        return request
    }

    /// 从 207 响应里把每段 calendar-data 拼起来。
    public static func calendarText(fromReport data: Data) throws -> String {
        let responses = try responses(in: data)
        let payloads = responses.compactMap { $0.calendarData }.filter { !$0.isEmpty }
        guard !payloads.isEmpty else { return "" }
        return payloads.joined(separator: "\r\n")
    }

    public static func parseDiscovery(_ data: Data, server: URL) throws -> [CalendarRef] {
        let responses = try responses(in: data)
        let typed = responses.filter { $0.isCalendar && $0.href != nil }
        let chosen = typed.isEmpty ? responses.filter { $0.href != nil } : typed
        return chosen.compactMap { response -> CalendarRef? in
            guard let href = response.href, !href.isEmpty else { return nil }
            let name = (response.displayName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !isAuxiliary(name: name, href: href) else { return nil }
            return CalendarRef(href: href, displayName: name.isEmpty ? fallbackName(href) : name)
        }
    }

    static func resolve(_ href: String, server: URL) -> URL? {
        if href.hasPrefix("http://") || href.hasPrefix("https://") { return URL(string: href) }
        if href.hasPrefix("/") {
            var components = URLComponents(url: server, resolvingAgainstBaseURL: false)
            components?.path = href
            components?.query = nil
            return components?.url
        }
        return URL(string: href, relativeTo: server)?.absoluteURL
    }

    // MARK: - 内部

    private static func authorize(_ request: inout URLRequest, username: String?, password: String?) {
        request.setValue("BargeIn/1.0", forHTTPHeaderField: "User-Agent")
        guard let username, let password, !username.isEmpty else { return }
        let token = Data("\(username):\(password)".utf8).base64EncodedString()
        request.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")
    }

    private static func stamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyyMMdd'T'HHmmss'Z'"
        return formatter.string(from: date)
    }

    private static func fallbackName(_ href: String) -> String {
        let trimmed = href.hasSuffix("/") ? String(href.dropLast()) : href
        let name = trimmed.split(separator: "/").last.map(String.init) ?? "日历"
        return name.isEmpty ? "日历" : name
    }

    private static func isAuxiliary(name: String, href: String) -> Bool {
        let haystacks = [name.lowercased(), href.lowercased()]
        return haystacks.contains { text in
            text.contains("outbox") || text.contains("inbox") || text.contains("notifications")
        }
    }

    private static func responses(in data: Data) throws -> [DavResponse] {
        let delegate = DavDelegate()
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.delegate = delegate
        guard parser.parse() else { throw FeedError.format }
        return delegate.responses
    }
}

struct DavResponse {
    var href: String?
    var displayName: String?
    var isCalendar = false
    var calendarData: String?
}

/// 只认四个元素：response / href / displayname / calendar-data，外加 resourcetype 里的 calendar。
private final class DavDelegate: NSObject, XMLParserDelegate {
    var responses: [DavResponse] = []
    private var current: DavResponse?
    private var buffer = ""
    private var capture: String?

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes: [String: String] = [:]
    ) {
        switch elementName {
        case "response":
            current = DavResponse()
        case "calendar":
            current?.isCalendar = true
        case "href", "displayname", "calendar-data":
            buffer = ""
            capture = elementName
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard capture != nil else { return }
        buffer += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?
    ) {
        switch elementName {
        case "response":
            if let current { responses.append(current) }
            current = nil
        case "href":
            if capture == "href" { current?.href = buffer.trimmingCharacters(in: .whitespacesAndNewlines) }
            capture = nil
        case "displayname":
            if capture == "displayname" { current?.displayName = buffer }
            capture = nil
        case "calendar-data":
            if capture == "calendar-data" { current?.calendarData = buffer }
            capture = nil
        default:
            break
        }
    }
}
