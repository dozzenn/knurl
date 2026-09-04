// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Knurl",
    platforms: [.macOS(.v13)],
    targets: [
        .target(name: "KnurlCore"),
        .executableTarget(name: "knurl-probe", dependencies: ["KnurlCore"]),
        .executableTarget(
            name: "KnurlApp",
            dependencies: ["KnurlCore"],
            swiftSettings: [.unsafeFlags(["-parse-as-library"])]
        ),
    ]
)
