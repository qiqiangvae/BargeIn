import SwiftUI
import BargeInCore

/// 设置页预设卡上的微缩呈现：这个产品的主张是"提醒长什么样就是产品"，
/// 所以卡片直接给出那套呈现的样子，而不是一个图标加一句描述。
@MainActor
struct PresetThumbnail: View {
    let preset: Preset
    let descriptor: SceneDescriptor

    var body: some View {
        Catalog.theme(for: preset)
            .thumbnail(ThumbnailContext(descriptor: descriptor))
            .frame(maxWidth: .infinity)
            .frame(height: 66)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .strokeBorder(Theme.stroke, lineWidth: 1)
            )
            .accessibilityHidden(true)
    }
}
