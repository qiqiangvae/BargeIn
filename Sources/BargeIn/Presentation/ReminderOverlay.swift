import SwiftUI
import BargeInCore

/// 关不掉的倒计时状态。用 @Observable 而非 @State：本机只有 CLT，SwiftUI 属性包装器宏不可用。
@MainActor
@Observable
final class OverlayState {
    private(set) var secondsLeft: Int
    /// 关闭/中断按钮的延迟解锁。
    private(set) var unlocked: Bool
    /// 覆盖层出现后 1 秒内所有按钮都不响应，避免"正在点的位置"被吞成误触。
    private(set) var interactive = false

    /// 双击确认的时间窗：两次按键之间不超过这个间隔才算一次确认。Esc（中断）与 Enter（喝了）各记一份。
    static let doublePressWindow: TimeInterval = 1

    @ObservationIgnored private var countdown: Task<Void, Never>?
    @ObservationIgnored private var lastEscapeAt: Date?
    @ObservationIgnored private var lastReturnAt: Date?

    init(dismissDelay: TimeInterval) {
        let seconds = max(0, Int(dismissDelay.rounded()))
        secondsLeft = seconds
        unlocked = seconds <= 0
    }

    func start() {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1))
            guard let self, !Task.isCancelled else { return }
            self.interactive = true
        }
        guard secondsLeft > 0 else { return }
        countdown = Task { [weak self] in
            while let self, !Task.isCancelled, self.secondsLeft > 0 {
                try? await Task.sleep(for: .seconds(1))
                guard !Task.isCancelled, self.secondsLeft > 0 else { return }
                self.secondsLeft -= 1
            }
            self?.unlocked = true
        }
    }

    func cancel() {
        countdown?.cancel()
        countdown = nil
    }

    /// 记录一次 Esc。返回 true 表示与上一次按键落在窗口内——快速按两次 = 确认中断。
    func registerEscape(now: Date = Date()) -> Bool {
        registerDoublePress(&lastEscapeAt, now: now)
    }

    /// 记录一次 Enter。返回 true 表示与上一次按键落在窗口内——快速按两次 = 确认喝了。
    func registerReturn(now: Date = Date()) -> Bool {
        registerDoublePress(&lastReturnAt, now: now)
    }

    private func registerDoublePress(_ last: inout Date?, now: Date) -> Bool {
        defer { last = now }
        guard let previous = last, now.timeIntervalSince(previous) <= Self.doublePressWindow else {
            return false
        }
        return true
    }
}

/// 覆盖层的壳：把输入整理成一份 `ThemeContext`，交给当前预设去画。
/// 这里不认识任何一套具体预设——加一套预设不需要动这个文件。
@MainActor
struct ReminderOverlay: View {
    let model: ReminderModel
    let presentation: Presentation
    let state: OverlayState
    /// 碎裂这类有自己时间线的预设由 presenter 造好递进来；其他预设为 nil。
    var animator: (any OverlayAnimator)? = nil
    var isPreview: Bool = false
    /// 每次呈现一份的随机种子；截图这类要复现的场合固定传一个值。
    var layoutSeed: UInt32 = .random(in: 0..<UInt32.max)
    let onComplete: () -> Void
    let onPostpone: () -> Void
    let onInterrupt: () -> Void

    var body: some View {
        Catalog.theme(for: presentation.preset).layout(
            ThemeContext(
                model: model,
                presentation: presentation,
                layoutSeed: layoutSeed,
                isPreview: isPreview,
                secondsLeft: state.secondsLeft,
                unlocked: state.unlocked,
                interactive: state.interactive,
                animator: animator,
                onComplete: onComplete,
                onPostpone: onPostpone,
                onInterrupt: onInterrupt
            )
        )
    }
}
