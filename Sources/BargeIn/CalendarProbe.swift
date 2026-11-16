import Foundation
import BargeInCore
import SceneSchedule

/// `BargeIn --calendar-probe ics <url>`
/// `BargeIn --calendar-probe caldav <server> <username> [--discover]`
///
/// 只取一次、把结果打到 stdout，用来在写界面之前确认"这条订阅到底能不能读"。
/// 密码从环境变量 `BARGEIN_PASSWORD` 读，不落盘、不进命令行历史。
enum CalendarProbe {
    static func run(_ args: [String]) -> Int32 {
        guard let index = args.firstIndex(of: "--calendar-probe"), args.count > index + 2 else {
            print("usage: --calendar-probe ics <url>")
            print("       --calendar-probe caldav <server> <username> [--discover]")
            return 2
        }

        let mode = args[index + 1]
        let password = ProcessInfo.processInfo.environment["BARGEIN_PASSWORD"] ?? ""
        let wantsDump = args.contains("--dump")
        // 顶层命令是同步的，异步结果用信号量接回来；执行完成后才读，不存在并发访问。
        final class Box: @unchecked Sendable {
            var code: Int32 = 1
        }
        let box = Box()
        let semaphore = DispatchSemaphore(value: 0)

        Task {
            defer { semaphore.signal() }
            do {
                switch mode {
                case "ics":
                    box.code = try await probeICS(args[index + 2], password: password, dump: wantsDump)
                case "file":
                    // 离线排查用：直接解析本地 .ics，确认是"取不到"还是"解析不了"。
                    let path = args[index + 2]
                    let text = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
                    print("读取 \(path) · \(text.count) 字符")
                    report(text, subscriptionID: UUID(), dump: wantsDump)
                    box.code = 0
                case "caldav":
                    guard args.count > index + 3 else {
                        print("probe: 缺少用户名")
                        return
                    }
                    box.code = try await probeCalDAV(
                        args[index + 2],
                        username: args[index + 3],
                        password: password,
                        dump: wantsDump
                    )
                default:
                    print("probe: 未知模式 \(mode)")
                }
            } catch {
                print("probe: \(describe(error))")
            }
        }

        semaphore.wait()
        return box.code
    }

    // MARK: - 一条日历地址

    private static func probeICS(_ raw: String, password: String, dump: Bool) async throws -> Int32 {
        guard let url = Subscription.normalize(raw) else {
            print("probe: 地址无效，只支持 https")
            return 2
        }
        var request = CalendarProtocol.icsRequest(url: url, username: nil, password: password.isEmpty ? nil : password)
        request.setValue("BargeIn/1.0", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw FeedError.network }
        print("GET \(url.absoluteString) → HTTP \(http.statusCode) · \(data.count) 字节")
        guard (200..<300).contains(http.statusCode) else {
            print("probe: \(http.statusCode == 401 ? "认证失败" : "请求失败")")
            return 1
        }
        let text = String(data: data, encoding: .utf8) ?? ""
        report(text, subscriptionID: UUID(), dump: dump)
        return 0
    }

    // MARK: - CalDAV

