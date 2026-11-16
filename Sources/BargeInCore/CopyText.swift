import Foundation

/// 一帧提醒最终要显示的三行字。
public struct ReminderCopy: Equatable, Sendable {
    public var title: String
    public var word: String
    public var progress: String

    public init(title: String, word: String, progress: String) {
        self.title = title
        self.word = word
        self.progress = progress
    }

    public static func make(
        instance: PresetInstance,
        scene: SceneDescriptor,
        values: [String: String]
    ) -> ReminderCopy {
        ReminderCopy(
            title: CopyText.text(.title, instance: instance, scene: scene, values: values),
            word: CopyText.text(.word, instance: instance, scene: scene, values: values),
            progress: CopyText.text(.progress, instance: instance, scene: scene, values: values)
        )
    }
}

/// 文案解析：实例覆盖 > 场景默认。预设是内置的，它的默认文案就是场景默认。
public enum CopyText {
    public static func defaultText(_ slot: CopySlot, scene: SceneDescriptor) -> String {
        scene.defaultCopy[slot] ?? ""
    }

    /// 编辑器里显示的那份模板本身，变量不替换。
    public static func template(
        _ slot: CopySlot,
        instance: PresetInstance,
        scene: SceneDescriptor
    ) -> String {
        guard let value = instance.copyOverrides[slot.rawValue], !value.isEmpty else {
            return defaultText(slot, scene: scene)
        }
        return value
    }

    /// 渲染用：先把变量填进去；含当前场景不提供的变量时，整段回落到默认文案。
    public static func text(
        _ slot: CopySlot,
        instance: PresetInstance,
        scene: SceneDescriptor,
        values: [String: String]
    ) -> String {
        let template = template(slot, instance: instance, scene: scene)
        guard !hasUnknownVariables(template, scene: scene) else {
            return substitute(defaultText(slot, scene: scene), values)
        }
        return substitute(template, values)
    }

    public static func hasUnknownVariables(_ text: String, scene: SceneDescriptor) -> Bool {
        placeholders(in: text).contains { !scene.variableNames.contains($0) }
    }

    /// 逐个 `{变量}` 扫描，`replace` 决定这个变量换成什么。
    private static func render(_ text: String, _ replace: (String) -> String) -> String {
        var result = ""
        var rest = text[...]
        while let open = rest.firstIndex(of: "{"),
              let close = rest[open...].firstIndex(of: "}") {
            result += rest[rest.startIndex..<open]
            let name = String(rest[rest.index(after: open)..<close])
            result += replace(name)
            rest = rest[rest.index(after: close)...]
        }
        return result + rest
    }

    private static func placeholders(in text: String) -> [String] {
        var result: [String] = []
        _ = render(text) { name in
            if !name.isEmpty { result.append(name) }
            return ""
        }
        return result
    }

    private static func substitute(_ text: String, _ values: [String: String]) -> String {
        render(text) { values[$0] ?? "{\($0)}" }
    }
}
