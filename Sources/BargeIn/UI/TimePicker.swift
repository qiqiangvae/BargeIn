import SwiftUI
import BargeInCore

/// 24 小时制时间值：收起时是一枚 `HH:mm` 胶囊，点开是「时网格 + 分滑条」。
/// 替掉系统 `DatePicker` 的步进字段，让时间输入与设置页其它控件同一套皮肤。
struct TimePicker: View {
    let label: String
    let time: TimeOfDay
    /// 指定时刻的列表行里用无边框样式：行本身已经有容器，再套一层胶囊就成了双层框。
    var bordered: Bool = true
    let onChange: (TimeOfDay) -> Void

    // 本机只有 CLT，SwiftUI 的 @State 宏不可用，交互状态走 @StateObject。
    @StateObject private var state = TimePickerState()

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(.secondary)

            Button {
                state.isPresented.toggle()
            } label: {
                HStack(spacing: 6) {
                    Text(time.formatted())
                        .font(.system(size: bordered ? 14 : 13, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(.primary)
                .padding(.horizontal, bordered ? 10 : 6)
                .frame(minWidth: bordered ? 82 : 0, minHeight: bordered ? 30 : 26)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(bordered
                            ? Color.primary.opacity(state.isHovering ? 0.08 : 0.05)
                            : Color.primary.opacity(state.isHovering ? 0.06 : 0))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(
                            bordered
                                ? (state.isHovering ? Theme.accent.opacity(0.5) : Theme.stroke)
                                : Color.clear,
                            lineWidth: 1
                        )
                )
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .onHover { state.isHovering = $0 }
            .animation(Motion.press, value: state.isHovering)
            .accessibilityLabel("\(label)，\(time.formatted())")
            .accessibilityHint("打开时间选择")
            .popover(isPresented: $state.isPresented, arrowEdge: .bottom) {
                TimePickerPanel(label: label, time: time, onChange: onChange)
            }
        }
    }
}

/// 展开内容：时是 24 项 6 列网格，分是一条 0–59 的滑条，单击 / 拖动即生效。
struct TimePickerPanel: View {
    let label: String
    let time: TimeOfDay
    let onChange: (TimeOfDay) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(time.formatted())
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .monospacedDigit()
            }

            grid(unit: "时", values: Array(0...23), selected: time.hour) { hour in
                onChange(TimeOfDay(hour: hour, minute: time.minute))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("分")
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(.secondary)
                MinuteSlider(minute: time.minute) { minute in
                    onChange(TimeOfDay(hour: time.hour, minute: minute))
                }
            }
        }
        .padding(14)
        .frame(width: 236)
    }

    private func grid(unit: String, values: [Int], selected: Int, onSelect: @escaping (Int) -> Void) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(unit)
                .font(.system(size: 10.5, weight: .medium))
                .foregroundStyle(.secondary)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 6), spacing: 4) {
                ForEach(values, id: \.self) { value in
                    TimePickerCell(
                        text: String(format: "%02d", value),
                        selected: value == selected,
                        accessibilityLabel: "\(value) \(unit)"
                    ) {
                        onSelect(value)
                    }
                }
            }
        }
    }
}

/// 分钟滑条：一条 4pt 轨道 + 14pt 圆点，滑到哪分就改到哪分。
/// 系统 Slider 在 macOS 上不画已走过的轨道，和设置页的"进度条"观感对不上，所以自绘。
private struct MinuteSlider: View {
    let minute: Int
    let onChange: (Int) -> Void

    private let thumb: CGFloat = 14
    private let track: CGFloat = 4

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let usable = max(1, width - thumb)
            let progress = CGFloat(min(minute, 59)) / 59
            let thumbX = thumb / 2 + usable * progress

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.primary.opacity(0.10))
                    .frame(height: track)
                Capsule()
                    .fill(Theme.accent)
                    .frame(width: thumbX, height: track)
                Circle()
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .overlay(
                        Circle().strokeBorder(Theme.stroke, lineWidth: 1)
                    )
                    .shadow(color: .black.opacity(0.18), radius: 2, y: 1)
                    .frame(width: thumb, height: thumb)
                    .offset(x: thumbX - thumb / 2)
            }
            .frame(width: width, height: thumb)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let ratio = (value.location.x - thumb / 2) / usable
                        set(min(59, max(0, Int((ratio * 59).rounded()))))
                    }
            )
        }
        .frame(height: thumb)
        .focusable()
        .onKeyPress(.leftArrow) { adjust(-1) }
        .onKeyPress(.rightArrow) { adjust(1) }
        .accessibilityElement()
        .accessibilityLabel("分钟")
        .accessibilityValue("\(minute) 分")
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: _ = adjust(1)
            case .decrement: _ = adjust(-1)
            default: break
            }
        }
    }

    private func set(_ next: Int) {
        guard next != minute else { return }
        onChange(next)
    }

    private func adjust(_ delta: Int) -> KeyPress.Result {
        set(min(59, max(0, minute + delta)))
        return .handled
    }
}

private struct TimePickerCell: View {
    let text: String
    let selected: Bool
    let accessibilityLabel: String
    let action: () -> Void

    @StateObject private var state = TimePickerState()

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 12, weight: selected ? .semibold : .regular, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(selected ? Theme.accentText : Color.primary)
                .frame(maxWidth: .infinity)
                .frame(height: 26)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(state.isHovering ? Theme.accent.opacity(0.10) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(selected ? Theme.accent.opacity(0.16) : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .strokeBorder(selected ? Theme.accent.opacity(0.45) : Color.clear, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { state.isHovering = $0 }
        .accessibilityLabel(accessibilityLabel)
        .accessibilityAddTraits(selected ? .isSelected : AccessibilityTraits())
    }
}

/// 胶囊与网格格子的悬停 / 展开状态。SwiftUI 的 @State 宏在本机 CLT 下不可用。
@MainActor
private final class TimePickerState: ObservableObject {
    @Published var isPresented = false
    @Published var isHovering = false
}
