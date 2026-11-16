import AppKit
import SwiftUI
import BargeInCore

/// 设置界面的一次性窗口持有者。
@MainActor
final class SettingsWindowController {
    private static let escapeKeyCode: UInt16 = 53
    private static let width: CGFloat = 640
    /// 窗口高度固定：切 tab 时只换页面内容，不换窗口高度。
    /// 730 是按喝水默认页（727）取的，再高只是多留白。
    private static let height: CGFloat = 730

    private var window: NSWindow?
    private var model: SettingsModel?
    private var escapeMonitor: Any?

    var isVisible: Bool { window?.isVisible ?? false }

    func close() {
        removeEscapeMonitor()
        window?.close()
        window = nil
        model = nil
    }

    func show(
        store: StateStore,
        engine: ReminderEngine,
        feeds: FeedService,
        updates: UpdateChecker,
        onboarding: Bool,
        page: SettingsModel.Page? = nil,
        onPreview: @escaping (SceneID, PresetInstance) -> Void,
        onFinishOnboarding: @escaping () -> Void
    ) {
        if let window {
            if let page { model?.selectPage(page) }
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }

        let model = SettingsModel(store: store, onboarding: onboarding, page: page ?? .scene)
        let hosting = NSHostingController(
            rootView: SettingsView(
                store: store,
                engine: engine,
                feeds: feeds,
                updates: updates,
                model: model,
                onPreview: onPreview,
                onFinishOnboarding: onFinishOnboarding
            )
        )
        // 窗口尺寸由我们自己定；不这样的话 SwiftUI 会按内容高度改窗口，切 tab 就跳。
        hosting.sizingOptions = []
        let window = NSWindow(contentViewController: hosting)
        window.title = "Barge In"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: Self.width, height: Self.height))
        window.center()
        self.window = window
        self.model = model

        installEscapeMonitor(for: window)

        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Esc 走 App 级事件监听，不依赖 SwiftUI 焦点或第一响应者，与本 App 的提醒层同一套路子。
    private func installEscapeMonitor(for window: NSWindow) {
        removeEscapeMonitor()
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.keyCode == Self.escapeKeyCode, event.window === window else { return event }
            if event.isARepeat { return nil }
            MainActor.assumeIsolated { self.escapePressed() }
            return nil
        }
    }

    private func removeEscapeMonitor() {
        if let escapeMonitor { NSEvent.removeMonitor(escapeMonitor) }
        escapeMonitor = nil
    }

    /// 逐级退：先收编辑面板，再关窗。
    private func escapePressed() {
        guard let model else { return }
        switch model.escape {
        case .closeEditor: model.editingID = nil
        case .closeWindow: close()
        }
    }
}
