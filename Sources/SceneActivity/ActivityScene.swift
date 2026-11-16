import BargeInCore

/// 活动场景：到点起身舒展，不设每日目标。业务模型见 ActivityState。
public enum ActivityScene {
    public static let descriptor = SceneDescriptor(
        id: .activity,
        title: "活动",
        summary: "到点起身舒展，不设每日目标",
        defaultTrigger: .rhythm(.timesOfDay([
            TimeOfDay(hour: 10, minute: 30),
            TimeOfDay(hour: 14, minute: 30),
            TimeOfDay(hour: 16, minute: 30),
        ])),
        defaultCopy: [
            .word: "该活动了",
            .title: "该活动了",
            .progress: "站起来，活动 1 分钟",
        ],
        variableNames: [],
        completionLabel: "活动了",
        completionSymbol: "figure.walk"
    )
}
