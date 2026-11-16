import AppKit

/// 品牌图形：节律脉冲。产品是身体节律提醒，不绑定喝水的语义。
/// 菜单栏模板图与 App 图标出自同一套图形；改品牌只改这里。
enum BrandMark {
    // MARK: - 菜单栏

    /// 18pt 模板图，单色跟随系统深浅色。波形双峰，单色下比单尖峰更不容易读成加号。
    static func menuBarImage() -> NSImage {
        let side: CGFloat = 18
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { _ in
            let path = NSBezierPath()
            path.move(to: NSPoint(x: 1.6, y: 9))
            path.line(to: NSPoint(x: 4.6, y: 9))
            path.line(to: NSPoint(x: 5.7, y: 4.4))
            path.line(to: NSPoint(x: 7.2, y: 13.6))
            path.line(to: NSPoint(x: 8.7, y: 4.4))
            path.line(to: NSPoint(x: 10.2, y: 13.6))
            path.line(to: NSPoint(x: 11.3, y: 9))
            path.line(to: NSPoint(x: 16.4, y: 9))
            path.lineWidth = 2.0
            path.lineCapStyle = .round
            path.lineJoinStyle = .round
            NSColor.black.setStroke()
            path.stroke()
            return true
        }
        image.isTemplate = true
        return image
    }

    // MARK: - App 图标

    /// 按像素尺寸离屏渲染，供 `--export-icon` 生成 iconset 与预览。
    static func appIconPNG(pixels: Int) -> Data? {
        guard pixels > 0,
              let rep = NSBitmapImageRep(
                  bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                  bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                  colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
              )
        else { return nil }
        rep.size = NSSize(width: pixels, height: pixels)

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        drawAppIcon(in: NSRect(x: 0, y: 0, width: CGFloat(pixels), height: CGFloat(pixels)))
        return rep.representation(using: .png, properties: [:])
    }

    /// 以 1024 为单位设计，再缩放到目标尺寸，任意尺寸都按矢量重绘。
    private static func drawAppIcon(in rect: NSRect) {
        let scale = rect.width / 1024
        let s = { (value: CGFloat) in value * scale }

        // Big Sur 比例：824 主体、100 留白、185 圆角。
        let body = NSRect(x: rect.minX + s(100), y: rect.minY + s(100), width: s(824), height: s(824))
        let base = NSBezierPath(roundedRect: body, xRadius: s(185), yRadius: s(185))

        let gradient = NSGradient(colors: [NSColor(hexValue: 0x22D3EE), NSColor(hexValue: 0x0EA5E9)])!
        gradient.draw(in: base, angle: -60)

        // 环：节律本身，压暗留出层次。
        let ring = NSBezierPath(
            ovalIn: NSRect(
                x: rect.minX + s(512 - 204), y: rect.minY + s(512 - 204),
                width: s(408), height: s(408)
            )
        )
        ring.lineWidth = s(56)
        NSColor.white.withAlphaComponent(0.30).setStroke()
        ring.stroke()

        // 脉冲：一次到点的打断，纯白。与菜单栏同一波形。
        let pulse = NSBezierPath()
        pulse.move(to: NSPoint(x: rect.minX + s(300), y: rect.minY + s(512)))
        pulse.line(to: NSPoint(x: rect.minX + s(400), y: rect.minY + s(512)))
        pulse.line(to: NSPoint(x: rect.minX + s(432), y: rect.minY + s(392)))
        pulse.line(to: NSPoint(x: rect.minX + s(470), y: rect.minY + s(632)))
        pulse.line(to: NSPoint(x: rect.minX + s(508), y: rect.minY + s(392)))
        pulse.line(to: NSPoint(x: rect.minX + s(546), y: rect.minY + s(632)))
        pulse.line(to: NSPoint(x: rect.minX + s(578), y: rect.minY + s(512)))
        pulse.line(to: NSPoint(x: rect.minX + s(724), y: rect.minY + s(512)))
        pulse.lineWidth = s(60)
        pulse.lineCapStyle = .round
        pulse.lineJoinStyle = .round
        NSColor.white.setStroke()
        pulse.stroke()
    }
}
