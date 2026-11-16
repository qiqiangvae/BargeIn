import AppKit

setbuf(stdout, nil)

if CommandLine.arguments.contains("--selftest") {
    exit(SelfTest.run() ? 0 : 1)
}

if CommandLine.arguments.contains("--calendar-probe") {
    exit(CalendarProbe.run(CommandLine.arguments))
}

if let index = CommandLine.arguments.firstIndex(of: "--snapshot") {
    _ = NSApplication.shared
    let dir = CommandLine.arguments.indices.contains(index + 1) ? CommandLine.arguments[index + 1] : "snapshots"
    exit(Int32(DevSnapshot.run(directory: dir)))
}

if let index = CommandLine.arguments.firstIndex(of: "--export-icon") {
    let dir = CommandLine.arguments.indices.contains(index + 1) ? CommandLine.arguments[index + 1] : "."
    exit(Int32(IconExport.run(directory: dir)))
}

let app = NSApplication.shared
let appDelegate = AppDelegate()
app.delegate = appDelegate
// 与 Info.plist 的 LSUIElement 等价；`swift run` 没有 bundle 时也能不占 Dock。
app.setActivationPolicy(.accessory)
app.run()
