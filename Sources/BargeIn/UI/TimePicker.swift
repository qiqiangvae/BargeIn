import SwiftUI
import BargeInCore

/// 24 小时制时间值：收起时是一枚 `HH:mm` 胶囊，点开是「时 / 分」网格。
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

/// 展开内容：时 24 项、分 12 项（当前值不是 5 的倍数时保留它），6 列网格单击即生效。
struct TimePickerPanel: View {
    let label: String
    let time: TimeOfDay
    let onChange: (TimeOfDay) -> Void

    private var minutes: [Int] {
        var values = Array(stride(from: 0, to: 60, by: 5))
        if !values.contains(time.minute) {
            values.append(time.minute)
            values.sort()
        }
        return values
    }

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

            grid(unit: "分", values: minutes, selected: time.minute) { minute in
                onChange(TimeOfDay(hour: time.hour, minute: minute))
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
