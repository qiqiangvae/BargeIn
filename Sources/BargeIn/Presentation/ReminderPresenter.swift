import AppKit
import SwiftUI
import BargeInCore

/// 覆盖层是"你正在看别处时突然出现"的窗口，第一次点击必须直接生效，
/// 否则会被 AppKit 当成"激活窗口"的点击吞掉。
final class ReminderHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

final class ReminderPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// 管住提醒层：每个屏幕一个面板，同一时刻只有一份。
@MainActor
final class ReminderPresenter {
    private static let escapeKeyCode: UInt16 = 53
    /// Return 与小键盘 Enter。
    private static let returnKeyCodes: Set<UInt16> = [36, 76]

    private var panels: [ReminderPanel] = []
    private var overlayState: OverlayState?
    private var keyMonitor: Any?
    private var previousApp: NSRunningApplication?
    private var animator: (any OverlayAnimator)?
    private let sound = SoundPlayer()
    private(set) var isShowing = false
    private var isPreviewing = false
    /// 碎裂退场：先播坠落，落完才关窗。
    private var isExiting = false
    private var exitTask: Task<Void, Never>?

    var onComplete: (() -> Void)?
    var onPostpone: (() -> Void)?
    var onInterrupt: (() -> Void)?
    /// 退场动画结束、窗口已关闭之后；队列里的下一条等它再出现。
    var onDismissed: (() -> Void)?

    /// `preview: true` 只呈现提醒：任何动作都只关闭，不写状态、不改账本、不动调度。
    func show(model: ReminderModel, presentation: Presentation, preview: Bool = false) {
        guard !isShowing else {
            print("[bargein] reminder skipped: already showing")
            return
        }
        isShowing = true
        isPreviewing = preview
        isExiting = false

        // 碎裂：裂开后就停住，等用户处理；退场时整片坠落。
        let theme = Catalog.theme(for: presentation.preset)
        animator = theme.makeAnimator(
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        )

        sound.start(presentation.sound)

        let state = OverlayState(dismissDelay: presentation.dismissDelay)
        state.start()
        overlayState = state

        let overlay = ReminderOverlay(
            model: model,
            presentation: presentation,
            state: state,
            animator: animator,
            isPreview: preview,
            onComplete: { [weak self] in self?.handle { $0.onComplete?() } },
            onPostpone: { [weak self] in self?.handle { $0.onPostpone?() } },
            onInterrupt: { [weak self] in self?.handle { $0.onInterrupt?() } }
        )

        print("[bargein] screens=\(NSScreen.screens.count) theme=\(presentation.preset.rawValue)")
        for screen in NSScreen.screens {
            let frame = Self.frame(for: theme.windowLayout, on: screen)
            let panel = ReminderPanel(
                contentRect: frame,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            panel.level = .screenSaver
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = theme.hasShadow
            panel.isMovable = false
            panel.hidesOnDeactivate = false
            panel.contentView = ReminderHostingView(rootView: overlay)
            panel.setFrame(frame, display: true)
            panel.orderFrontRegardless()
            panels.append(panel)
        }

        // 覆盖层必须真的拿到键盘：先激活 App，再让面板成为 key window，
        // 否则 Esc / Enter 只会落在用户原来那个 App 上。退出时把前台还回去。
        if !NSApp.isActive {
            previousApp = NSWorkspace.shared.frontmostApplication
            NSApp.activate()
        }
        panels.first?.makeKeyAndOrderFront(nil)
        installKeyMonitor()
        print("[bargein] reminder shown: \(presentation.preset.rawValue), \(panels.count) screen(s)")
    }

    /// `reactivate` 为 false 时用于队列里的下一条：别在两条提醒之间把前台还给原 App 又抢回来。
    /// 碎裂要先播完坠落再关窗，所以这里可能会晚 2 秒才收尾；锁屏/离开时走 `animated: false`，立刻收。
    func dismiss(reactivate: Bool = true, animated: Bool = true) {
        guard isShowing else { return }
        if animated, let animator, !animator.reduceMotion, !isExiting {
            isExiting = true
            removeKeyMonitor()
            animator.beginExit()
            let duration = animator.exitDuration
            exitTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(duration))
                guard let self, !Task.isCancelled else { return }
                self.finishDismiss(reactivate: reactivate)
            }
            return
        }
        finishDismiss(reactivate: reactivate)
    }

    private func finishDismiss(reactivate: Bool) {
        exitTask?.cancel()
        exitTask = nil
        isExiting = false
        removeKeyMonitor()
        animator = nil
        overlayState?.cancel()
        overlayState = nil
        sound.stop()
        panels.forEach { $0.close() }
        panels.removeAll()
        isShowing = false
        isPreviewing = false

        if reactivate {
            if let previousApp, previousApp.processIdentifier != ProcessInfo.processInfo.processIdentifier {
                previousApp.activate()
            }
            previousApp = nil
        }
        print("[bargein] reminder dismissed")
        onDismissed?()
    }

    /// Esc / Enter 走 App 级事件监听，不依赖 SwiftUI 焦点或第一响应者——
    /// 中断是应急出口，确认是主路径，都不能押在视图层级上。
    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let isEscape = event.keyCode == Self.escapeKeyCode
            guard isEscape || Self.returnKeyCodes.contains(event.keyCode) else { return event }
            // 按住不放产生的重复按键不算"第二次按键"，也不外传给响应链（避免系统提示音）。
            if event.isARepeat { return nil }
            MainActor.assumeIsolated {
                if isEscape {
                    self?.escapePressed()
                } else {
                    self?.returnPressed()
                }
            }
            return nil
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    /// 双击 Esc 中断：与预设、账本等级、解除延迟都无关，任何等级都要按两次。
    private func escapePressed() {
        // 面板还没出现时不响应：用户还没看到任何东西，不该被一个 Esc 关掉。
        if let animator, !animator.isInteractive { return }
        guard let state = overlayState, state.registerEscape() else { return }
        handle { $0.onInterrupt?() }
    }

    /// 1 秒内连按两次 Enter = 确认喝了。第一次只记录，单次误触不会记下一杯。
    private func returnPressed() {
        if let animator, !animator.isInteractive { return }
        guard let state = overlayState, state.interactive, state.registerReturn() else { return }
        handle { $0.onComplete?() }
    }

    private func handle(_ action: (ReminderPresenter) -> Void) {
        guard !isPreviewing else {
            dismiss()
            return
        }
        action(self)
    }

    private static func frame(for layout: WindowLayout, on screen: NSScreen) -> NSRect {
        switch layout {
        case .fullscreen:
            return screen.frame
        case let .corner(size: size, margin: margin):
            return NSRect(
                x: screen.frame.maxX - size.width - margin.width,
                y: screen.frame.maxY - size.height - margin.height,
                width: size.width,
                height: size.height
            )
        }
    }
}
