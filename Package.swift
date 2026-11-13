// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "UsageBar",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "UsageBarCore"),
        .executableTarget(name: "UsageBar", dependencies: ["UsageBarCore"]),
        .testTarget(
            name: "UsageBarCoreTests",
            dependencies: ["UsageBarCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
