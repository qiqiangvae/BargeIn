import AppKit

/// 「人在不在机器前」：只回答一个布尔，不做任何业务判断。
/// 检测失败一律当作在场——多弹一条能被看见，少弹一条没人能诊断。
@MainActor
final class Presence {
    private(set) var isPresent: Bool
    /// 从在场变成不在场 / 从不在场变回在场。
    var onBecameAbsent: (() -> Void)?
    var onBecamePresent: (() -> Void)?

    init() {
        isPresent = Self.detect()
        observeSystemEvents()
    }

    /// 会话在前台、没锁屏、至少一块屏幕醒着。
    /// 锁屏没有官方通知，`CGSSessionScreenIsLocked` 是系统会话字典里的稳定约定，不是文档化 API。
    static func detect() -> Bool {
        let session = CGSessionCopyCurrentDictionary() as? [String: Any] ?? [:]
        if (session["kCGSSessionOnConsoleKey"] as? NSNumber)?.boolValue == false { return false }
        if (session["CGSSessionScreenIsLocked"] as? NSNumber)?.boolValue == true { return false }
        return anyDisplayAwake
    }

    /// 合盖接外接屏时主屏是睡的，所以看所有在线屏幕：只要有一块醒着就算在场。
    private static var anyDisplayAwake: Bool {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(16, &ids, &count) == .success, count > 0 else { return true }
        return (0..<Int(count)).contains { CGDisplayIsAsleep(ids[$0]) == 0 }
    }

    private func observeSystemEvents() {
        let workspace = NSWorkspace.shared.notificationCenter
        let workspaceNames: [NSNotification.Name] = [
            NSWorkspace.screensDidSleepNotification,
            NSWorkspace.willSleepNotification,
            NSWorkspace.sessionDidResignActiveNotification,
            NSWorkspace.screensDidWakeNotification,
            NSWorkspace.didWakeNotification,
            NSWorkspace.sessionDidBecomeActiveNotification,
        ]
        for name in workspaceNames {
            workspace.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshNextRunLoop() }
            }
        }
        for name in ["com.apple.screenIsLocked", "com.apple.screenIsUnlocked"] {
            DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name(name), object: nil, queue: .main
            ) { [weak self] _ in
                MainActor.assumeIsolated { self?.refreshNextRunLoop() }
            }
        }
    }

    /// 通知到达时系统状态可能还没写完（锁屏通知尤其），等下一轮 runloop 再读。
    private func refreshNextRunLoop() {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    private func refresh() {
        let now = Self.detect()
        guard now != isPresent else { return }
        isPresent = now
        if now { onBecamePresent?() } else { onBecameAbsent?() }
    }
}
