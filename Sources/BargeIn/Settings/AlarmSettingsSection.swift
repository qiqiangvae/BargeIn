import SwiftUI
import BargeInCore
import SceneAlarm

/// 闹钟 tab 的一张卡：闹钟列表、行内编辑与添加。无效是派生状态，随通用时间实时重判。
struct AlarmSettingsSection: View {
    let store: StateStore
    let model: SettingsModel
    let onChanged: () -> Void

    var body: some View {
        SettingsCard(title: "闹钟", footnote: footnote) {
            VStack(alignment: .leading, spacing: 10) {
                if store.alarms.isEmpty {
                    Text("还没有闹钟。加一条，到点就用这套呈现把你拽出来。")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(store.alarms) { alarm in
                        VStack(alignment: .leading, spacing: 0) {
                            row(alarm)
                            if model.editingAlarmID == alarm.id {
                                editor(alarm)
                            }
                        }
                    }
                }

                addButton

                if !store.isSceneEnabled(.alarm), !store.alarms.isEmpty {
                    Text("闹钟场景现在是停用的，这些闹钟不会响。用上面的「启用」打开它。")
                        .font(.system(size: 11))
                        .foregroundStyle(Theme.warn)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Text("每天：每个非休息日；仅一次：未来 7 天内的一天。时刻不在工作时段内、或那天是休息日时，这一条会标成「不会响」。")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var footnote: String? {
        store.alarms.isEmpty ? nil : "\(store.alarms.count) 条"
    }

    // MARK: - 列表行

    private func row(_ alarm: Alarm) -> some View {
        let issue = store.alarmIssue(alarm)
        // 停用的条目本来就不响，不再额外标无效：两个原因同时说反而读不出重点。
        let showsIssue = issue != nil && alarm.isEnabled
        return HStack(spacing: 9) {
            Circle()
                .fill(showsIssue ? Theme.warn : Theme.accent)
                .frame(width: 7, height: 7)

            Button {
                model.beginEditAlarm(alarm)
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text(alarm.time.formatted())
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                        Text(alarm.displayTitle)
                            .font(.system(size: 12))
                            .lineLimit(1)
                    }
                    Text(showsIssue ? (issue?.message ?? "") : AlarmPolicy.repeatText(alarm, calendar: .current))
                        .font(.system(size: 10.5))
                        .foregroundStyle(showsIssue ? Theme.warn : Color.secondary)
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(PressableStyle())
            .accessibilityLabel("\(alarm.time.formatted()) \(alarm.displayTitle)，编辑")
            .accessibilityHint(showsIssue ? (issue?.message ?? "") : "展开编辑")

            Spacer(minLength: 8)

            Toggle("", isOn: Binding(
                get: { alarm.isEnabled },
                set: { enabled in
                    store.setAlarmEnabled(enabled, for: alarm.id)
                    onChanged()
                }
            ))
            .labelsHidden()
            .toggleStyle(.switch)
            .controlSize(.mini)
            .accessibilityLabel("启用 \(alarm.displayTitle)")

            ConfirmDeleteButton(
                form: .quiet,
                label: "删除 \(alarm.displayTitle)",
                confirming: model.confirmingDelete == "alarm:\(alarm.id.uuidString)",
                onArm: { model.confirmingDelete = "alarm:\(alarm.id.uuidString)" }
            ) {
                model.confirmingDelete = nil
                if model.editingAlarmID == alarm.id { model.editingAlarmID = nil }
                store.deleteAlarm(alarm.id)
                onChanged()
            }
        }
        .padding(9)
        .cardChrome(radius: 10, fill: Color.primary.opacity(0.04))
    }

    // MARK: - 编辑

    private func editor(_ alarm: Alarm) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            field("内容") {
                TextField("为空就用时刻", text: titleBinding(alarm))
                    .textFieldStyle(.plain)
                    .font(.system(size: 12))
                    .padding(.horizontal, 9)
                    .frame(height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Color.primary.opacity(0.05))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .strokeBorder(Theme.stroke, lineWidth: 1)
                    )
            }

            HStack(spacing: 12) {
                TimePicker(label: "时刻", time: alarm.time) { time in
                    store.updateAlarm(alarm.id) { $0.time = time }
                    onChanged()
                }
                Spacer(minLength: 8)
                SegmentedControl(
                    labels: ["每天", "仅一次"],
                    selected: alarm.onceDay == nil ? 0 : 1
                ) { index in
                    store.updateAlarm(alarm.id) { item in
                        item.recurrence = index == 0
                            ? .daily
                            : .once(AlarmPolicy.clamp(item.onceDay ?? Date(), now: Date(), calendar: .current))
                    }
                    onChanged()
                }
                .frame(width: 132)
            }

            if let day = alarm.onceDay {
                dateRow(alarm, day: day)
            }

            if let issue = store.alarmIssue(alarm) {
                Text(issue.message)
                    .font(.system(size: 10.5))
                    .foregroundStyle(Theme.warn)
            }
        }
        .padding(10)
        .cardChrome(radius: 10, fill: Color.primary.opacity(0.02))
        .padding(.top, 6)
    }

    private func dateRow(_ alarm: Alarm, day: Date) -> some View {
        HStack(spacing: 8) {
            Text("日期")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer(minLength: 8)
            stepButton("上一天", systemImage: "chevron.left") { step(alarm, day, -1) }
            Text(AlarmPolicy.dayText(day, calendar: .current))
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
            stepButton("下一天", systemImage: "chevron.right") { step(alarm, day, 1) }
        }
        .frame(minHeight: 26)
    }

    private func stepButton(
        _ label: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Color.primary.opacity(0.05)))
                .contentShape(Circle())
        }
        .buttonStyle(PressableStyle(scale: 0.9))
        .accessibilityLabel(label)
    }

    private func step(_ alarm: Alarm, _ day: Date, _ delta: Int) {
        guard let next = Calendar.current.date(byAdding: .day, value: delta, to: day) else { return }
        let clamped = AlarmPolicy.clamp(next, now: Date(), calendar: .current)
        store.updateAlarm(alarm.id) { $0.recurrence = .once(clamped) }
        onChanged()
    }

    private func titleBinding(_ alarm: Alarm) -> Binding<String> {
        Binding(
            get: { model.alarmTitleDraft },
            set: { text in
                // 草稿留在模型里：输入法组字时不会被 store 的旧值弹回去。
                model.alarmTitleDraft = text
                store.updateAlarm(alarm.id) { $0.title = text }
            }
        )
    }

    private func field<Content: View>(_ label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 添加

    private var addButton: some View {
        Button {
            let alarm = newAlarm()
            store.addAlarm(alarm)
            model.beginEditAlarm(alarm)
            onChanged()
        } label: {
            Label("添加闹钟", systemImage: "plus")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .strokeBorder(Theme.stroke, style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
    }

    /// 新闹钟落在下一个半点上；落在工作时段外就回工作时段开始——别造一条开局就无效的。
    private func newAlarm() -> Alarm {
        let components = Calendar.current.dateComponents([.hour, .minute], from: Date())
        var hour = components.hour ?? 9
        var minute = (components.minute ?? 0) / 30 * 30 + 30
        if minute >= 60 {
            minute -= 60
            hour += 1
        }
        var time = TimeOfDay(hour: hour, minute: minute)
        if time < store.state.workStart || time >= store.state.workEnd {
            time = store.state.workStart
        }
        return Alarm(time: time)
    }
}
