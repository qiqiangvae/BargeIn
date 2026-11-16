import AppKit
import SwiftUI

/// 更新通知用「温柔」那张卡：右上角、一声提示音、不抢焦点。
/// 它不是提醒队列的一员，不写任何状态；点卡片才打开设置。
final class UpdateNoticePanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

@MainActor
struct UpdateNoticeCard: View {
    let version: String
    let current: String
    let onOpen: () -> Void
    let onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Barge In 有新版本 \(version)")
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                    Text("当前 \(current) · 点一下打开通用设置")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .onTapGesture(perform: onOpen)

                // 与预设卡里的 × 同一个样子，但这里只收起通知。
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .padding(8)
                        .background(.quaternary, in: Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("收起，这一版不再提醒")
            }

            HStack(spacing: 0) {
                QuietButton(title: "去更新", systemImage: "arrow.down.circle", height: 34, emphasized: true, action: onOpen)
                    .frame(width: 108)
                Spacer(minLength: 0)
            }
        }
        .padding(16)
        .frame(width: 320, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}

@MainActor
final class UpdateNoticePresenter {
    private var panel: NSPanel?
    private var onOpen: (() -> Void)?
    private let sound = SoundPlayer()

    func show(version: String, current: String, onOpen: @escaping () -> Void) {
        guard panel == nil, let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        self.onOpen = onOpen

        let view = UpdateNoticeCard(
            version: version,
            current: current,
            onOpen: { [weak self] in self?.open() },
            onClose: { [weak self] in self?.dismiss() }
        )
        let frame = ReminderPresenter.frame(for: Catalog.theme(for: .gentle).windowLayout, on: screen)
        let panel = UpdateNoticePanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovable = false
        panel.hidesOnDeactivate = false
        panel.contentView = ReminderHostingView(rootView: view)
        panel.setFrame(frame, display: true)
        panel.orderFrontRegardless()
        self.panel = panel
        sound.start(.chime)
        print("[bargein] update notice shown: \(version)")
    }

    func dismiss() {
        sound.stop()
        panel?.close()
        panel = nil
        onOpen = nil
    }

    private func open() {
        let action = onOpen
        dismiss()
        action?()
    }
}
