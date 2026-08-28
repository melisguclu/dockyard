// swift-tools-version:6.0

import PackageDescription

let package = Package(
    name: "DockKit",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DockKit", targets: ["DockKit"])
    ],
    dependencies: [
        .package(path: "../DockCore")
    ],
    targets: [
        .target(
            name: "DockKit",
            dependencies: [.product(name: "DockCore", package: "DockCore")],
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        ),
        .testTarget(
            name: "DockKitTests",
            dependencies: ["DockKit"],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
