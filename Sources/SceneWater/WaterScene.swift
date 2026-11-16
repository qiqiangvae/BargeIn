import BargeInCore

/// 喝水场景：业务模型见 WaterState；这里只声明它与其他场景不同的那点东西。
public enum WaterScene {
    public static let descriptor = SceneDescriptor(
        id: .water,
        title: "喝水",
        summary: "按节奏提醒，累计今天喝到多少",
        defaultTrigger: .rhythm(.interval(minutes: 60)),
        defaultCopy: [
            .word: "该喝水了",
            .title: "该喝水了",
            .progress: "{consumed} / {target} ml",
        ],
        variableNames: ["consumed", "target", "remaining"],
        completionLabel: "喝了",
        completionSymbol: "drop.fill"
    )
}
