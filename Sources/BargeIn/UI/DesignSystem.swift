import AppKit
import SwiftUI

// MARK: - 设计令牌

/// 浅色/深色各写一次的品牌色。组件里不出现裸色值，换肤只改这里。
enum Theme {
    static let accent = adaptive(0x0284C7, 0x38BDF8)
    static let accentText = adaptive(0x0369A1, 0x7DD3FC)
    static let warn = adaptive(0xB45309, 0xFBBF24)
    static let success = adaptive(0x0F766E, 0x34D399)
    static let danger = adaptive(0xB3261E, 0xF87171)

    /// 水色按钮上的文字色。深浅两套外观共用（水色足够亮，压深色字更稳）。
    static let ink = fixed(0x04121C)

    static let cardFill = Color(nsColor: NSColor(name: nil) { appearance in
        isDark(appearance) ? NSColor(white: 1, alpha: 0.05) : NSColor(white: 1, alpha: 0.78)
    })
    static let stroke = Color(nsColor: NSColor(name: nil) { appearance in
        isDark(appearance) ? NSColor(white: 1, alpha: 0.10) : NSColor(white: 0, alpha: 0.08)
    })
    /// 分段控件选中块：深色下要比轨道亮，不能用 controlBackgroundColor（它比窗口底还暗）。
    static let segmentFill = Color(nsColor: NSColor(name: nil) { appearance in
        isDark(appearance) ? NSColor(white: 1, alpha: 0.16) : NSColor(white: 1, alpha: 1)
    })

    static let actionGradient = LinearGradient(
        colors: [fixed(0x22D3EE), fixed(0x0EA5E9)],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    /// 预设卡微缩图的三种底色：大字墙与碎裂是暗屏，温柔跟着系统外观。
    static let screenDark = fixed(0x0B0D10)
    static let screenLight = adaptive(0xE3E7EC, 0x24272B)
    static let screenCard = adaptive(0xFFFFFF, 0x3B3F45)

}

enum Motion {
    static let press = Animation.easeOut(duration: 0.12)
    static let enter = Animation.spring(response: 0.46, dampingFraction: 0.86)
}

private func isDark(_ appearance: NSAppearance) -> Bool {
    appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
}

private func fixed(_ hex: UInt32) -> Color {
    Color(nsColor: NSColor(hexValue: hex))
}

private func adaptive(_ light: UInt32, _ dark: UInt32) -> Color {
    Color(nsColor: NSColor(name: nil) { appearance in
        NSColor(hexValue: isDark(appearance) ? dark : light)
    })
}

extension NSColor {
    convenience init(hexValue: UInt32) {
        self.init(
            srgbRed: CGFloat((hexValue >> 16) & 0xFF) / 255,
            green: CGFloat((hexValue >> 8) & 0xFF) / 255,
            blue: CGFloat(hexValue & 0xFF) / 255,
            alpha: 1
        )
    }
}

// MARK: - 时间文案

enum RelativeTime {
    static func clock(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// "14:30 · 18 分钟后" / "明天 09:00" / "周一 09:00"
    /// 不印月日：这句话要放进 popover 卡片里那一列，月日一写就截断。
    static func when(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let time = clock(date)
        if calendar.isDate(date, inSameDayAs: now) {
            return "\(time) · \(distance(from: now, to: date))"
        }
        if calendar.isDateInTomorrow(date) {
            return "明天 \(time)"
        }
        return "\(date.formatted(.dateTime.weekday(.short))) \(time)"
    }

    static func distance(from now: Date, to date: Date) -> String {
        let seconds = date.timeIntervalSince(now)
        guard seconds >= 60 else { return "不到 1 分钟后" }
        let minutes = Int((seconds / 60).rounded())
        guard minutes >= 60 else { return "\(minutes) 分钟后" }
        let hours = minutes / 60
        let rest = minutes % 60
        guard hours < 24 else { return "\(hours / 24) 天后" }
        return rest == 0 ? "\(hours) 小时后" : "\(hours) 小时 \(rest) 分钟后"
    }
}

// MARK: - 按钮样式

struct PressableStyle: ButtonStyle {
    var scale: CGFloat = 0.985

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? scale : 1)
            .brightness(configuration.isPressed ? -0.03 : 0)
            .animation(Motion.press, value: configuration.isPressed)
    }
}

// MARK: - 次级按钮

struct QuietButton: View {
    let title: String
    var systemImage: String?
    var height: CGFloat = 36
    /// 行内主动作（如"活动了"）：淡品牌色底 + 实描边。
    /// 默认灰底与卡片只有 1.3–1.6:1 的边界对比，看着不像按钮。
    var emphasized: Bool = false
    var enabled: Bool = true
    let action: () -> Void

