// swift-tools-version:6.0

import PackageDescription

let package = Package(
    name: "Dockyard",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Dockyard", targets: ["Dockyard"])
    ],
    dependencies: [
        .package(path: "Packages/DockCore"),
        .package(path: "Packages/DockKit")
    ],
    targets: [
        .executableTarget(
            name: "Dockyard",
            dependencies: [
                .product(name: "DockCore", package: "DockCore"),
                .product(name: "DockKit", package: "DockKit")
            ],
            path: "Dockyard",
            exclude: ["Info.plist", "Dockyard.entitlements", "Resources"],
            resources: [.process("Localization")],
            swiftSettings: [.swiftLanguageMode(.v6)]
        )
    ]
)
