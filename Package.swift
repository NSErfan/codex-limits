// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "CodexLimits",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "CodexLimits", targets: ["CodexLimits"]),
        .library(name: "CodexWidgetKit", type: .static, targets: ["CodexWidgetKit"])
    ],
    targets: [
        .target(name: "CodexWidgetKit", swiftSettings: [.unsafeFlags(["-application-extension"])]),
        .executableTarget(name: "CodexLimits", dependencies: ["CodexWidgetKit"]),
        .testTarget(name: "CodexLimitsTests", dependencies: ["CodexLimits"]),
        .testTarget(name: "CodexWidgetKitTests", dependencies: ["CodexWidgetKit"])
    ]
)
