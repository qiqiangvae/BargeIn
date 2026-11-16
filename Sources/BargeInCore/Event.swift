import Foundation

/// 一条事件发生的身份：订阅里的 UID + 发生时刻。
/// 重复事件的一次发生与另一家订阅里的同名事件因此不会互相吃掉。
public struct EventKey: Hashable, Codable, Sendable, Comparable {
    public var uid: String
    public var start: Date

    public init(uid: String, start: Date) {
        self.uid = uid
        self.start = start
    }

    /// 落盘用的稳定字符串。
    public var storageKey: String { "\(uid)|\(Int(start.timeIntervalSince1970))" }

    public init?(storageKey: String) {
        guard let separator = storageKey.lastIndex(of: "|") else { return nil }
        let uid = String(storageKey[storageKey.startIndex..<separator])
        guard !uid.isEmpty,
              let epoch = TimeInterval(storageKey[storageKey.index(after: separator)...])
        else { return nil }
        self.uid = uid
        self.start = Date(timeIntervalSince1970: epoch)
    }

    public static func < (lhs: EventKey, rhs: EventKey) -> Bool {
        lhs.start == rhs.start ? lhs.uid < rhs.uid : lhs.start < rhs.start
    }
}

/// 订阅日历里的一次事件发生。日程场景的触发单位就是它，不是"一场会"这个概念本身。
public struct EventOccurrence: Equatable, Sendable, Identifiable {
    public var subscriptionID: UUID
    public var uid: String
    public var start: Date
    public var title: String
    public var location: String?

    public init(
        subscriptionID: UUID,
        uid: String,
        start: Date,
        title: String,
        location: String? = nil
    ) {
        self.subscriptionID = subscriptionID
        self.uid = uid
        self.start = start
        self.title = title
        self.location = location
    }

    public var id: EventKey { key }

    public var key: EventKey { EventKey(uid: uid, start: start) }
}

/// 队列里的一条待呈现提醒。喝水与活动只有场景，日程按事件各一条。
public struct ReminderKey: Hashable, Sendable {
    public var scene: SceneID
    public var event: EventKey?

    public init(scene: SceneID, event: EventKey? = nil) {
        self.scene = scene
        self.event = event
    }

    /// 喝水与活动：整场景一条。
    public static func sceneOnly(_ scene: SceneID) -> ReminderKey {
        ReminderKey(scene: scene)
    }
}
