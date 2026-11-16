import SwiftUI
import BargeInCore

/// 预设目录：新增一套提醒预设，唯一要动的地方。
/// 加一套预设 = 新建一个实现 `PresetTheme` 的文件，然后在 `all` 里加一行。
enum Catalog {
    static let all: [any PresetTheme] = [
        GentleTheme(),
        WallTheme(),
        ShatterTheme(),
    ]

    /// 出厂选中哪一套。
    static let defaultActive: Preset = .wall

    /// 认不出的 id 回落第一套：存档里留着一套已经删掉的预设时，至少还能弹出一条提醒。
    static func theme(for preset: Preset) -> any PresetTheme {
        all.first { $0.preset == preset } ?? all[0]
    }

    /// 某个场景支持的预设。
    static func themes(for scene: SceneID) -> [any PresetTheme] {
        all.filter { $0.scenes.contains(scene) }
    }

    /// 某个实例的呈现参数：预设自己的基础参数，强度由实例带进来。
    static func presentation(for instance: PresetInstance) -> Presentation {
        theme(for: instance.preset).presentation(for: instance)
    }

    /// 出厂卡片：只放这个场景支持的预设。
    static func makeInstances(for scene: SceneID) -> [PresetInstance] {
        themes(for: scene).map {
            PresetInstance(
                preset: $0.preset,
                name: $0.title,
                intensity: $0.defaultIntensity,
                builtIn: true
            )
        }
    }
}
