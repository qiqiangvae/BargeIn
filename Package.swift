// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BargeIn",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "BargeInCore",
            path: "Sources/BargeInCore"
        ),
        .target(
            name: "SceneWater",
            dependencies: ["BargeInCore"],
            path: "Sources/SceneWater"
        ),
        .target(
            name: "SceneActivity",
            dependencies: ["BargeInCore"],
            path: "Sources/SceneActivity"
        ),
        .target(
            name: "SceneSchedule",
            dependencies: ["BargeInCore"],
            path: "Sources/SceneSchedule"
        ),
        .target(
            name: "SceneAlarm",
            dependencies: ["BargeInCore"],
            path: "Sources/SceneAlarm"
        ),
        .executableTarget(
            name: "BargeIn",
            dependencies: ["BargeInCore", "SceneWater", "SceneActivity", "SceneSchedule", "SceneAlarm"],
            path: "Sources/BargeIn"
        ),
    ]
)
