import Foundation

/// 场景的闭合集合。不是插件：加一个场景 = 加一个 case + 一份默认配置 + 一个场景模块。
public enum SceneID: String, Codable, CaseIterable, Hashable, Sendable {
    case water
    case activity
    case schedule
    case alarm
}

/// 场景无关的呈现资源之外的、这个场景自己的那点东西：
/// 名称、默认调度、默认文案、可用变量、完成动作的标签。
public struct SceneDescriptor: Sendable {
    public let id: SceneID
    public let title: String
    public let summary: String
    public let defaultTrigger: SceneTrigger
    public let defaultCopy: [CopySlot: String]
    public let variableNames: [String]
    /// 变量的样例值：缩略图与设置里的预览拿它填模板，真实提醒永远用当次的真实值。
    public let sampleValues: [String: String]
    public let completionLabel: String
    public let completionSymbol: String

    public init(
        id: SceneID,
        title: String,
        summary: String,
        defaultTrigger: SceneTrigger,
        defaultCopy: [CopySlot: String],
        variableNames: [String],
        completionLabel: String,
        completionSymbol: String,
        sampleValues: [String: String] = [:]
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.defaultTrigger = defaultTrigger
        self.defaultCopy = defaultCopy
        self.variableNames = variableNames
        self.sampleValues = sampleValues
        self.completionLabel = completionLabel
        self.completionSymbol = completionSymbol
    }
}

/// 一个场景的可持久化配置：触发来源、预设实例、账本、启用开关。
/// 场景私有的业务数据（喝水的配额、活动的次数、日程的订阅）不在里面，由各自的场景模块持有。
public struct SceneConfig: Codable, Equatable, Sendable {
    public var isEnabled: Bool
    public var trigger: SceneTrigger
    public var instances: [PresetInstance]
    public var activeInstanceID: UUID
    public var skipsToday: Int
    /// 节奏的另一边：切走时把原来那套存在这里，切回来原样还原。
    /// 只有「固定间隔 / 指定时刻」二选一的场景会用到。
    public var parkedRhythm: Schedule?

    public init(
        isEnabled: Bool,
        trigger: SceneTrigger,
        instances: [PresetInstance],
        activeInstanceID: UUID,
        skipsToday: Int = 0,
        parkedRhythm: Schedule? = nil
    ) {
        self.isEnabled = isEnabled
        self.trigger = trigger
        self.instances = instances
        self.activeInstanceID = activeInstanceID
        self.skipsToday = skipsToday
        self.parkedRhythm = parkedRhythm
    }

    /// 逐字段容错：`trigger` 是场景身份，读不出来交给上层整块回该场景出厂配置；
    /// 其余字段缺哪补哪，别让一个字段拖走这个场景的实例与账本。
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        trigger = try container.decode(SceneTrigger.self, forKey: .trigger)
        isEnabled = container.tolerant(Bool.self, forKey: .isEnabled, or: true)
        instances = container.tolerantArray(PresetInstance.self, forKey: .instances)
        activeInstanceID = container.tolerant(UUID.self, forKey: .activeInstanceID, or: UUID())
        skipsToday = container.tolerant(Int.self, forKey: .skipsToday, or: 0)
        parkedRhythm = container.tolerantOptional(Schedule.self, forKey: .parkedRhythm)
    }

    /// 固定间隔 / 指定时刻二选一：只换用哪一套，另一套留着，切回来原样还原。
    /// 已经在这一边就什么都不做——分段控件点当前项也会回调。
    public mutating func useRhythm(timesOfDay: Bool) {
        guard let current = trigger.rhythm, current.isTimesOfDay != timesOfDay else { return }
        // 存的不是要切过去的那一边（换过类的旧值）就当没存过，别把两种节奏搅在一起。
        let remembered = parkedRhythm.flatMap { $0.isTimesOfDay == timesOfDay ? $0 : nil }
        parkedRhythm = current
        trigger = .rhythm(
            remembered
                ?? (timesOfDay
                    ? .timesOfDay(Schedule.defaultTimesOfDay)
                    : .interval(minutes: Schedule.defaultIntervalMinutes))
        )
    }

    /// 出厂配置：卡片由预设目录提供，这里只负责装进一个场景。
    public static func makeDefault(
        trigger: SceneTrigger,
        isEnabled: Bool = true,
        catalog: [PresetInstance],
        defaultActive: Preset
    ) -> SceneConfig {
        SceneConfig(
            isEnabled: isEnabled,
            trigger: trigger,
            instances: catalog,
            activeInstanceID: catalog.first { $0.preset == defaultActive }?.id ?? catalog.first?.id ?? UUID()
        )
    }

    /// 解码后的收口：空实例列表回出厂卡；老存档缺哪张内置补哪张（追加在末尾，不动激活项）；
    /// 激活项丢了回出厂预设。卡片与"哪张出厂激活"都由预设目录决定，场景这一层不认具体预设。
    public mutating func normalize(catalog: [PresetInstance], defaultActive: Preset) {
        // 没有任何预设可用（配置错了）时不动现有数据，别把一个场景清空。
        guard !catalog.isEmpty else { return }

        // 这套预设在当前场景里没有意义：连同用户改过的副本一起清掉。
        let allowed = Set(catalog.map(\.preset))
        instances.removeAll { !allowed.contains($0.preset) }

        if instances.isEmpty {
            instances = catalog
        } else {
            for builtIn in catalog
            where !instances.contains(where: { $0.builtIn && $0.preset == builtIn.preset }) {
                instances.append(builtIn)
            }
        }
        if !instances.contains(where: { $0.id == activeInstanceID }) {
            activeInstanceID = instances.first { $0.preset == defaultActive }?.id ?? instances[0].id
        }
    }
}
