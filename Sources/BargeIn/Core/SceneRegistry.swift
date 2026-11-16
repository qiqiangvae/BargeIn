import Foundation
import BargeInCore
import SceneWater
import SceneActivity
import SceneSchedule
import SceneAlarm

/// 内置场景的静态装配。不是插件注册表：这里就是写明谁是谁。
enum SceneRegistry {
    static let all: [SceneDescriptor] = [
        WaterScene.descriptor,
        ActivityScene.descriptor,
        ScheduleScene.descriptor,
        AlarmScene.descriptor,
    ]

    private static let byID: [SceneID: SceneDescriptor] = Dictionary(
        uniqueKeysWithValues: all.map { ($0.id, $0) }
    )

    static func descriptor(_ id: SceneID) -> SceneDescriptor {
        byID[id]!
    }
}
