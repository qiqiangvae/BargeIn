import SwiftUI
import BargeInCore

/// 大字墙：满屏重复大字 + 渐强音。三种预设里唯一靠"信息轰炸"打断的。
struct WallTheme: PresetTheme {
    let preset = Preset.wall
    let title = "大字墙"
    let summary = "满屏重复大字 + 渐强音"
    let symbol = "text.alignleft"
    let slots: [CopySlot] = [.word, .progress]
    let intensities: [Intensity] = [.standard, .strict]
    let defaultIntensity: Intensity? = .standard

    var windowLayout: WindowLayout { .fullscreen }

    private var chrome: ChromeStyle { .fullscreen }

    func presentation(for instance: PresetInstance) -> Presentation {
        var result = Presentation(
            preset: preset,
            sound: .escalating,
            allowsPostpone: true,
            dismissDelay: 0,
            interruptNeedsHold: false
        )
        if instance.intensity == .strict {
            result.allowsPostpone = false
            result.dismissDelay = 5
        }
        return result
    }

    @MainActor @ViewBuilder
    func layout(_ context: ThemeContext) -> AnyView {
        AnyView(fullscreenLayout(context))
    }

    @MainActor private func fullscreenLayout(_ context: ThemeContext) -> some View {
        ZStack {
            LinearGradient(
                colors: [Color(red: 0.02, green: 0.09, blue: 0.16), .black],
                startPoint: .topLeading, endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            wordWall(context)

            // 中央只轻轻压暗：动作区靠自身底板保证可读，别在屏幕正中糊出一团黑。
            RadialGradient(
                colors: [.black.opacity(0.5), .black.opacity(0.05)],
                center: .center, startRadius: 40, endRadius: 480
            )
            .ignoresSafeArea()

            VStack(spacing: 20) {
                Text(context.model.copy.progress)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
                PresentationChrome.actions(context)
                PresentationChrome.pending(context, style: chrome)
                PresentationChrome.preview(context, style: chrome)
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 30)
            .background(.black.opacity(0.65), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(.cyan.opacity(0.3), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.6), radius: 24)

            PresentationChrome.close(context)
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        }
        // 全屏层永远是深色底，不跟随系统浅色外观。
        .environment(\.colorScheme, .dark)
    }

    /// 满屏重复的大字词：大小字混排、每词各自旋转与偏移，再按词错峰闪烁。
    @MainActor private func wordWall(_ context: ThemeContext) -> some View {
        Group {
            if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                wordWallLayer(context, time: 0, animating: false)
            } else {
                TimelineView(.periodic(from: .now, by: 0.06)) { timeline in
                    wordWallLayer(
                        context,
                        time: timeline.date.timeIntervalSinceReferenceDate,
                        animating: true
                    )
                }
            }
        }
        .clipped()
        .ignoresSafeArea()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(context.model.copy.word)
    }

    @MainActor private func wordWallLayer(_ context: ThemeContext, time: TimeInterval, animating: Bool) -> some View {
        GeometryReader { geo in
            let fontSize = min(max(48, geo.size.width / 13), 110)
            let rowCount = max(4, Int(geo.size.height / (fontSize * 1.05)) + 2)
            // 超宽屏按宽度补列，避免两侧留黑。
            let columnCount = max(5, Int(geo.size.width / (fontSize * 1.6)) + 2)

            VStack(spacing: 0) {
                ForEach(0..<rowCount, id: \.self) { row in
                    HStack(spacing: fontSize * 0.22) {
                        ForEach(0..<columnCount, id: \.self) { column in
                            let seed = seed(row: row, column: column)
                            let flash = animating ? flashLevel(time: time, seed: seed) : 0
                            Text(context.model.copy.word)
                                .font(.system(
                                    size: fontSize * scale(seed),
                                    weight: .black,
                                    design: .rounded
                                ))
                                .lineLimit(1)
                                .fixedSize()
                                .foregroundStyle(wordColor(seed))
                                .opacity(baseOpacity(seed) + flash * (1 - baseOpacity(seed)))
                                .scaleEffect(1 + flash * 0.05)
                                .rotationEffect(.degrees(rotation(seed)))
                                .offset(
                                    x: CGFloat((seed * 3) % 5 - 2) * fontSize * 0.08,
                                    y: CGFloat((seed * 5) % 7 - 3) * fontSize * 0.08
                                )
                        }
                    }
                    // 固定行高：大字直接压到相邻行上，密度不因字号变化而变稀。
                    .frame(width: geo.size.width, height: fontSize * 1.05)
                    .offset(x: rowShift(row, fontSize: fontSize))
                }
            }
            .frame(width: geo.size.width, height: geo.size.height)
            .rotationEffect(.degrees(-7))
            .scaleEffect(1.25)
        }
    }

    /// 按 5 组错峰闪烁：每组 2.4 秒短暂冲到全亮，整墙每秒约 2 次亮起。
    /// 刻意压住频率与面积，不做整屏频闪，避免光敏性风险。
    private func flashLevel(time: TimeInterval, seed: Int) -> Double {
        let phase = Double(seed % 5) / 5 * 2 * .pi
        let wave = sin(time * 2 * .pi / 2.4 + phase)
        return pow(max(0, wave), 6)
    }

    private func seed(row: Int, column: Int) -> Int {
        (row * 37 + column * 19) % 13
    }

    /// 同一面墙里同时出现约 0.5× 与 2× 的字号，形成大小混排。
    private func scale(_ seed: Int) -> CGFloat {
        [0.5, 1.7, 0.75, 1.1, 0.6, 2, 0.85, 0.55, 1.4, 0.7, 1, 0.65, 1.9][seed]
    }

    private func rotation(_ seed: Int) -> Double {
        [-4, 3, -7, 1, 6, -2, 8, -6, 0, 4, -1, 7, -8][seed]
    }

    private func rowShift(_ row: Int, fontSize: CGFloat) -> CGFloat {
        [0, -0.9, 0.45, -0.35, 0.75, -0.6][row % 6] * fontSize
    }

    private func wordColor(_ seed: Int) -> Color {
        seed % 7 == 0 ? .cyan : .white
    }

    private func baseOpacity(_ seed: Int) -> Double {
        if seed % 7 == 0 { return scale(seed) > 1.4 ? 0.32 : 0.6 }
        if scale(seed) > 1.4 { return 0.13 }
        return [0.45, 0.22, 0.34, 0.16][seed % 4]
    }

    // MARK: - 缩略图

    @MainActor @ViewBuilder
    func thumbnail(_ context: ThumbnailContext) -> AnyView {
        AnyView(wallThumbnail(context))
    }

    /// 满屏重复大字，三行错峰淡出。
    @MainActor private func wallThumbnail(_ context: ThumbnailContext) -> some View {
        VStack(spacing: 1) {
            line(context, opacity: 1)
            line(context, opacity: 0.42)
            line(context, opacity: 0.22)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.screenDark)
    }

    @MainActor private func line(_ context: ThumbnailContext, opacity: Double) -> some View {
        Text(context.sample(.word))
            .font(.system(size: 15, weight: .bold))
            .foregroundStyle(.white.opacity(opacity))
            .lineLimit(1)
            .minimumScaleFactor(0.5)
            .padding(.horizontal, 8)
    }
}
