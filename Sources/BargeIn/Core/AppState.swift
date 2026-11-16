import Foundation
import BargeInCore
import SceneWater
import SceneActivity
import SceneSchedule
import SceneAlarm

/// 全部持久化状态。新增字段一律给默认值，并在解码时容忍缺失——旧存档能不能读，
/// 由 `Decoding.swift` 的逐字段容错保证；读不出来的坏档在 `StateStore` 里另存一份。
struct AppState: Codable, Equatable {
    var waterConfig: SceneConfig
    var activityConfig: SceneConfig
    var scheduleConfig: SceneConfig
    var alarmConfig: SceneConfig

    var water: WaterState
    var activity: ActivityState
    var schedule: ScheduleState
    var alarm: AlarmState

    var workStart: TimeOfDay = .nineAM
    var workEnd: TimeOfDay = .sixPM
    var restDays: Set<Int> = [1, 7]
    var pausedUntil: Date?
    var lastActiveDate: Date = Date()
    var hasOnboarded: Bool = false
    /// 启动时与每 24 小时问一次 GitHub 有没有新版本；关掉后 App 不再为更新联网。
    var checkForUpdates: Bool = true
    /// 已经用温柔卡通知过的版本。同一个版本只提醒一次。
    var lastNotifiedVersion: String?

    init() {
        water = WaterState()
        activity = ActivityState()
        schedule = ScheduleState()
        alarm = AlarmState()
        waterConfig = Self.defaultConfig(trigger: WaterScene.descriptor.defaultTrigger, scene: .water)
        activityConfig = Self.defaultConfig(trigger: ActivityScene.descriptor.defaultTrigger, scene: .activity)
        // 日程出厂停用：没有订阅就没有数据，开了也只是一个空场景。
        scheduleConfig = Self.defaultConfig(
            trigger: ScheduleScene.descriptor.defaultTrigger,
            scene: .schedule,
            isEnabled: false
        )
        // 闹钟同理：没有闹钟就没有数据。
        alarmConfig = Self.defaultConfig(
            trigger: AlarmScene.descriptor.defaultTrigger,
            scene: .alarm,
            isEnabled: false
        )
    }

    func config(_ scene: SceneID) -> SceneConfig {
        switch scene {
        case .water: waterConfig
        case .activity: activityConfig
        case .schedule: scheduleConfig
        case .alarm: alarmConfig
        }
    }

    mutating func setConfig(_ config: SceneConfig, for scene: SceneID) {
        switch scene {
        case .water: waterConfig = config
        case .activity: activityConfig = config
        case .schedule: scheduleConfig = config
        case .alarm: alarmConfig = config
        }
    }
}

extension AppState {
    /// 顶层也逐字段容错：某个场景整块读不出来，只回这个场景的出厂配置，
    /// 不牵连同一次存档里的其它场景与进度。
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = AppState()

        waterConfig = container.tolerant(SceneConfig.self, forKey: .waterConfig, or: fallback.waterConfig)
        activityConfig = container.tolerant(SceneConfig.self, forKey: .activityConfig, or: fallback.activityConfig)
        scheduleConfig = container.tolerant(SceneConfig.self, forKey: .scheduleConfig, or: fallback.scheduleConfig)
        alarmConfig = container.tolerant(SceneConfig.self, forKey: .alarmConfig, or: fallback.alarmConfig)
        water = container.tolerant(WaterState.self, forKey: .water, or: fallback.water)
        activity = container.tolerant(ActivityState.self, forKey: .activity, or: fallback.activity)
        schedule = container.tolerant(ScheduleState.self, forKey: .schedule, or: fallback.schedule)
        alarm = container.tolerant(AlarmState.self, forKey: .alarm, or: fallback.alarm)
        workStart = container.tolerant(TimeOfDay.self, forKey: .workStart, or: fallback.workStart)
        workEnd = container.tolerant(TimeOfDay.self, forKey: .workEnd, or: fallback.workEnd)
        restDays = container.tolerant(Set<Int>.self, forKey: .restDays, or: fallback.restDays)
        pausedUntil = container.tolerantOptional(Date.self, forKey: .pausedUntil)
        lastActiveDate = container.tolerant(Date.self, forKey: .lastActiveDate, or: fallback.lastActiveDate)
        hasOnboarded = container.tolerant(Bool.self, forKey: .hasOnboarded, or: fallback.hasOnboarded)
        checkForUpdates = container.tolerant(Bool.self, forKey: .checkForUpdates, or: fallback.checkForUpdates)
        lastNotifiedVersion = container.tolerantOptional(String.self, forKey: .lastNotifiedVersion)

        // 解码后的收口：空实例列表、丢了的激活项都在这里回出厂；不改动读出来的业务数据。
        waterConfig.normalize(catalog: Catalog.makeInstances(for: .water), defaultActive: Catalog.defaultActive)
        activityConfig.normalize(catalog: Catalog.makeInstances(for: .activity), defaultActive: Catalog.defaultActive)
        scheduleConfig.normalize(catalog: Catalog.makeInstances(for: .schedule), defaultActive: Catalog.defaultActive)
        alarmConfig.normalize(catalog: Catalog.makeInstances(for: .alarm), defaultActive: Catalog.defaultActive)
    }
}


extension AppState {
    /// 每个场景各造一套卡片：卡片 id 是场景内的身份，四个场景不共用同一批 UUID。
    private static func defaultConfig(
        trigger: SceneTrigger,
        scene: SceneID,
        isEnabled: Bool = true
    ) -> SceneConfig {
        SceneConfig.makeDefault(
            trigger: trigger,
            isEnabled: isEnabled,
            catalog: Catalog.makeInstances(for: scene),
            defaultActive: Catalog.defaultActive
        )
    }
}
