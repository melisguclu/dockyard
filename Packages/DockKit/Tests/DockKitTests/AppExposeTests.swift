import DockCore
import DockKit
import Foundation
import Testing

@Suite("Click and hold lists the application's own windows and nothing else")
struct AppExposeTests {
    private func tile(running: Bool = true, kind: DockTile.Kind = .application) -> DockTile {
        DockTile(
            id: .bundle("com.apple.Safari"),
            kind: kind,
            label: "Safari",
            url: URL(fileURLWithPath: "/Applications/Safari.app"),
            bundleIdentifier: "com.apple.Safari",
            isRunning: running,
            isPinned: true
        )
    }

    private func snapshot(_ windows: [String]) -> AppMenuSnapshot {
        AppMenuSnapshot(
            processIdentifier: 500,
            commands: [AppMenuCommand(kind: .creation, menuTitle: "File", title: "New Window", shortcut: nil)],
            recents: [AppMenuCommand(kind: .recent, menuTitle: "File", title: "Report", shortcut: nil)],
            windows: windows.enumerated().map {
                AppWindowEntry(index: $0.offset, title: $0.element, isMinimized: false)
            }
        )
    }

    @Test("Only the windows appear, in the application's own order")
    func windowsOnly() {
        let items = DockTileMenuBuilder.windowItems(
            for: tile(),
            appMenu: snapshot(["Inbox", "Drafts"])
        )

        #expect(items.map(\.title) == ["Inbox", "Drafts"])
        #expect(items.allSatisfy { $0.kind != .separator })
    }

    @Test("An application with no windows offers no menu at all")
    func noWindowsNoMenu() {
        #expect(DockTileMenuBuilder.windowItems(for: tile(), appMenu: snapshot([])).isEmpty)
        #expect(DockTileMenuBuilder.windowItems(for: tile(), appMenu: nil).isEmpty)
    }

    @Test("A tile that is not a running application never opens App Exposé")
    func onlyRunningApplications() {
        let stopped = DockTileMenuBuilder.windowItems(for: tile(running: false), appMenu: snapshot(["Inbox"]))
        let folder = DockTileMenuBuilder.windowItems(
            for: tile(kind: .folder(FolderPresentation())),
            appMenu: snapshot(["Inbox"])
        )

        #expect(stopped.isEmpty)
        #expect(folder.isEmpty)
    }

    @Test("A window list taller than the screen is trimmed rather than clipped")
    func trimmedToFit() {
        let many = (1...20).map { "Window \($0)" }
        let metrics = DockMenuMetrics.current
        let height = 6 * metrics.rowHeight

        let items = DockTileMenuBuilder.windowItems(
            for: tile(),
            appMenu: snapshot(many),
            availableHeight: height,
            metrics: metrics
        )

        #expect(!items.isEmpty)
        #expect(items.count < many.count)
        #expect(items.first?.title == "Window 1")
    }

    @Test("A window title longer than the balloon is shortened in the middle")
    func longTitles() {
        let title = String(repeating: "A", count: 120)
        let items = DockTileMenuBuilder.windowItems(for: tile(), appMenu: snapshot([title]))

        #expect(items.count == 1)
        #expect(items[0].title.count <= DockTileMenuBuilder.maximumTitleLength)
        #expect(items[0].title.contains("…"))
    }

    @Test("The hold is long enough to be deliberate and short enough to be usable")
    func holdDelay() {
        #expect(DockContentView.exposeHoldDelay > 0.4)
        #expect(DockContentView.exposeHoldDelay < 1.0)
    }
}
