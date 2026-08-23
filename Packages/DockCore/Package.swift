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
        ),
        .testTarget(
            name: "DockCoreTests",
            dependencies: ["DockCore"],
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
