import Foundation

public enum ReminderSound: String, Codable, Sendable {
    case none
    case chime        // 单次
    case escalating   // 30% 起，每 2 秒加一档
    case alarm        // 直接 100%
    case shatter      // 玻璃碎：满音量一次，不重复
}

/// 一次提醒的完整体验参数，完全由预设实例解析而来：强度、文案都是实例自己的属性。
/// 这里的 `preset` 只是"谁来渲染"，具体长什么样由那套预设自己决定。
public struct Presentation: Equatable, Sendable {
    public var preset: Preset
    public var sound: ReminderSound
    public var allowsPostpone: Bool
    public var dismissDelay: TimeInterval
    public var interruptNeedsHold: Bool

    public init(
        preset: Preset,
        sound: ReminderSound,
        allowsPostpone: Bool,
        dismissDelay: TimeInterval,
        interruptNeedsHold: Bool
    ) {
        self.preset = preset
        self.sound = sound
        self.allowsPostpone = allowsPostpone
        self.dismissDelay = dismissDelay
        self.interruptNeedsHold = interruptNeedsHold
    }
}
