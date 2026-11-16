import SwiftUI
import BargeInCore

/// 温柔：右上角一张小卡片 + 一声提示音。不挡你，但会自己消失。
struct GentleTheme: PresetTheme {
    let preset = Preset.gentle
    let title = "温柔"
    let summary = "右上角小卡片，一声提示音"
    let symbol = "leaf.fill"
    let slots: [CopySlot] = [.title, .progress]

    var windowLayout: WindowLayout {
        .corner(
            size: CGSize(width: 360, height: 260),
            margin: CGSize(width: 24, height: 24)
        )
    }

    var hasShadow: Bool { true }

    private var chrome: ChromeStyle { .card }

    func presentation(for instance: PresetInstance) -> Presentation {
        Presentation(
            preset: preset,
            sound: .chime,
            allowsPostpone: true,
            dismissDelay: 0,
            interruptNeedsHold: false
        )
    }

    @MainActor @ViewBuilder
    func layout(_ context: ThemeContext) -> AnyView {
        AnyView(cardLayout(context))
    }

    @MainActor private func cardLayout(_ context: ThemeContext) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(context.model.copy.title)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                Spacer()
                PresentationChrome.close(context)
            }
            Text(context.model.copy.progress)
                .font(.callout)
                .foregroundStyle(.secondary)
            PresentationChrome.actions(context)
            PresentationChrome.pending(context, style: chrome)
            PresentationChrome.preview(context, style: chrome)
        }
        .padding(16)
        .frame(width: 320, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - 缩略图

    @MainActor @ViewBuilder
    func thumbnail(_ context: ThumbnailContext) -> AnyView {
        AnyView(gentleThumbnail(context))
    }

    /// 浅色屏幕上右上角一张卡。深色外观下屏幕跟着变深，不能摆一块白板。
    @MainActor private func gentleThumbnail(_ context: ThumbnailContext) -> some View {
        ZStack(alignment: .topTrailing) {
            Theme.screenLight
            VStack(spacing: 0) {
                Color.primary.opacity(0.05)
                    .frame(height: 9)
                Divider().opacity(0.4)
                Spacer(minLength: 0)
            }
            VStack(alignment: .leading, spacing: 3) {
                Capsule().fill(Color.primary.opacity(0.52)).frame(width: 40, height: 3)
                Capsule().fill(Color.primary.opacity(0.16)).frame(maxWidth: .infinity).frame(height: 3)
                Capsule().fill(Color.primary.opacity(0.16)).frame(width: 26, height: 3)
            }
            .padding(6)
            .frame(width: 62, height: 28, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 5, style: .continuous).fill(Theme.screenCard))
            .shadow(color: .black.opacity(0.16), radius: 4, y: 2)
            .padding(8)
        }
    }
}
