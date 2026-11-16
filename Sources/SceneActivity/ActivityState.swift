import Foundation
import BargeInCore

/// 活动的业务模型：只记今天完成了几次。没有配额，不做久坐检测。
public struct ActivityState: Codable, Equatable, Sendable {
    public var doneToday: Int

    public init(doneToday: Int = 0) {
        self.doneToday = doneToday
    }

    /// 逐字段容错：新版本加字段不会把今天的次数一起吞掉。
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        doneToday = container.tolerant(Int.self, forKey: .doneToday, or: 0)
    }

    /// 活动场景没有可中断的进度量，文案里不提供变量。
    public var copyValues: [String: String] { [:] }
}
