import SwiftUI
import BargeInCore

/// 碎裂：屏幕炸开 + 玻璃碎音。三种预设里唯一有物理动画的。
struct ShatterTheme: PresetTheme {
    let preset = Preset.shatter
    let title = "碎裂"
    let summary = "屏幕炸开 + 玻璃碎音"
    let symbol = "burst.fill"
    let slots: [CopySlot] = [.title, .progress]

    var windowLayout: WindowLayout { .fullscreen }

    private var chrome: ChromeStyle { .shatter }

    func presentation(for instance: PresetInstance) -> Presentation {
        Presentation(
            preset: preset,
            sound: .shatter,
            allowsPostpone: true,
            dismissDelay: 0,
            interruptNeedsHold: false
        )
    }

    @MainActor func makeAnimator(reduceMotion: Bool) -> (any OverlayAnimator)? {
        ShatterAnimator(reduceMotion: reduceMotion)
    }

    @MainActor @ViewBuilder
    func layout(_ context: ThemeContext) -> AnyView {
        AnyView(shatterLayout(context))
    }

    /// 整屏是碎掉的深色玻璃，面板浮在中间。确认之前只裂不落；
    /// 动作后 presenter 让整片玻璃坠落，遮罩随碎片一起消失、露出桌面。
    @MainActor private func shatterLayout(_ context: ThemeContext) -> some View {
        ZStack {
            if let shatter = context.animator as? ShatterAnimator {
                FractureCanvas(animator: shatter)
            } else {
                Color.black
            }

            VStack(spacing: 12) {
                Text(context.model.copy.title)
                    .font(.system(size: 20, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text(context.model.copy.progress)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.92))
                PresentationChrome.actions(context)
                PresentationChrome.pending(context, style: chrome)
                PresentationChrome.preview(context, style: chrome)
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 26)
            .background(.black.opacity(0.74), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(.cyan.opacity(0.30), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.6), radius: 24)
            .opacity(panelVisible(context) ? 1 : 0)
            .allowsHitTesting(panelVisible(context))

            PresentationChrome.close(context)
                .opacity(panelVisible(context) ? 1 : 0)
                .allowsHitTesting(panelVisible(context))
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        .environment(\.colorScheme, .dark)
    }

    /// 裂满、面板出现之后才允许操作。
    @MainActor private func panelVisible(_ context: ThemeContext) -> Bool {
        context.animator?.isRevealed ?? true
    }

    // MARK: - 缩略图

    @MainActor @ViewBuilder
    func thumbnail(_ context: ThumbnailContext) -> AnyView {
        AnyView(shatterThumbnail(context))
    }

    /// 暗屏上从中心裂开。
    @MainActor private func shatterThumbnail(_ context: ThumbnailContext) -> some View {
        ZStack {
            Theme.screenDark
            Canvas { canvas, size in
                let center = CGPoint(x: size.width / 2, y: size.height * 0.44)
                var path = Path()
                for ray in Self.cracks {
                    let radians = ray.angle * .pi / 180
                    path.move(to: center)
                    path.addLine(
                        to: CGPoint(
                            x: center.x + cos(radians) * size.width * ray.reach,
                            y: center.y + sin(radians) * size.height * ray.reach
                        )
                    )
                }
                canvas.stroke(path, with: .color(.white.opacity(0.62)), lineWidth: 0.9)
            }
            Text(context.sample(.title))
                .font(.system(size: 10.5, weight: .bold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .padding(.horizontal, 10)
        }
    }

    private static let cracks: [(angle: CGFloat, reach: CGFloat)] = [
        (8, 0.95), (44, 0.86), (78, 1.0), (118, 0.78),
        (152, 0.92), (196, 0.84), (238, 0.98), (286, 0.82), (326, 0.9),
    ]
}

extension ShatterAnimator: OverlayAnimator {
    var exitDuration: TimeInterval { fracture.exitDuration }
}
