import AppKit
import Foundation
import Observation
import BargeInCore
import SceneSchedule

/// 订阅取数：启动、每 30 分钟、唤醒、手动各刷一次。
/// 失败不删事件——宁可拿过期数据提醒，也不要因为网络把一条日程静默抹掉。
@MainActor
@Observable
final class FeedService {
    static let refreshInterval: TimeInterval = 30 * 60
    static let backoffInterval: TimeInterval = 4 * 60 * 60

    private(set) var isRefreshing = false

    @ObservationIgnored private let store: StateStore
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private var parsed: [UUID: [EventOccurrence]] = [:]
    @ObservationIgnored private var failures: [UUID: Int] = [:]
    @ObservationIgnored private var nextAttempt: [UUID: Date] = [:]
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var started = false
    @ObservationIgnored var onEventsChanged: (() -> Void)?

    init(store: StateStore) {
        self.store = store
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        self.session = URLSession(configuration: configuration)
    }

    var cacheDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent("BargeIn/subscriptions", isDirectory: true)
    }

    /// 窗口与 FirePlan 对齐：前几天（补提醒）+ 未来 8 天。只在里面展开。
    static func window(now: Date = Date()) -> DateInterval {
        DateInterval(
            start: now.addingTimeInterval(-86_400),
            duration: Double(FirePlan.maxLookaheadDays) * 86_400
        )
    }

    func start() {
        guard !started else { return }
        started = true
        loadCache()
        installWakeObserver()
        scheduleTimer()
        Task { await refreshAll() }
    }

    func scheduleTimer() {
        timer?.invalidate()
        let timer = Timer(timeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in await self?.refreshAll() }
        }
        timer.tolerance = 60
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    // MARK: - 刷新

    func refreshAll(force: Bool = false) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        for subscription in store.subscriptions where subscription.isEnabled {
            if !force, let next = nextAttempt[subscription.id], Date() < next { continue }
            await refresh(subscription)
        }
        pushEvents()
        onEventsChanged?()
    }

    func refresh(_ subscription: Subscription, force: Bool = false) async {
        if !force, let next = nextAttempt[subscription.id], Date() < next { return }
        let window = Self.window()
        do {
            let text = try await fetchText(for: subscription, window: window)
            let events = parse(text, subscription: subscription, window: window)
            try? write(text, for: subscription.id)
            parsed[subscription.id] = events
            failures[subscription.id] = 0
            nextAttempt[subscription.id] = Date().addingTimeInterval(Self.refreshInterval)
            store.markSynced(subscription.id)
        } catch {
            let failure = failures[subscription.id, default: 0] + 1
            failures[subscription.id] = failure
            nextAttempt[subscription.id] = Date().addingTimeInterval(Self.backoffInterval)
            store.setFeedError(mapError(error), for: subscription.id)
            // 保留上一次成功的事件与缓存，只在界面上标注过期。
        }
        pushEvents()
        onEventsChanged?()
    }

    /// 删掉一条订阅后，把它留下的事件、失败计数与退避一并清掉。
    func forget(_ id: UUID) {
        parsed[id] = nil
        failures[id] = nil
        nextAttempt[id] = nil
        pushEvents()
        onEventsChanged?()
    }

    // MARK: - 添加订阅

    /// 一次性验证一条日历地址，成功才让用户保存。
    func connectICS(urlText: String, username: String, password: String) async throws -> Subscription {
        guard let url = Subscription.normalize(urlText) else { throw FeedError.badURL }
        let name = url.host ?? "日历"
        var subscription = Subscription(kind: .ics, name: name, url: url)
        subscription.username = username.isEmpty ? nil : username
        let window = Self.window()
        let text = try await fetchText(for: subscription, password: password, window: window)
        let events = parse(text, subscription: subscription, window: window)
        guard !events.isEmpty || text.uppercased().contains("BEGIN:VCALENDAR") else { throw FeedError.format }
        return subscription
    }

    /// CalDAV：先发现日历集合，交给用户勾选。
    func discover(serverText: String, username: String, password: String) async throws -> (URL, [CalendarRef]) {
        guard let server = Subscription.normalize(serverText) else { throw FeedError.badURL }
        var sawAuthFailure = false
        for candidate in CalendarProtocol.discoveryRequests(server: server, username: username) {
            var request = candidate
            if !password.isEmpty {
                let token = Data("\(username):\(password)".utf8).base64EncodedString()
                request.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")
            }
            request.setValue("BargeIn/1.0", forHTTPHeaderField: "User-Agent")
            guard let (data, response) = try? await session.data(for: request),
                  let http = response as? HTTPURLResponse
            else { continue }
            switch http.statusCode {
            case 207:
                let calendars = (try? CalendarProtocol.parseDiscovery(data, server: server)) ?? []
                if !calendars.isEmpty {
                    return (server, calendars)
                }
            case 401, 403:
                // 某些服务器对 well-known 一律 401，别在这里就下结论，继续试真正的 home set。
                sawAuthFailure = true
            default:
                continue
            }
        }
        throw sawAuthFailure ? FeedError.auth : FeedError.format
    }

    /// 保存后立刻拉一次，让用户马上看到事件数。
    func finishCalDAV(
        server: URL,
        username: String,
        password: String,
        name: String,
        calendars: [CalendarRef]
    ) async throws -> Subscription {
        let subscription = Subscription(
            kind: .caldav,
            name: name.isEmpty ? (server.host ?? "日历") : name,
            url: server,
            username: username,
            calendars: calendars
        )
        let window = Self.window()
        let text = try await fetchText(for: subscription, password: password, window: window)
        _ = parse(text, subscription: subscription, window: window)
        return subscription
    }

    // MARK: - 缓存

    func loadCache() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: cacheDirectory,
            includingPropertiesForKeys: nil
        ) else { return }
        let window = Self.window()
        for file in files where file.pathExtension == "ics" {
            guard let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent),
                  let text = try? String(contentsOf: file, encoding: .utf8),
                  let subscription = store.subscriptions.first(where: { $0.id == id })
            else { continue }
            parsed[id] = parse(text, subscription: subscription, window: window)
        }
        pushEvents()
    }

    private func write(_ text: String, for id: UUID) throws {
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
        let file = cacheDirectory.appendingPathComponent("\(id.uuidString).ics")
        try text.write(to: file, atomically: true, encoding: .utf8)
    }

    // MARK: - 内部

    private func parse(
        _ text: String,
        subscription: Subscription,
        window: DateInterval
    ) -> [EventOccurrence] {
        IcsParser.occurrences(
            from: text,
            subscriptionID: subscription.id,
            window: window,
            calendar: .current
        )
    }

    private func pushEvents() {
        let all = parsed.values.flatMap { $0 }.sorted { $0.start < $1.start }
        store.setEvents(all)
    }

    private func fetchText(
        for subscription: Subscription,
        password: String? = nil,
        window: DateInterval
    ) async throws -> String {
        let secret = password ?? Keychain.password(for: subscription.id)
        switch subscription.kind {
        case .ics:
            let request = CalendarProtocol.icsRequest(
                url: subscription.url,
                username: subscription.username,
                password: secret
            )
            let (data, response) = try await session.data(for: request)
            try validate(response, allowHTML: false)
            return String(data: data, encoding: .utf8) ?? ""
        case .caldav:
            var chunks: [String] = []
            for calendar in subscription.calendars {
                guard let request = CalendarProtocol.reportRequest(
                    href: calendar.href,
                    server: subscription.url,
                    username: subscription.username,
                    password: secret,
                    window: window
                ) else { throw FeedError.format }
                let (data, response) = try await session.data(for: request)
                guard let http = response as? HTTPURLResponse else { throw FeedError.network }
                switch http.statusCode {
                case 207:
                    chunks.append(try CalendarProtocol.calendarText(fromReport: data))
                case 401, 403:
                    throw FeedError.auth
                default:
                    throw FeedError.network
                }
            }
            guard !chunks.isEmpty else { throw FeedError.format }
            return chunks.joined(separator: "\r\n")
        }
    }

    private func validate(_ response: URLResponse, allowHTML: Bool) throws {
        guard let http = response as? HTTPURLResponse else { throw FeedError.network }
        switch http.statusCode {
        case 200..<300:
            break
        case 401, 403:
            throw FeedError.auth
        default:
            throw FeedError.network
        }
        let contentType = (http.value(forHTTPHeaderField: "Content-Type") ?? "").lowercased()
        if !allowHTML, contentType.contains("text/html") { throw FeedError.format }
    }

    private func mapError(_ error: Error) -> FeedError {
        if let feed = error as? FeedError { return feed }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .userAuthenticationRequired, .noPermissionsToReadFile:
                return .auth
            default:
                return .network
            }
        }
        return .network
    }

    private func installWakeObserver() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                await self?.refreshAll(force: true)
            }
        }
    }
}
