import AppKit
import BargeInCore

/// 循环播放系统提示音，音量逐步抬高；到 100% 后保持。
@MainActor
final class SoundPlayer {
    private var sound: NSSound?
    private var timer: Timer?
    private var volume: Float = 1

    private static let candidates = ["Ping", "Glass", "Hero", "Tink"]

    func start(_ kind: ReminderSound) {
        stop()
        guard kind != .none else { return }
        guard let loaded = Self.loadSystemSound() else { return }
        sound = loaded

        switch kind {
        case .none:
            return
        case .chime:
            loaded.volume = 0.7
            loaded.play()
        case .escalating:
            volume = 0.3
            play()
            timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            RunLoop.main.add(timer!, forMode: .common)
        case .alarm:
            volume = 1
            play()
            timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.play() }
            }
            RunLoop.main.add(timer!, forMode: .common)
        case .shatter:
            // 玻璃碎：满音量、只响一次，跟着炸点延后 0.36 秒
            sound?.stop()
            sound = nil
            guard let glass = Self.loadSystemSound(named: "Glass") else { return }
            sound = glass
            volume = 1
            timer = Timer.scheduledTimer(withTimeInterval: 0.36, repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.play() }
            }
            RunLoop.main.add(timer!, forMode: .common)
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        sound?.stop()
        sound = nil
    }

    private func tick() {
        volume = min(1, volume + 0.15)
        play()
    }

    private func play() {
        sound?.volume = volume
        sound?.play()
    }

    private static func loadSystemSound() -> NSSound? {
        for name in candidates {
            if let sound = loadSystemSound(named: name) { return sound }
        }
        return nil
    }

    private static func loadSystemSound(named name: String) -> NSSound? {
        let path = "/System/Library/Sounds/\(name).aiff"
        guard FileManager.default.fileExists(atPath: path),
              let sound = NSSound(contentsOfFile: path, byReference: true) else { return nil }
        sound.loops = false
        return sound
    }
}
