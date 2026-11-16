import AppKit

/// `BargeIn --export-icon <dir>`：把 BrandMark 落成 AppIcon.icns。
/// bundle.sh 在组装时调用，图标源始终是代码里的 BrandMark。
enum IconExport {
    static func run(directory: String) -> Int {
        let dir = URL(fileURLWithPath: directory, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let iconset = dir.appendingPathComponent("AppIcon.iconset", isDirectory: true)
        try? FileManager.default.removeItem(at: iconset)
        try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

        let variants: [(name: String, pixels: Int)] = [
            ("icon_16x16", 16), ("icon_16x16@2x", 32),
            ("icon_32x32", 32), ("icon_32x32@2x", 64),
            ("icon_128x128", 128), ("icon_128x128@2x", 256),
            ("icon_256x256", 256), ("icon_256x256@2x", 512),
            ("icon_512x512", 512), ("icon_512x512@2x", 1024),
        ]
        for variant in variants {
            guard let data = BrandMark.appIconPNG(pixels: variant.pixels) else {
                print("[bargein] icon render failed at \(variant.pixels)px")
                return 1
            }
            try? data.write(to: iconset.appendingPathComponent("\(variant.name).png"))
        }

        if let data = BrandMark.appIconPNG(pixels: 1024) {
            try? data.write(to: dir.appendingPathComponent("AppIcon-1024.png"))
        }
        if let data = menuBarPreviewPNG() {
            try? data.write(to: dir.appendingPathComponent("MenuBar-18@2x.png"))
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        process.arguments = ["-c", "icns", iconset.path, "-o", dir.appendingPathComponent("AppIcon.icns").path]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            print("[bargein] iconutil failed: \(error)")
            return 1
        }
        try? FileManager.default.removeItem(at: iconset)
        return process.terminationStatus == 0 ? 0 : 1
    }

    /// 18pt 菜单栏图放大 10 倍，铺浅色底，用于视觉检查。
    private static func menuBarPreviewPNG() -> Data? {
        let pixels = 36
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSColor(white: 0.96, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: CGFloat(pixels), height: CGFloat(pixels)).fill()
        BrandMark.menuBarImage().draw(
            in: NSRect(x: 0, y: 0, width: CGFloat(pixels), height: CGFloat(pixels))
        )
        return rep.representation(using: .png, properties: [:])
    }
}
