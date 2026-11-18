import SwiftUI
import BargeInCore

/// 预设网格的尺寸口径。网格最多两行，超出的在卡片里纵向滚动；
/// 卡头的「共 N 套」也用它，两个地方不能各写一个阈值。
enum PresetGridLayout {
    static let columns = 3
    static let visibleRows = 2
    /// 卡片定高：66 的微缩图 + 单行名称与描述 + 8pt 内边距。
    /// 限高滚动要靠它算出两行的准确高度，不能量一次留一次余量。
    static let cardHeight: CGFloat = 126
    static let gap: CGFloat = 10

    static var limit: Int { columns * visibleRows }
    static var cappedHeight: CGFloat {
        CGFloat(visibleRows) * cardHeight + CGFloat(visibleRows - 1) * gap
    }

    /// 「共 9 套」只在一屏放不下时出现，默认三套不写。
    static func overflowNote(_ count: Int) -> String? {
        count > limit ? "共 \(count) 套" : nil
    }
}

/// 预设卡网格：设置页与全部预设共用一套卡。卡片只负责"被选中"，
/// 编辑 / 预览 / 复制 / 删除收在下方一行，只作用于当前使用中的那张。
struct PresetGrid<Editor: View>: View {
    let store: StateStore
    let model: SettingsModel
    let scene: SceneID
    let instances: [PresetInstance]
    let showsActions: Bool
    let editingID: UUID?
    let onSelect: (PresetInstance) -> Void
    let onEdit: (PresetInstance) -> Void
    let onPreview: (PresetInstance) -> Void
    let onCopy: (PresetInstance) -> Void
    let onDelete: (PresetInstance) -> Void
    let editor: (PresetInstance) -> Editor

    private var active: PresetInstance { store.activeInstance(for: scene) }
    private var editing: PresetInstance? { instances.first { $0.id == editingID } }
    private var descriptor: SceneDescriptor { store.descriptor(scene) }
    private var capped: Bool { instances.count > PresetGridLayout.limit }

    /// 滚动到底用的锚点：复制出来的卡排在最后，网格滚到它才算给了反馈。
    private static var endAnchor: String { "preset-grid-end" }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if capped {
                ScrollViewReader { proxy in
                    ScrollView(.vertical) {
                        VStack(spacing: 0) {
                            grid
                            Color.clear.frame(height: 1).id(Self.endAnchor)
                        }
                    }
                    .frame(height: PresetGridLayout.cappedHeight)
                    // 第 7 张把网格顶成限高状态：这棵子树是随这次复制才出现的，
                    // onChange 看不到「变多」，所以 onAppear 也要接一次。
                    .onAppear { revealPendingCopy(proxy) }
                    .onChange(of: instances.count) { old, new in
                        guard new > old else { return }
                        revealPendingCopy(proxy)
                    }
                }
            } else {
                grid
            }

            if showsActions {
                actionBar
                if let editing {
                    editor(editing)
                }
            }
        }
    }

    /// 复制出来的卡排在最后，限高后它落在屏外：滚到底把它露出来，
    /// 不然点了「复制」界面看着没反应。新卡这一轮才进布局，等它落位再滚。
    private func revealPendingCopy(_ proxy: ScrollViewProxy) {
        guard model.pendingPresetReveal else { return }
        model.pendingPresetReveal = false
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.25)) {
                proxy.scrollTo(Self.endAnchor, anchor: .bottom)
            }
        }
    }

    private var grid: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: PresetGridLayout.gap), count: PresetGridLayout.columns),
            alignment: .leading,
            spacing: PresetGridLayout.gap
        ) {
            ForEach(instances) { instance in
                PresetCard(
                    instance: instance,
                    descriptor: descriptor,
                    active: instance.id == active.id
                ) {
                    onSelect(instance)
                }
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 6) {
            ActionChip(title: "编辑", systemImage: "pencil") { onEdit(active) }
            ActionChip(title: "预览", systemImage: "eye") { onPreview(active) }
            ActionChip(title: "复制", systemImage: "doc.on.doc") { onCopy(active) }
            Spacer(minLength: 8)
            if !active.builtIn {
                DeleteChip(
                    confirming: model.confirmingDelete == "preset:\(active.id.uuidString)",
                    arm: { model.confirmingDelete = "preset:\(active.id.uuidString)" },
                    delete: { onDelete(active) }
                )
            }
        }
    }
}

struct PresetCard: View {
    let instance: PresetInstance
    let descriptor: SceneDescriptor
    let active: Bool
    let onSelect: () -> Void

    @MainActor private var theme: any PresetTheme { Catalog.theme(for: instance.preset) }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            PresetThumbnail(preset: instance.preset, descriptor: descriptor)

            HStack(spacing: 5) {
                Text(instance.name)
                    .font(.system(size: 12.5, weight: .semibold))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if active {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.accent)
                }
            }

            Text(theme.summary)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: PresetGridLayout.cardHeight, alignment: .topLeading)
        .cardChrome(
            radius: 11,
            fill: active ? Theme.accent.opacity(0.09) : Color.primary.opacity(0.03),
            stroke: active ? Theme.accent.opacity(0.55) : Theme.stroke
        )
        .contentShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
        .onTapGesture(perform: onSelect)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(instance.name)，\(theme.summary)")
        .accessibilityAddTraits(active ? .isSelected : AccessibilityTraits())
        .accessibilityAction(named: "使用这套预设", onSelect)
    }
}

