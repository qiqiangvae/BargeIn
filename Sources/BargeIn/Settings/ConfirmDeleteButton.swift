import SwiftUI

/// 删除入口一律两段式：第一下把垃圾桶换成「确认删除」，第二下才真正删除。
/// 确认态由 SettingsModel 集中持有，点别的删除入口或切页即复位，同一时刻只有一个。
struct ConfirmDeleteButton: View {
    enum Form {
        /// 预设卡片动作行里的小方块，撑满剩余宽度。
        case compact
        /// 订阅行尾的小图标。
        case plain
        /// 时刻行的圆钮。
        case circle
        /// 列表行尾的安静入口：默认只是灰色图标，确认时才转危险色。
        case quiet
    }

    let form: Form
    /// 无障碍名与悬停提示，确认后换成「确认删除」。
    let label: String
    let confirming: Bool
    let onArm: () -> Void
    let action: () -> Void

    var body: some View {
        Button {
            if confirming {
                action()
            } else {
                onArm()
            }
        } label: {
            if confirming {
                confirmFace
            } else {
                iconFace
            }
        }
        .buttonStyle(PressableStyle(scale: 0.9))
        .help(confirming ? "再点一次删除" : label)
        .accessibilityLabel(confirming ? "确认删除" : label)
    }

    private var confirmFace: some View {
        Text("确认删除")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Theme.danger)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 6)
            .frame(height: 22)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Theme.danger.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(Theme.danger.opacity(0.45), lineWidth: 1)
            )
            .contentShape(Rectangle())
    }

    @ViewBuilder
    private var iconFace: some View {
        switch form {
        case .compact:
            trash(size: 11.5)
                .frame(maxWidth: .infinity)
                .frame(height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(Color.primary.opacity(0.03))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(Theme.danger.opacity(0.35), lineWidth: 1)
                )
                .contentShape(Rectangle())
        case .plain:
            trash(size: 11.5)
                .frame(width: 20, height: 20)
                .contentShape(Rectangle())
        case .circle:
            trash(size: 11.5)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Theme.danger.opacity(0.10)))
                .contentShape(Rectangle())
        case .quiet:
            trash(size: 11.5, tint: .secondary)
                .frame(width: 24, height: 24)
                .contentShape(Rectangle())
        }
    }

    private func trash(size: CGFloat, tint: Color = Theme.danger) -> some View {
        Image(systemName: "trash")
            .font(.system(size: size, weight: .medium))
            .foregroundStyle(tint)
    }
}
