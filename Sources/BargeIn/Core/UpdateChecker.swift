import AppKit
import Foundation
import Observation

/// 自动更新：只向 GitHub Releases 问一次「最新正式版是哪个」，不发送任何本机数据。
/// 检查与下载都只在用户开着「自动检查更新」或亲手点检查 / 更新时发生。
@MainActor
@Observable
final class UpdateChecker {
    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case available(Release)
        case downloading(version: String, received: Int64, total: Int64)
        case installing(version: String)
        case failed(String)
    }

    struct Release: Equatable, Sendable {
        var version: String
        var downloadURL: URL
        /// 发布页：想看完整发布说明时去这里。
        var pageURL: URL
        /// 这次更新了什么：发布说明里的第一个小标题；没有就用发布名。设置里的版本卡显示它。
        var summary: String?
    }

    private enum UpdateError: Error {
        case server(Int)
        case noAsset
        case notInstalled
        case noPermission(String)
        case invalidBundle
        case commandFailed
    }

    private static let releasesPageString = "https://github.com/qiqiangvae/BargeIn/releases"
    private static let releasesFeed = URL(string: releasesPageString + ".atom")!
    static let releasesPage = URL(string: releasesPageString + "/latest")!
    static let bundleIdentifier = "com.bargein.app"
    static let bundleName = "Barge In.app"

    private(set) var status: Status = .idle
    /// 打包后的 App 才读得到版本号；`swift run` 这类裸二进制不检查也不安装。
    let currentVersion: String?

    private let store: StateStore
    private var autoTimers: [Timer] = []
    private var downloadTask: URLSessionDownloadTask?
    private var pendingRelease: Release?

    /// 自动检查发现有新版本；设置里的手动检查不触发它。
    var onFoundNewVersion: ((Release) -> Void)?

    init(store: StateStore, currentVersion: String? = nil) {
        self.store = store
        self.currentVersion = currentVersion
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
    }

    var isSupported: Bool { currentVersion != nil }

    /// 启动路径：稍等一下再查，别和首启窗口抢时间。
    func start() {
        guard store.state.checkForUpdates, isSupported else { return }
        let first = Timer(timeInterval: 8, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.check(notify: true) }
        }
        first.tolerance = 5
        RunLoop.main.add(first, forMode: .common)
        autoTimers = [first]
        scheduleDaily()
    }

    /// 设置里的开关。打开时当场查一次，之后每 24 小时一次；关掉立刻停表。
    func setAutoCheck(_ enabled: Bool) {
        stopAutoCheck()
        guard enabled, isSupported else { return }
        check(notify: true)
        scheduleDaily()
    }

    private func stopAutoCheck() {
        autoTimers.forEach { $0.invalidate() }
        autoTimers.removeAll()
    }

    private func scheduleDaily() {
        let daily = Timer(timeInterval: 86_400, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.check(notify: true) }
        }
        daily.tolerance = 600
        RunLoop.main.add(daily, forMode: .common)
        autoTimers.append(daily)
    }

    func check(notify: Bool = false) {
        guard isSupported, status != .checking, !isBusy else { return }
        Task { await runCheck(notify: notify) }
    }

    func downloadAndInstall(_ release: Release) {
        guard isSupported, downloadTask == nil else { return }
        pendingRelease = release
        status = .downloading(version: release.version, received: 0, total: 0)
        let task = session.downloadTask(with: release.downloadURL)
        downloadTask = task
        task.resume()
    }

    /// 只给 `--snapshot` 用：不发请求也能渲染版本卡的几种样子。
    func setStatusForSnapshot(_ status: Status) {
        self.status = status
    }

    // MARK: - 检查

    private func runCheck(notify: Bool) async {
        status = .checking
        do {
            let release = try await fetchLatest()
            guard let currentVersion else {
                status = .upToDate
                return
            }
            if Self.isNewer(release.version, than: currentVersion) {
                print("[bargein] update available: \(release.version) · \(release.summary ?? "无摘要")")
                status = .available(release)
                if notify { onFoundNewVersion?(release) }
            } else {
                print("[bargein] update check: up to date (\(currentVersion))")
                status = .upToDate
            }
        } catch {
            print("[bargein] update check failed: \(error)")
            status = .failed(Self.message(for: error))
        }
    }

    /// 读 GitHub 的 releases atom：一次拿到最新版本、发布页与发布说明。
    /// 不走 API（未登录的 API 每小时只有 60 次，共享出口 IP 很容易被限流），也不拉整个发布页。
    private func fetchLatest() async throws -> Release {
        var request = URLRequest(url: Self.releasesFeed)
        request.timeoutInterval = 20
        request.setValue("BargeIn/\(currentVersion ?? "dev")", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw UpdateError.server(0) }
        guard http.statusCode == 200 else { throw UpdateError.server(http.statusCode) }
        guard let release = Self.release(fromFeed: data) else { throw UpdateError.noAsset }
        return release
    }

    /// atom 的第一条就是最新正式版；安装包名由发布流程固定：`Barge-In-<版本>-macos-arm64.zip`。
    static func release(fromFeed data: Data) -> Release? {
        let feed = ReleaseFeedParser()
        let parser = XMLParser(data: data)
        parser.delegate = feed
        guard parser.parse(), let entry = feed.first else { return nil }
        guard let link = entry.link,
              let tag = link.split(separator: "/").last,
              tag.hasPrefix("v")
        else { return nil }
        let version = String(tag.dropFirst())
        guard !version.isEmpty,
              let pageURL = URL(string: link),
              let downloadURL = URL(string: "\(releasesPageString)/download/\(tag)/Barge-In-\(version)-macos-arm64.zip")
        else { return nil }
        return Release(
            version: version,
            downloadURL: downloadURL,
            pageURL: pageURL,
            summary: summary(from: entry.contentHTML, title: entry.title, version: version)
        )
    }

    /// 发布说明里的第一个小标题最接近"这次更新了什么"；没有标题就用发布名。
    /// 发布流程约定：正文用 `## …` 开头写这次改了什么，标题不要只写版本号。
    static func summary(from html: String?, title: String?, version: String) -> String? {
        if let html, !html.isEmpty,
           let heading = firstHeading(in: html) {
            return heading
        }
        if let title, !title.isEmpty, title != "Barge In \(version)" {
            return title
        }
        return nil
    }

    private static func firstHeading(in html: String) -> String? {
        guard let regex = try? NSRegularExpression(
            pattern: "<h[1-3][^>]*>(.*?)</h[1-3]>",
            options: [.caseInsensitive, .dotMatchesLineSeparators]
        ) else { return nil }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        guard let match = regex.firstMatch(in: html, range: range),
              let inner = Range(match.range(at: 1), in: html) else { return nil }
        let text = String(html[inner])
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? nil : text
    }

    /// 逐段比较数字：`0.4.10` 比 `0.4.9` 新，`v0.5.0` 与 `0.5.0` 同版。
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let left = versionComponents(candidate)
        let right = versionComponents(current)
        for index in 0..<max(left.count, right.count) {
            let a = index < left.count ? left[index] : 0
            let b = index < right.count ? right[index] : 0
            if a != b { return a > b }
        }
        return false
    }

    private static func versionComponents(_ raw: String) -> [Int] {
        var text = raw.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("v") || text.hasPrefix("V") { text.removeFirst() }
        return text.split(separator: ".").map { Int($0.prefix { $0.isNumber }) ?? 0 }
    }

    // MARK: - 下载与安装

    @ObservationIgnored private lazy var session: URLSession = {
        let delegate = UpdateDownloadDelegate()
        delegate.onProgress = { [weak self] received, total in
            guard let self else { return }
            self.status = .downloading(
                version: self.pendingRelease?.version ?? "",
                received: received,
                total: total
            )
        }
        delegate.onFinish = { [weak self] result in self?.finishDownload(result) }
        return URLSession(configuration: .default, delegate: delegate, delegateQueue: .main)
    }()

    private var isBusy: Bool {
        if downloadTask != nil { return true }
        switch status {
        case .downloading, .installing: return true
        default: return false
        }
    }

    private func finishDownload(_ result: Result<URL, Error>) {
        downloadTask = nil
        guard let release = pendingRelease else { return }
        pendingRelease = nil
        switch result {
        case let .success(zip):
            install(zip: zip, release: release)
        case let .failure(error):
            status = .failed(Self.message(for: error))
        }
    }

    /// 装到当前 bundle 所在目录：解包 → 校验版本与签名 → 交给一段脚本等本进程退出后替换并重开。
    private func install(zip: URL, release: Release) {
        status = .installing(version: release.version)
        do {
            let bundle = Bundle.main.bundleURL
            guard bundle.pathExtension == "app" else { throw UpdateError.notInstalled }
            let parent = bundle.deletingLastPathComponent()
            let token = String(UUID().uuidString.prefix(8))
            let work = parent.appendingPathComponent(".bargein-update-\(token)", isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: work, withIntermediateDirectories: false)
            } catch {
                throw UpdateError.noPermission(parent.path)
            }

            var handedToInstaller = false
            defer {
                // 安装脚本会自己清；走到失败分支时由这里收拾半成品。
                if !handedToInstaller { try? FileManager.default.removeItem(at: work) }
            }

            let unpacked = work.appendingPathComponent("unpacked", isDirectory: true)
            try run("/usr/bin/ditto", ["-x", "-k", zip.path, unpacked.path])
            let staged = unpacked.appendingPathComponent(Self.bundleName)
            try validate(staged, version: release.version)

            let stash = parent.appendingPathComponent(".bargein-old-\(token).app")
            try launchInstaller(work: work, bundle: bundle, staged: staged, stash: stash)
            handedToInstaller = true
            NSApp.terminate(nil)
        } catch {
            status = .failed(Self.message(for: error))
        }
    }

    private func validate(_ app: URL, version: String) throws {
        let plist = app.appendingPathComponent("Contents/Info.plist")
        guard let info = NSDictionary(contentsOf: plist) as? [String: Any],
              info["CFBundleIdentifier"] as? String == Self.bundleIdentifier,
              info["CFBundleShortVersionString"] as? String == version
        else { throw UpdateError.invalidBundle }
        // ad-hoc 签名也能过 codesign --verify；这一步只挡坏包，不当公证用。
        try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path])
    }

    /// 脚本排在当前进程退出之后动手：先移走旧 bundle，再把新 bundle 放到原位；
    /// 中途失败就还原并重新打开旧版本，最坏也只是更新没成功。
    private func launchInstaller(work: URL, bundle: URL, staged: URL, stash: URL) throws {
        let script = work.appendingPathComponent("install.sh")
        let text = """
        #!/bin/sh
        pid="$1"; bundle="$2"; staged="$3"; stash="$4"; work="$5"
        while /bin/kill -0 "$pid" 2>/dev/null; do /bin/sleep 0.2; done
        /bin/rm -rf "$stash"
        if ! /bin/mv "$bundle" "$stash"; then
          /usr/bin/open -n "$bundle"
          exit 1
        fi
        if ! /bin/mv "$staged" "$bundle"; then
          /bin/mv "$stash" "$bundle"
          /usr/bin/open -n "$bundle"
          exit 1
        fi
        /usr/bin/xattr -dr com.apple.quarantine "$bundle" >/dev/null 2>&1
        /usr/bin/open -n "$bundle"
        /bin/rm -rf "$stash" "$work"
        """
        try text.write(to: script, atomically: true, encoding: .utf8)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = [script.path, String(getpid()), bundle.path, staged.path, stash.path, work.path]
        try process.run()
    }

    private func run(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw UpdateError.commandFailed }
    }

    // MARK: - 文案

    static func message(for error: Error) -> String {
        if error is URLError { return "连不上 GitHub，检查网络后再试" }
        switch error {
        case let UpdateError.server(code):
            return code == 404 ? "还没有发布版本可查" : "GitHub 返回 \(code)，稍后再试"
        case UpdateError.noAsset:
            return "没读到可用的新版本信息，稍后再试"
        case UpdateError.notInstalled:
            return "当前不是打包好的 App，没法自动安装；去 Releases 手动下载"
        case let UpdateError.noPermission(path):
            return "没有写入 \(path) 的权限；去 Releases 手动下载"
        case UpdateError.invalidBundle:
            return "下载的安装包没通过校验，已放弃安装"
        case UpdateError.commandFailed:
            return "解压或校验安装包失败，已放弃安装"
        default:
            return "下载失败，稍后再试"
        }
    }

}