    private var fill: Color { emphasized ? Theme.accent.opacity(0.16) : Color.primary.opacity(0.05) }
    private var border: Color { emphasized ? Theme.accent.opacity(0.85) : Theme.stroke }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                if let systemImage {
                    Image(systemName: systemImage)
                        .font(.system(size: height > 46 ? 12 : 11, weight: .medium))
                }
                Text(title)
                    .font(.system(size: height > 46 ? 14 : 12.5, weight: emphasized ? .semibold : .medium))
            }
            .foregroundStyle(emphasized ? Theme.accentText : Color.primary)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: height > 46 ? 14 : 10, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: height > 46 ? 14 : 10, style: .continuous)
                    .strokeBorder(border, lineWidth: 1)
            )
            .opacity(enabled ? 1 : 0.4)
        }
        .buttonStyle(PressableStyle())
        .disabled(!enabled)
    }
}

// MARK: - 设置控件

/// 分段选择：选中块自己滑动，不依赖 SwiftUI 的分段控件默认皮肤。
struct SegmentedControl: View {
    let labels: [String]
    let selected: Int
    let onSelect: (Int) -> Void

    var body: some View {
        GeometryReader { proxy in
            let segment = (proxy.size.width - 4) / CGFloat(labels.count)
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(Color.primary.opacity(0.06))

                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Theme.segmentFill)
                    .frame(width: segment, height: proxy.size.height - 4)
                    .offset(x: 2 + CGFloat(selected) * segment, y: 2)
                    .shadow(color: .black.opacity(0.10), radius: 2, y: 1)

                HStack(spacing: 0) {
                    ForEach(labels.indices, id: \.self) { index in
                        Button {
                            onSelect(index)
                        } label: {
                            Text(labels[index])
                                .font(.system(size: 12.5, weight: selected == index ? .semibold : .regular))
                                .foregroundStyle(selected == index ? .primary : .secondary)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected == index ? .isSelected : AccessibilityTraits())
                    }
                }
            }
            .animation(Motion.enter, value: selected)
        }
        .frame(height: 32)
    }
}

/// 数值步进：比系统 Stepper 宽一点的点击面，单位紧贴数字。
struct AmountStepper: View {
    let value: Int
    let range: ClosedRange<Int>
    let step: Int
    let unit: String
    let onChange: (Int) -> Void

    var body: some View {
        HStack(spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text("\(value)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(unit)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .frame(minWidth: 66, alignment: .trailing)

            HStack(spacing: 4) {
                stepButton(symbol: "minus", delta: -step, disabled: value - step < range.lowerBound, label: "减少")
                stepButton(symbol: "plus", delta: step, disabled: value + step > range.upperBound, label: "增加")
            }
        }
    }

    private func stepButton(symbol: String, delta: Int, disabled: Bool, label: String) -> some View {
        Button {
            onChange(min(max(value + delta, range.lowerBound), range.upperBound))
        } label: {
            Image(systemName: symbol)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(disabled ? .tertiary : .primary)
                .frame(width: 24, height: 24)
                .background(Circle().fill(Color.primary.opacity(0.06)))
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle(scale: 0.92))
        .disabled(disabled)
        .accessibilityLabel(label)
    }
}

struct SettingsRow<Control: View>: View {
    let title: String
    var hint: String? = nil
    @ViewBuilder let control: () -> Control

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13))
                if let hint {
                    Text(hint)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 12)
            control()
        }
        .frame(minHeight: 28)
    }
}

struct SettingsCard<Content: View>: View {
    let title: String
    var footnote: String? = nil
    var trailing: AnyView? = nil
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if !title.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(title)
                        .font(.system(size: 12.5, weight: .semibold))
                    Spacer(minLength: 8)
                    if let footnote {
                        Text(footnote)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                    if let trailing {
                        trailing
                    }
                }
            }
            content()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Theme.cardFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(Theme.stroke, lineWidth: 1)
        )
    }
}

/// 卡片内的次级块：圆角底 + 描边。设置页的编辑面板、订阅行、popover 的行共用。
private struct CardChrome: ViewModifier {
    var radius: CGFloat
    var fill: Color
    var stroke: Color

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(stroke, lineWidth: 1)
            )
    }
}

extension View {
    func cardChrome(
        radius: CGFloat = 11,
        fill: Color = Color.primary.opacity(0.03),
        stroke: Color = Theme.stroke
    ) -> some View {
        modifier(CardChrome(radius: radius, fill: fill, stroke: stroke))
    }
}

struct InlineWarning: View {
    let text: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 10))
            Text(text)
                .font(.system(size: 11))
                .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(Theme.warn)
    }
}