/// 卡片下方的一行动作：带文字的按钮，不再是无标签的小图标。
private struct ActionChip: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: systemImage)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                Text(title)
                    .font(.system(size: 11.5))
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(Theme.stroke, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .accessibilityLabel(title)
    }
}

/// 删除入口：第一下换成「确认删除」，第二下才真的删。
private struct DeleteChip: View {
    let confirming: Bool
    let arm: () -> Void
    let delete: () -> Void

    var body: some View {
        Button {
            if confirming {
                delete()
            } else {
                arm()
            }
        } label: {
            HStack(spacing: 5) {
                if !confirming {
                    Image(systemName: "trash")
                        .font(.system(size: 11, weight: .medium))
                }
                Text(confirming ? "确认删除" : "删除")
                    .font(.system(size: 11.5, weight: confirming ? .semibold : .regular))
            }
            .foregroundStyle(confirming ? Theme.danger : Color.secondary)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(confirming ? Theme.danger.opacity(0.10) : Color.primary.opacity(0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        confirming ? Theme.danger.opacity(0.45) : Theme.stroke,
                        lineWidth: 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .help(confirming ? "再点一次删除" : "删除这张预设")
        .accessibilityLabel(confirming ? "确认删除" : "删除这张预设")
    }
}

/// 编辑面板：强度是预设的属性，所以放在这里，卡片正面不显示。
struct PresetEditor: View {
    let store: StateStore
    let model: SettingsModel
    let scene: SceneID
    let instance: PresetInstance

    @MainActor private var theme: any PresetTheme { Catalog.theme(for: instance.preset) }

    @FocusState private var focusedSlot: CopySlot?
    @FocusState private var focusedName: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("编辑 · \(instance.name)")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Button("恢复默认文案") {
                    store.resetCopy(instance.id, in: scene)
                }
                .buttonStyle(.plain)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Theme.accentText)
                .accessibilityHint("把这段文案改回出厂内容")
            }

            if !instance.builtIn {
                VStack(alignment: .leading, spacing: 5) {
                    Text("名称")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    TextField("", text: renameBinding)
                        .textFieldStyle(.plain)
                        .font(.system(size: 12.5))
                        .padding(.horizontal, 10)
                        .frame(height: 30)
                        .modifier(InputChrome(focused: focusedName))
                        .focused($focusedName)
                        .accessibilityLabel("卡片名称")
                }
            }

            if !theme.intensities.isEmpty {
                HStack(spacing: 12) {
                    Text("强度")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    SegmentedControl(
                        labels: theme.intensities.map(\.title),
                        selected: intensityIndex
                    ) { index in
                        store.setIntensity(instance.id, in: scene, theme.intensities[index])
                    }
                    .frame(width: 180)
                    Spacer(minLength: 0)
                }
                Text("强硬不可推迟，按钮锁定 5 秒（双击 Esc 仍可立即中断）；标准可以推迟 5 分钟。")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }

            ForEach(theme.slots, id: \.self) { slot in
                field(slot)
            }

            variableHints

            if store.hasUnknownVariables(instance.id, in: scene) {
                InlineWarning(text: "模板里有当前场景不提供的变量，这段文案会回落成默认内容。")
            }
        }
        .padding(12)
        .cardChrome()
    }

    private var intensityIndex: Int {
        theme.intensities.firstIndex(of: instance.intensity ?? .standard) ?? 0
    }

    private func field(_ slot: CopySlot) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(slot.label)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                if store.hasOverride(instance.id, in: scene, slot: slot) {
                    Text("已改")
                        .font(.system(size: 9.5, weight: .semibold))
                        .foregroundStyle(Theme.accentText)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Theme.accent.opacity(0.12))
                        )
                }
            }

            TextField("", text: binding(slot), prompt: Text(CopyText.defaultText(slot, scene: store.descriptor(scene))))
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .padding(.horizontal, 10)
                .frame(height: 30)
                .modifier(InputChrome(focused: focusedSlot == slot))
                .focused($focusedSlot, equals: slot)
                .accessibilityLabel(slot.label)
        }
    }

    @ViewBuilder
    private var variableHints: some View {
        let names = store.descriptor(scene).variableNames
        HStack(spacing: 5) {
            if names.isEmpty {
                Text("这个场景的文案不支持变量")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            } else {
                Text("可用变量")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                ForEach(names, id: \.self) { name in
                    Text("{\(name)}")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1.5)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color.primary.opacity(0.06))
                        )
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var renameBinding: Binding<String> {
        Binding(
            get: { model.renameDraft },
            set: { model.rename(instance, to: $0) }
        )
    }

    private func binding(_ slot: CopySlot) -> Binding<String> {
        Binding(
            get: { store.template(instance.id, in: scene, slot: slot) },
            set: { store.setCopy(instance.id, in: scene, slot: slot, to: $0) }
        )
    }
}

/// 文本输入框的外框：文案槽与名称共用。
struct InputChrome: ViewModifier {
    let focused: Bool

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.primary.opacity(focused ? 0.06 : 0.03))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(
                        focused ? Theme.accent.opacity(0.70) : Theme.stroke,
                        lineWidth: focused ? 1.5 : 1
                    )
            )
    }
}
