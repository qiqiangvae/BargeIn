import Foundation

/// 文案槽：预设实例里一段可被改写的文字位置。
public enum CopySlot: String, Codable, CaseIterable, Hashable, Sendable {
    case word       // 大字墙铺满的重复词
    case title      // 卡片抬头 / 碎裂面板的标题
    case progress   // 进度行，模板里可含变量

    public var label: String {
        switch self {
        case .word: "大字词"
        case .title: "标题"
        case .progress: "进度"
        }
    }
}

/// 强度：哪些预设能配、配出什么，由那套预设自己决定。
public enum Intensity: String, Codable, CaseIterable, Sendable {
    case standard
    case strict

    public var title: String {
        switch self {
        case .standard: "标准"
        case .strict: "强硬"
        }
    }
}

/// 预设身份。这一层只认 id，不认识任何一套预设长什么样——
/// 元数据、呈现、音效与强度选项都在 `Sources/BargeIn/Presentation/Themes/` 里，
/// 新增一套预设只加一个 theme 文件 + `Catalog.all` 里一行。
public struct Preset: RawRepresentable, Codable, Hashable, Sendable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public static let gentle = Preset(rawValue: "gentle")
    public static let wall = Preset(rawValue: "wall")
    public static let shatter = Preset(rawValue: "shatter")
}

/// 预设实例：某个预设在一个场景下被采用后的存在，也就是设置里的一张卡片。
public struct PresetInstance: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var preset: Preset
    public var name: String
    public var intensity: Intensity?
    public var copyOverrides: [String: String]
    public var builtIn: Bool

    public init(
        id: UUID = UUID(),
        preset: Preset,
        name: String,
        intensity: Intensity?,
        copyOverrides: [String: String] = [:],
        builtIn: Bool = false
    ) {
        self.id = id
        self.preset = preset
        self.name = name
        self.intensity = intensity
        self.copyOverrides = copyOverrides
        self.builtIn = builtIn
    }

    /// 逐字段容错：`preset` 是这张卡的身份，读不出来就丢掉这张卡（上层按条容错），
    /// 其余字段缺哪补哪。缺了 `name` 时回落成 id，界面会用这套预设自己的标题覆盖它。
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        preset = try container.decode(Preset.self, forKey: .preset)
        id = container.tolerant(UUID.self, forKey: .id, or: UUID())
        name = container.tolerant(String.self, forKey: .name, or: preset.rawValue)
        intensity = container.tolerantOptional(Intensity.self, forKey: .intensity)
        copyOverrides = container.tolerant([String: String].self, forKey: .copyOverrides, or: [:])
        builtIn = container.tolerant(Bool.self, forKey: .builtIn, or: false)
    }
}
