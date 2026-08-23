// swift-tools-version:6.0

import PackageDescription

let package = Package(
    name: "DockCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DockCore", targets: ["DockCore"])
    ],
    targets: [
        .target(
            name: "DockCore",
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
