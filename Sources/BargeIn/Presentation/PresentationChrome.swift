import SwiftUI
import BargeInCore

/// 一套预设里那些"动作区"长什么样。由预设自己填，公共组件照着画，
/// 公共组件因此不需要知道现在是谁在用它。
struct ChromeStyle {
    var previewFont: Font
    var secondaryColor: Color

    static let card = ChromeStyle(
        previewFont: .caption2,
        secondaryColor: .secondary
    )

    static let fullscreen = ChromeStyle(
        previewFont: .footnote,
        secondaryColor: .white.opacity(0.6)
    )

    static let shatter = ChromeStyle(
        previewFont: .system(size: 11.5),
        secondaryColor: .white.opacity(0.6)
    )
}

/// 三套预设共用的动作区：完成 / 推迟 / 倒计时提示 / 中断 / 队列 / 预览说明。
/// 这里不出现任何"现在是不是卡片"的判断——差异全部由传入的 `ChromeStyle` 表达。
@MainActor
enum PresentationChrome {
    @ViewBuilder
    static func actions(_ context: ThemeContext) -> some View {
        HStack(spacing: 12) {
            Button(action: context.onComplete) {
                Label(context.model.completionLabel, systemImage: context.model.completionSymbol)
                    .frame(minWidth: 96)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!context.interactive)
            .help("记录这次提醒（1 秒内连按两次 Enter 也可确认）")

            if context.presentation.allowsPostpone {
                Button("推迟 5 分钟", action: context.onPostpone)
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .disabled(!context.interactive)
            }

            if !context.unlocked {
                Text("\(context.secondsLeft) 秒后可关闭")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    static func pending(_ context: ThemeContext, style: ChromeStyle) -> some View {
        if context.model.pendingCount > 0 {
            Text("还有 \(context.model.pendingCount) 个提醒")
                .font(.caption)
                .foregroundStyle(style.secondaryColor)
        }
    }

    @ViewBuilder
    static func preview(_ context: ThemeContext, style: ChromeStyle) -> some View {
        if context.isPreview {
            Text("这是预览，之后到点才会这样提醒")
                .font(style.previewFont)
                .foregroundStyle(style.secondaryColor)
        }
    }

    @ViewBuilder
    static func close(_ context: ThemeContext) -> some View {
        Image(systemName: "xmark")
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(8)
            .background(.quaternary, in: Circle())
            .contentShape(Circle())
            .onTapGesture {
                if context.interactive && context.unlocked && !context.presentation.interruptNeedsHold {
                    context.onInterrupt()
                }
            }
            .onLongPressGesture(minimumDuration: 2) {
                if context.interactive && context.unlocked && context.presentation.interruptNeedsHold {
                    context.onInterrupt()
                }
            }
            .help(context.presentation.interruptNeedsHold ? "按住 2 秒中断，或双击 esc" : "单击中断，或双击 esc")
    }
}
