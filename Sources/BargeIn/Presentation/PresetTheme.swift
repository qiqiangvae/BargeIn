import SwiftUI
import BargeInCore

/// 一套提醒的完整呈现参数，由预设实例解析而来；界面只负责显示。
struct ReminderModel: Equatable {
    var completionLabel: String
    var completionSymbol: String
    /// 文案已按实例解析完，界面只负责显示。
    var copy: ReminderCopy
    /// 队列里还有几条。引擎独占的文案，预设改不了。
    var pendingCount: Int
}

/// 呈现层的动画器：只暴露外壳需要问的几个问题，具体怎么动由预设自己造。
@MainActor
protocol OverlayAnimator: AnyObject {
    var isInteractive: Bool { get }
    var isRevealed: Bool { get }
    /// 降低动态时直接收，不播退场。
    var reduceMotion: Bool { get }
    /// 退场动画的时长：外壳要等它播完才关窗。
    var exitDuration: TimeInterval { get }
    func beginExit()
}

/// 窗口摆在哪。由预设自己定，外壳照着摆。
enum WindowLayout: Equatable {
    case fullscreen
    case corner(size: CGSize, margin: CGSize)
}

/// 呈现时给预设的全部输入：文案已解析完、按钮与退出由外壳提供。
struct ThemeContext {
    let model: ReminderModel
    let presentation: Presentation
    let isPreview: Bool
    let secondsLeft: Int
    let unlocked: Bool
    let interactive: Bool
    let animator: (any OverlayAnimator)?
    let onComplete: () -> Void
    let onPostpone: () -> Void
    let onInterrupt: () -> Void
}

/// 缩略图的输入：用这份样例文案把模板填一遍。
struct ThumbnailContext {
    let descriptor: SceneDescriptor

    /// 模板里可能带变量（日程的 `{title}`、闹钟的 `{title}`），缩略图用一份样例值填一遍。
    /// 场景自己的样例值优先于通用表：同一份「缩略图上的字」由场景定义。
    func sample(_ slot: CopySlot) -> String {
        var text = descriptor.defaultCopy[slot] ?? ""
        let values = Self.sampleValues.merging(descriptor.sampleValues) { _, scene in scene }
        for (name, value) in values {
            text = text.replacingOccurrences(of: "{\(name)}", with: value)
        }
        return text
    }

    private static let sampleValues: [String: String] = [
        "title": "Q4 产品评审", "start": "9:30", "minutes": "5", "location": "会议室 A",
        "cup": "4", "cups": "8", "consumed": "1,000", "target": "2,000", "remaining": "1,000",
    ]
}

/// 一套预设的全部：身份、设置页要用的元数据、呈现、缩略图、音效、强度与裂纹选项。
/// 新增预设 = 新建一个实现它的文件 + 在 `Catalog.all` 里加一行，别的代码不用动。
///
/// 元数据与参数合成是场景无关的纯值，所以不挂在主线程上：场景的解码容错也要造得出出厂卡片。
/// 只有真正画东西的两个方法要求主线程。
protocol PresetTheme: Sendable {
    var preset: Preset { get }
    var title: String { get }
    var summary: String { get }
    var symbol: String { get }
    /// 这套预设渲染哪几个文案槽。
    var slots: [CopySlot] { get }
    /// 这套预设能选哪些强度；空数组表示它没有强度这个属性。
    var intensities: [Intensity] { get }
    /// 这套预设能选哪些裂纹；空数组表示它没有裂纹这个属性。
    var patterns: [CrackPattern] { get }
    var defaultIntensity: Intensity? { get }
    var defaultPattern: CrackPattern? { get }
    var windowLayout: WindowLayout { get }
    var hasShadow: Bool { get }
    /// 这套预设能出现在哪些场景。只有"某些场景才有意义"的预设才需要覆盖它，
    /// 例如日程专属的时间呈现：默认是所有场景。
    var scenes: Set<SceneID> { get }

    /// 这套预设的基础呈现参数。
    func presentation(for instance: PresetInstance) -> Presentation
    /// 这套预设自己的动画器；nil 表示只有静态呈现。
    @MainActor func makeAnimator(pattern: CrackPattern, reduceMotion: Bool) -> (any OverlayAnimator)?

    @MainActor @ViewBuilder func layout(_ context: ThemeContext) -> AnyView
    @MainActor @ViewBuilder func thumbnail(_ context: ThumbnailContext) -> AnyView
}

extension PresetTheme {
    var intensities: [Intensity] { [] }
    var patterns: [CrackPattern] { [] }
    var defaultIntensity: Intensity? { nil }
    var defaultPattern: CrackPattern? { nil }
    var hasShadow: Bool { false }
    var scenes: Set<SceneID> { Set(SceneID.allCases) }
    @MainActor func makeAnimator(pattern: CrackPattern, reduceMotion: Bool) -> (any OverlayAnimator)? { nil }
}

extension PresetInstance {
    /// 老实例没有裂纹字段：缺省即这套预设自己的默认值，预览与到点一致。
    func resolvedPattern(theme: any PresetTheme) -> CrackPattern? {
        theme.patterns.isEmpty ? nil : (pattern ?? theme.defaultPattern)
    }
}
