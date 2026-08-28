import DockCore
import Foundation

enum TileFactory {
    static func application(_ name: String) -> DockTile {
        DockTile(
            id: .bundle("com.example.\(name)"),
            kind: .application,
            label: name,
            url: URL(fileURLWithPath: "/Applications/\(name).app"),
            bundleIdentifier: "com.example.\(name)",
            isPinned: true
        )
    }

    static func applications(_ count: Int) -> [DockTile] {
        (0..<count).map { application("App\($0)") }
    }

    static let separator = DockTile(id: .builtin(.separator), kind: .separator, label: "")

    static func spacer(_ width: SpacerWidth, index: Int = 0) -> DockTile {
        DockTile(id: .builtin(.spacer(index: index)), kind: .spacer(width: width), label: "")
    }

    static let trash = DockTile(id: .builtin(.trash), kind: .trash(isEmpty: true), label: "Trash")

    static func folder(
        _ name: String = "Downloads",
        presentation: FolderPresentation = FolderPresentation()
    ) -> DockTile {
        DockTile(
            id: .path("file:///Users/tester/\(name)/"),
            kind: .folder(presentation),
            label: name,
            url: URL(fileURLWithPath: "/Users/tester/\(name)", isDirectory: true),
            isPinned: true
        )
    }
}

enum Displays {
    static let builtIn = CGRect(x: 0, y: 0, width: 1512, height: 982)
    static let leftOfBuiltIn = CGRect(x: -2560, y: -300, width: 2560, height: 1440)
    static let aboveBuiltIn = CGRect(x: 0, y: 982, width: 5120, height: 2880)
}
