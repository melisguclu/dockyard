import DockCore
import Foundation
import Testing

@Suite("The Dock's own item list supplies order and badges")
struct DockItemMatchingTests {
    private func application(_ name: String, path: String) -> DockTile {
        DockTile(
            id: .bundle("com.example.\(name)"),
            kind: .application,
            label: name,
            url: URL(fileURLWithPath: path),
            bundleIdentifier: "com.example.\(name)",
            isRunning: true
        )
    }

    private func item(
        _ index: Int,
        kind: DockItemKind = .application,
        title: String? = nil,
        badge: String? = nil,
        path: String? = nil
    ) -> DockItem {
        DockItem(
            index: index,
            kind: kind,
            title: title,
            badge: badge,
            locator: path.map { DockItem.locator(for: URL(fileURLWithPath: $0)) }
        )
    }

    private let separator = DockTile(id: .builtin(.separator), kind: .separator, label: "")
    private let trash = DockTile(
        id: .builtin(.trash),
        kind: .trash(isEmpty: true),
        label: "Trash",
        url: URL(fileURLWithPath: "/Users/tester/.Trash")
    )

    @Test("Tiles adopt the order of the Dock's own items")
    func adoptsOrder() {
        let tiles = [
            application("Safari", path: "/Applications/Safari.app"),
            application("Mail", path: "/Applications/Mail.app"),
            application("Notes", path: "/Applications/Notes.app"),
        ]
        let list = DockItemList(items: [
            item(0, path: "/Applications/Notes.app"),
            item(1, path: "/Applications/Safari.app"),
            item(2, path: "/Applications/Mail.app"),
        ])

        let result = DockItemMatching.applied(list, to: tiles)

        #expect(result.map(\.label) == ["Notes", "Safari", "Mail"])
    }

    @Test("A status label becomes the tile's badge")
    func badgeFromStatusLabel() {
        let tiles = [
            application("Mail", path: "/Applications/Mail.app"),
            application("Notes", path: "/Applications/Notes.app"),
        ]
        let list = DockItemList(items: [
            item(0, badge: "12", path: "/Applications/Mail.app"),
            item(1, path: "/Applications/Notes.app"),
        ])

        let result = DockItemMatching.applied(list, to: tiles)

        #expect(result[0].badge == "12")
        #expect(result[1].badge == nil)
    }

    @Test("An unmatched tile keeps its place behind the tile it followed")
    func unmatchedTileFollowsItsNeighbour() {
        let stranger = application("Stranger", path: "/Applications/Stranger.app")
        let tiles = [
            application("Safari", path: "/Applications/Safari.app"),
            stranger,
            application("Mail", path: "/Applications/Mail.app"),
            application("Notes", path: "/Applications/Notes.app"),
        ]
        let list = DockItemList(items: [
            item(0, path: "/Applications/Safari.app"),
            item(1, path: "/Applications/Notes.app"),
            item(2, path: "/Applications/Mail.app"),
        ])

        let result = DockItemMatching.applied(list, to: tiles)

        #expect(result.map(\.label) == ["Safari", "Stranger", "Notes", "Mail"])
    }

    @Test("Minimized windows land in the Dock's own minimize order")
    func minimizeOrder() {
        let first = DockTile(id: .window(1), kind: .minimizedWindow, label: "Draft")
        let second = DockTile(id: .window(2), kind: .minimizedWindow, label: "Report")
        let downloads = DockTile(
            id: .path("file:///Users/tester/Downloads"),
            kind: .folder(FolderPresentation()),
            label: "Downloads",
            url: URL(fileURLWithPath: "/Users/tester/Downloads")
        )
        let tiles = [separator, first, second, downloads, trash]
        let list = DockItemList(items: [
            item(0, kind: .separator),
            item(1, kind: .minimizedWindow, title: "Report"),
            item(2, kind: .folder, title: "Downloads", path: "/Users/tester/Downloads"),
            item(3, kind: .minimizedWindow, title: "Draft"),
            item(4, kind: .trash, title: "Trash"),
        ])

        let result = DockItemMatching.applied(list, to: tiles)

        #expect(result.map(\.label) == ["", "Report", "Downloads", "Draft", "Trash"])
    }

    @Test("A list that matches almost nothing is ignored rather than trusted")
    func lowMatchRatioIsIgnored() {
        let tiles = [
            application("Safari", path: "/Applications/Safari.app"),
            application("Mail", path: "/Applications/Mail.app"),
            application("Notes", path: "/Applications/Notes.app"),
        ]
        let list = DockItemList(items: [
            item(0, badge: "9", path: "/Applications/Unrelated.app"),
            item(1, path: "/Applications/AlsoUnrelated.app"),
        ])

        let result = DockItemMatching.applied(list, to: tiles)

        #expect(result.map(\.label) == tiles.map(\.label))
        #expect(result.allSatisfy { $0.badge == nil })
    }

    @Test("An empty list leaves the inferred order alone")
    func emptyListIsInert() {
        let tiles = [application("Safari", path: "/Applications/Safari.app"), separator, trash]

        let result = DockItemMatching.applied(.empty, to: tiles)

        #expect(result.map(\.label) == tiles.map(\.label))
    }

    @Test("Spacers stay where the Dock's own preferences put them")
    func spacersAreNotMatched() {
        let spacer = DockTile(id: .builtin(.spacer(index: 0)), kind: .spacer(width: .full), label: "")
        let tiles = [
            application("Safari", path: "/Applications/Safari.app"),
            spacer,
            application("Mail", path: "/Applications/Mail.app"),
        ]
        let list = DockItemList(items: [
            item(0, path: "/Applications/Safari.app"),
            item(1, path: "/Applications/Mail.app"),
        ])

        let result = DockItemMatching.applied(list, to: tiles)

        #expect(result.map(\.label) == ["Safari", "", "Mail"])
    }

    @Test("Two windows of one application match one dock item each, in order")
    func duplicateTitlesConsumeOneItemEach() {
        let tiles = [
            DockTile(id: .window(1), kind: .minimizedWindow, label: "Untitled"),
            DockTile(id: .window(2), kind: .minimizedWindow, label: "Untitled"),
        ]
        let list = DockItemList(items: [
            item(0, kind: .minimizedWindow, title: "Untitled"),
            item(1, kind: .minimizedWindow, title: "Untitled"),
        ])

        let result = DockItemMatching.applied(list, to: tiles)

        #expect(result.map(\.id) == tiles.map(\.id))
    }

    @Test("A badge from another application is treated as untrusted text")
    func badgesAreSanitized() {
        #expect(DockItem(index: 0, kind: .application, badge: "  12\n").badge == "12")
        #expect(DockItem(index: 0, kind: .application, badge: "   ").badge == nil)
        #expect(DockItem(index: 0, kind: .application, badge: "1234567890").badge == "123456")
        #expect(DockItem(index: 0, kind: .application, badge: "9\n99").badge == "9 99")
    }

    @Test("A tile that matches by name when it has no URL still takes its place")
    func titleFallback() {
        let tiles = [
            DockTile(id: .bundle("com.example.ghost"), kind: .application, label: "Ghost"),
            application("Safari", path: "/Applications/Safari.app"),
        ]
        let list = DockItemList(items: [
            item(0, path: "/Applications/Safari.app"),
            item(1, title: "Ghost", badge: "3"),
        ])

        let result = DockItemMatching.applied(list, to: tiles)

        #expect(result.map(\.label) == ["Safari", "Ghost"])
        #expect(result[1].badge == "3")
    }
}
