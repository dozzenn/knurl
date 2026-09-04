// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MacroPadMac",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "MacroPadCore"),
        .executableTarget(name: "macropad-probe", dependencies: ["MacroPadCore"]),
        .executableTarget(
            name: "MacroPadApp",
            dependencies: ["MacroPadCore"],
            swiftSettings: [.unsafeFlags(["-parse-as-library"])]
        ),
    ]
)
