import BargeInCore

/// 日程场景：外部日历驱动的触发。业务模型见 ScheduleState / Subscription。
public enum ScheduleScene {
    public static let descriptor = SceneDescriptor(
        id: .schedule,
        title: "日程",
        summary: "按你订阅的日历提醒：事件开始前把你还给你",
        defaultTrigger: .events(leadMinutes: 5),
        defaultCopy: [
            .word: "{title}",
            .title: "{title}",
            .progress: "{start} 开始 · 还有 {minutes} 分钟",
        ],
        variableNames: ["title", "start", "minutes", "location"],
        completionLabel: "知道了",
        completionSymbol: "calendar",
        sampleValues: ["title": "Q4 产品评审", "start": "9:30", "minutes": "5", "location": "会议室 A"]
    )
}