/// 只取 atom 的第一条 entry。
private final class ReleaseFeedParser: NSObject, XMLParserDelegate {
    struct Entry {
        var link: String?
        var title: String?
        var contentHTML: String?
    }

    private(set) var first: Entry?
    private var current: Entry?
    private var buffer = ""
    private var inEntry = false

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?,
        attributes attributeDict: [String: String] = [:]
    ) {
        switch elementName {
        case "entry":
            guard first == nil else { return }
            inEntry = true
            current = Entry()
        case "link":
            if inEntry, attributeDict["rel"] == "alternate" {
                current?.link = attributeDict["href"]
            }
        case "title", "content":
            buffer = ""
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        buffer += string
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName: String?
    ) {
        switch elementName {
        case "title":
            if inEntry { current?.title = buffer }
        case "content":
            if inEntry { current?.contentHTML = buffer }
        case "entry":
            if inEntry {
                first = current
                current = nil
                inEntry = false
            }
        default:
            break
        }
        buffer = ""
    }
}

/// 下载进度与结果都排在主队列上，所以这里可以直接断言主线程。
private final class UpdateDownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    var onProgress: ((Int64, Int64) -> Void)?
    var onFinish: ((Result<URL, Error>) -> Void)?

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let progress = onProgress
        MainActor.assumeIsolated { progress?(totalBytesWritten, totalBytesExpectedToWrite) }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // 这个临时文件一出这个方法就会被删，先搬到一个稳定的位置。
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("BargeIn-update-\(UUID().uuidString).zip")
        let finish = onFinish
        do {
            try FileManager.default.moveItem(at: location, to: destination)
            MainActor.assumeIsolated { finish?(.success(destination)) }
        } catch {
            MainActor.assumeIsolated { finish?(.failure(error)) }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let error else { return }
        let finish = onFinish
        MainActor.assumeIsolated { finish?(.failure(error)) }
    }
}