    private static func probeCalDAV(
        _ raw: String,
        username: String,
        password: String,
        dump: Bool
    ) async throws -> Int32 {
        guard let server = Subscription.normalize(raw) else {
            print("probe: 服务器地址无效，只支持 https")
            return 2
        }

        var calendars: [CalendarRef] = []
        for candidate in CalendarProtocol.discoveryRequests(server: server, username: username) {
            var request = candidate
            request.setValue("BargeIn/1.0", forHTTPHeaderField: "User-Agent")
            if !password.isEmpty {
                let token = Data("\(username):\(password)".utf8).base64EncodedString()
                request.setValue("Basic \(token)", forHTTPHeaderField: "Authorization")
            }
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let http = response as? HTTPURLResponse
            else { continue }
            print("PROPFIND \(candidate.url?.absoluteString ?? "?") → HTTP \(http.statusCode)")
            guard http.statusCode == 207 else { continue }
            let found = (try? CalendarProtocol.parseDiscovery(data, server: server)) ?? []
            if !found.isEmpty {
                calendars = found
                break
            }
        }

        guard !calendars.isEmpty else {
            print("probe: 没有发现可读的日历（401 = 账号密码不对；207 但没有日历 = 服务器形态不认识）")
            return 1
        }

        print("发现 \(calendars.count) 本日历：")
        for calendar in calendars {
            print("· \(calendar.displayName)  \(calendar.href)")
        }

        // 探测用 30 天窗口：先回答"这台日历到底有没有事件"，再谈提醒窗口。
        let window = DateInterval(start: Date().addingTimeInterval(-7 * 86_400), duration: 37 * 86_400)
        var total = 0
        for calendar in calendars {
            guard let request = CalendarProtocol.reportRequest(
                href: calendar.href,
                server: server,
                username: username,
                password: password.isEmpty ? nil : password,
                window: window
            ) else { continue }
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  let http = response as? HTTPURLResponse
            else { continue }
            print("REPORT \(calendar.displayName) → HTTP \(http.statusCode)")
            guard http.statusCode == 207 else { continue }
            let text = (try? CalendarProtocol.calendarText(fromReport: data)) ?? ""
            let vevents = text.components(separatedBy: "BEGIN:VEVENT").count - 1
            print("  calendar-data：响应 \(data.count) 字节 · VEVENT \(vevents) 条")
            if text.isEmpty {
                print("  server 返回 207 但没有 calendar-data（这个集合在当前筛选下没有资源）")
            }
            total += report(text, subscriptionID: UUID(), limit: 5, dump: dump)
        }
        return total >= 0 ? 0 : 1
    }

    // MARK: - 输出

    @discardableResult
    private static func report(
        _ text: String,
        subscriptionID: UUID,
        limit: Int = 20,
        dump: Bool = false
    ) -> Int {
        guard text.uppercased().contains("BEGIN:VCALENDAR") else {
            print("probe: 返回内容里没有 VCALENDAR（多半是登录页或错误页）")
            return 0
        }
        if dump {
            print("---- 原始 ICS 前 6000 字符 ----")
            print(String(text.prefix(6000)))
            print("---- 原始 ICS 结束 ----")
        }

        let window = DateInterval(start: Date().addingTimeInterval(-7 * 86_400), duration: 37 * 86_400)
        let lines = IcsParser.unfold(text)
        let beginCount = lines.filter { $0.trimmingCharacters(in: .whitespaces) == "BEGIN:VEVENT" }.count
        print("展开后 \(lines.count) 行 · BEGIN:VEVENT \(beginCount) 处")

        let parsed = IcsParser.parse(text, calendar: .current)
        print("解析出 \(parsed.count) 条 VEVENT：")
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.dateFormat = "MM-dd HH:mm"
        for event in parsed.prefix(10) {
            let flags = [
                event.isAllDay ? "全天" : nil,
                event.rule == nil ? nil : "重复 \(event.rule!.frequency.rawValue)",
            ].compactMap { $0 }.joined(separator: " · ")
            let expanded = event.isAllDay
                ? 0
                : Recurrence.occurrences(of: event, in: window, calendar: .current).count
            print("  · \(formatter.string(from: event.start))  \(event.title)  [\(flags.isEmpty ? "单次" : flags)] 窗口内 \(expanded) 次")
        }

        let events = IcsParser.occurrences(
            from: text,
            subscriptionID: subscriptionID,
            window: window,
            calendar: .current
        )
        print("\(events.count) 个事件发生（前后 37 天）：")
        for event in events.prefix(limit) {
            print("· \(formatter.string(from: event.start))  \(event.title)")
        }
        return events.count
    }

    private static func describe(_ error: Error) -> String {
        if let feed = error as? FeedError { return feed.message }
        return error.localizedDescription
    }
}
