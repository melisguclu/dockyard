import DockCore
import DockKit
import Foundation
import Testing

@Suite("Dragging a tile along the bar moves it only where the Dock's own regions allow")
struct DockReorderPolicyTests {
    private func application(_ name: String) -> DockTile {
        DockTile(
            id: .bundle("com.example.\(name)"),
            kind: .application,
            label: name,
            url: URL(fileURLWithPath: "/Applications/\(name).app"),
            bundleIdentifier: "com.example.\(name)",
            isPinned: true
        )
    }

    private let separator = DockTile(id: .builtin(.separator), kind: .separator, label: "")
    private let trash = DockTile(id: .builtin(.trash), kind: .trash(isEmpty: true), label: "Trash")
    private let window = DockTile(id: .window(3), kind: .minimizedWindow, label: "Draft")
    private let folder = DockTile(
        id: .path("file:///Users/tester/Downloads"),
        kind: .folder(FolderPresentation()),
        label: "Downloads",
        url: URL(fileURLWithPath: "/Users/tester/Downloads")
    )

    private var bar: [DockTile] {
        [application("Safari"), application("Mail"), application("Notes"), separator, window, folder, trash]
    }

    @Test("A tile lands where the pointer is")
    func movesToTheTarget() {
        let result = DockReorderPolicy.reordered(bar, moving: .bundle("com.example.Notes"), to: 0)

        #expect(result?.map(\.label) == ["Notes", "Safari", "Mail", "", "Draft", "Downloads", "Trash"])
    }

    @Test("Only applications, folders, and web locations can be dragged")
    func onlyReorderableTilesDrag() {
        #expect(DockReorderPolicy.canDrag(application("Safari")))
        #expect(DockReorderPolicy.canDrag(folder))
        #expect(DockReorderPolicy.canDrag(separator) == false)
        #expect(DockReorderPolicy.canDrag(trash) == false)
        #expect(DockReorderPolicy.canDrag(window) == false)
    }

    @Test("A drag stops at the separator instead of crossing it")
    func separatorIsAWall() {
        #expect(DockReorderPolicy.reordered(bar, moving: .bundle("com.example.Safari"), to: 5) == nil)
        #expect(DockReorderPolicy.reordered(bar, moving: .path("file:///Users/tester/Downloads"), to: 1) == nil)
    }

    @Test("Dropping onto the separator, the Trash, or a minimized window does nothing")
    func fixedTilesRefuseTheDrop() {
        #expect(DockReorderPolicy.reordered(bar, moving: .bundle("com.example.Safari"), to: 3) == nil)
        #expect(DockReorderPolicy.reordered(bar, moving: .path("file:///Users/tester/Downloads"), to: 6) == nil)
        #expect(DockReorderPolicy.reordered(bar, moving: .path("file:///Users/tester/Downloads"), to: 4) == nil)
    }

    @Test("A drop on the tile's own place, or outside the bar, changes nothing")
    func degenerateTargets() {
        #expect(DockReorderPolicy.reordered(bar, moving: .bundle("com.example.Safari"), to: 0) == nil)
        #expect(DockReorderPolicy.reordered(bar, moving: .bundle("com.example.Safari"), to: 99) == nil)
        #expect(DockReorderPolicy.reordered(bar, moving: .bundle("com.example.Absent"), to: 1) == nil)
    }

    @Test("A bar with no separator is one region")
    func barWithoutASeparator() {
        let tiles = [application("Safari"), application("Mail")]

        let result = DockReorderPolicy.reordered(tiles, moving: .bundle("com.example.Mail"), to: 0)

        #expect(result?.map(\.label) == ["Mail", "Safari"])
    }

    @Test("A drag has to travel before it becomes a reorder rather than a click")
    func thresholdIsDeliberate() {
        #expect(DockContentView.reorderThreshold >= 4)
    }
}
