import Foundation
import BargeInCore

/// 喝水的业务模型：累计量。目标、单杯量、今天已喝。
public struct WaterState: Codable, Equatable, Sendable {
    public var targetML: Int
    public var cupML: Int
    public var consumedML: Int

    public init(targetML: Int = 2000, cupML: Int = 250, consumedML: Int = 0) {
        self.targetML = targetML
        self.cupML = cupML
        self.consumedML = consumedML
    }

    /// 逐字段容错：新版本加字段不会把今天的进度一起吞掉。
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = WaterState()
        targetML = container.tolerant(Int.self, forKey: .targetML, or: fallback.targetML)
        cupML = container.tolerant(Int.self, forKey: .cupML, or: fallback.cupML)
        consumedML = container.tolerant(Int.self, forKey: .consumedML, or: fallback.consumedML)
    }

    /// 当天是否已喝够目标。consumedML 已由 StateStore.refreshDay 保证属于当天。
    public var isCompleted: Bool {
        targetML > 0 && consumedML >= targetML
    }

    /// 今日进度，0...1，用于进度环。
    public var progress: Double {
        guard targetML > 0 else { return 0 }
        return min(1, Double(consumedML) / Double(targetML))
    }

    /// 这个场景给文案模板提供的变量。
    public var copyValues: [String: String] {
        // 千分位与 popover 环里的大数字一致：1000 和 1,000 混着出现最扎眼。
        [
            "consumed": consumedML.formatted(),
            "target": targetML.formatted(),
            "remaining": max(0, targetML - consumedML).formatted(),
        ]
    }
}
