import BargeInCore

/// 闹钟场景：用户自己定下时刻的提醒。业务模型见 02/03。
public enum AlarmScene {
    public static let descriptor = SceneDescriptor(
        id: .alarm,
        title: "闹钟",
        summary: "你自己定的时刻：到点用同一套呈现把你拽出来",
        defaultTrigger: .alarms,
        defaultCopy: [
            .word: "{title}",
            .title: "{title}",
            .progress: "{start}",
        ],
        variableNames: ["title", "start"],
        completionLabel: "知道了",
        completionSymbol: "alarm",
        sampleValues: ["title": "点外卖", "start": "11:30"]
    )
}
