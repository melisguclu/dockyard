import DockCore
import Foundation
import Testing

@Suite("A local order applies to Dockyard's bars and never to the real Dock")
struct TileOrderOverrideTests {
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

    private func folder(_ name: String) -> DockTile {
        DockTile(
            id: .path("file:///Users/tester/\(name)"),
            kind: .folder(FolderPresentation()),
            label: name,
            url: URL(fileURLWithPath: "/Users/tester/\(name)"),
            isPinned: true
        )
    }

    private let separator = DockTile(id: .builtin(.separator), kind: .separator, label: "")
    private let trash = DockTile(
        id: .builtin(.trash),
        kind: .trash(isEmpty: true),
        label: "Trash",
        url: URL(fileURLWithPath: "/Users/tester/.Trash")
    )

    private func keys(_ tiles: [DockTile]) -> TileOrderOverride {
        TileOrderOverride.recorded(tiles)
    }

    @Test("The recorded order is the order the bars render")
    func appliesRecordedOrder() {
        let safari = application("Safari")
        let mail = application("Mail")
        let notes = application("Notes")
        let tiles = [safari, mail, notes, separator, trash]

        let override = keys([notes, safari, mail])
        let result = override.applied(to: tiles)

        #expect(result.map(\.label) == ["Notes", "Safari", "Mail", "", "Trash"])
    }

    @Test("The separator and the Trash keep their places")
    func fixedTilesStayPut() {
        let tiles = [application("Safari"), separator, folder("Downloads"), trash]
        let override = TileOrderOverride(keys: [
            "builtin:trash",
            "path:file:///Users/tester/Downloads",
            "bundle:com.example.Safari",
        ])

        let result = override.applied(to: tiles)

        #expect(result.map(\.label) == ["Safari", "", "Downloads", "Trash"])
    }

    @Test("A tile the Dock added later stays next to the tile it follows")
    func newTileFollowsItsNeighbour() {
        let safari = application("Safari")
        let mail = application("Mail")
        let fresh = application("Fresh")
        let tiles = [safari, fresh, mail, separator, trash]

        let override = keys([mail, safari])
        let result = override.applied(to: tiles)

        #expect(result.map(\.label) == ["Mail", "Safari", "Fresh", "", "Trash"])
    }

    @Test("An empty override changes nothing")
    func emptyOverrideIsInert() {
        let tiles = [application("Safari"), application("Mail"), separator, trash]

        #expect(TileOrderOverride.empty.applied(to: tiles).map(\.label) == tiles.map(\.label))
    }

    @Test("A tile is never dragged across the separator into the other region")
    func regionsAreSealed() {
        let safari = application("Safari")
        let downloads = folder("Downloads")
        let tiles = [safari, separator, downloads, trash]

        let override = TileOrderOverride(keys: [
            "path:file:///Users/tester/Downloads",
            "bundle:com.example.Safari",
        ])
        let result = override.applied(to: tiles)

        #expect(result.map(\.label) == ["Safari", "", "Downloads", "Trash"])
    }

    @Test("Only tiles that can be dragged are recorded")
    func recordsOnlyReorderableTiles() {
        let spacer = DockTile(id: .builtin(.spacer(index: 0)), kind: .spacer(width: .full), label: "")
        let window = DockTile(id: .window(7), kind: .minimizedWindow, label: "Draft")

        let recorded = TileOrderOverride.recorded([
            application("Safari"), spacer, separator, window, folder("Downloads"), trash,
        ])

        #expect(recorded.keys == ["bundle:com.example.Safari", "path:file:///Users/tester/Downloads"])
    }

    @Test("A minimized window keeps its own place inside the trailing region")
    func minimizedWindowsAreNotReordered() {
        let window = DockTile(id: .window(7), kind: .minimizedWindow, label: "Draft")
        let documents = folder("Documents")
        let downloads = folder("Downloads")
        let tiles = [separator, window, documents, downloads, trash]

        let override = keys([downloads, documents])
        let result = override.applied(to: tiles)

        #expect(result.map(\.label) == ["", "Draft", "Downloads", "Documents", "Trash"])
    }

    @Test("An order recorded from a bar reproduces that bar exactly")
    func roundTrip() {
        let tiles = [
            application("Notes"), application("Safari"), folder("Downloads"), separator, trash,
        ]

        let result = TileOrderOverride.recorded(tiles).applied(to: tiles)

        #expect(result.map(\.label) == tiles.map(\.label))
    }

    @Test("An unranked run keeps the order it came in")
    func sequenceIsStable() {
        let tiles = [application("A"), application("B"), application("C")]

        let result = TileSequence.ordered(tiles) { _ in nil }

        #expect(result.map(\.label) == ["A", "B", "C"])
    }
}
