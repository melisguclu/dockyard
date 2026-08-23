// swift-tools-version:6.0

import PackageDescription

let package = Package(
    name: "DockKit",
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
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
