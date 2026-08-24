import DockCore
import DockKit
import Foundation
import Testing

@Suite("Tile menus place the app's own commands above Dockyard's")
struct DockTileMenuBuilderTests {
    private func tile(running: Bool, hidden: Bool = false) -> DockTile {
        DockTile(
            id: .bundle("com.google.Chrome"),
            kind: .application,
            label: "Google Chrome",
            url: URL(fileURLWithPath: "/Applications/Google Chrome.app"),
            bundleIdentifier: "com.google.Chrome",
            isRunning: running,
            isHidden: hidden,
            isPinned: true
        )
    }

    private func snapshot(
        commands: [String] = ["New Window"],
        recents: [String] = [],
        windows: [String] = ["Inbox"]
    ) -> AppMenuSnapshot {
        AppMenuSnapshot(
            processIdentifier: 1808,
            commands: commands.map {
                AppMenuCommand(kind: .creation, menuTitle: "File", title: $0, shortcut: nil)
            },
            recents: recents.map {
                AppMenuCommand(
                    kind: .recent,
                    menuTitle: "File",
                    submenuTitle: "Open Recent",
                    title: $0,
                    shortcut: nil
                )
            },
            windows: windows.enumerated().map {
                AppWindowEntry(index: $0.offset, title: $0.element, isMinimized: false)
            }
        )
    }

    private func titles(_ items: [DockMenuItem]) -> [String] {
        items.map { item in
            switch item.kind {
            case .separator:
                return "—"
            case .command:
                return item.title
            }
        }
    }

    @Test("A running app lists its commands, then its windows, then Dockyard's commands")
    func runningApplication() {
        let items = DockTileMenuBuilder.items(for: tile(running: true), appMenu: snapshot())

        #expect(
            titles(items) == [
                "New Window", "—",
                "Inbox", "—",
                "Show", "Hide", "—",
                "Show in Finder", "—",
                "Quit", "Force Quit",
            ]
        )
    }

    @Test("Without an app menu the tile keeps Dockyard's own menu unchanged")
    func withoutSnapshot() {
        let items = DockTileMenuBuilder.items(for: tile(running: true))

        #expect(
            titles(items) == [
                "Show", "Hide", "—",
                "Show in Finder", "—",
                "Quit", "Force Quit",
            ]
        )
    }

    @Test("An app that is not running gets no commands even when a snapshot lingers")
    func notRunning() {
        let items = DockTileMenuBuilder.items(for: tile(running: false), appMenu: snapshot())

        #expect(titles(items) == ["Open", "—", "Show in Finder"])
    }

    @Test("An empty section contributes no separator")
    func emptySections() {
        let items = DockTileMenuBuilder.items(
            for: tile(running: true),
            appMenu: snapshot(commands: [], windows: [])
        )

        #expect(!titles(items).starts(with: ["—"]))
        #expect(titles(items).first == "Show")
    }

    @Test("A long window title is shortened in the middle")
    func longWindowTitle() {
        let title = String(repeating: "abcde ", count: 20)
        let items = DockTileMenuBuilder.items(
            for: tile(running: true),
            appMenu: snapshot(commands: [], windows: [title])
        )

        guard let row = items.first else {
            Issue.record("no rows built")
            return
        }
        #expect(row.title.count <= DockTileMenuBuilder.maximumTitleLength)
        #expect(row.title.contains("…"))
        #expect(row.title.hasPrefix("abcde"))
        #expect(row.title.hasSuffix("abcde "))
    }

    @Test("A hidden app offers to show all its windows")
    func hiddenApplication() {
        let items = DockTileMenuBuilder.items(for: tile(running: true, hidden: true))

        #expect(titles(items).contains("Show All Windows"))
    }
}

extension DockTileMenuBuilderTests {
    @Test("Recent documents sit between the app's commands and its windows")
    func recentSection() {
        let items = DockTileMenuBuilder.items(
            for: tile(running: true),
            appMenu: snapshot(commands: ["New Window"], recents: ["Taurus.xcodeproj"], windows: ["Inbox"])
        )

        #expect(
            titles(items) == [
                "New Window", "—",
                "Taurus.xcodeproj", "—",
                "Inbox", "—",
                "Show", "Hide", "—",
                "Show in Finder", "—",
                "Quit", "Force Quit",
            ]
        )
    }

    @Test("An app with only recents still gets one separator before Dockyard's commands")
    func recentsOnly() {
        let items = DockTileMenuBuilder.items(
            for: tile(running: true),
            appMenu: snapshot(commands: [], recents: ["notes.pdf"], windows: [])
        )

        #expect(titles(items).prefix(3) == ["notes.pdf", "—", "Show"])
    }
}

extension DockTileMenuBuilderTests {
    private var metrics: DockMenuMetrics { .current }

    private func crowded() -> AppMenuSnapshot {
        snapshot(
            commands: (0..<6).map { "Command \($0)" },
            recents: (0..<8).map { "recent\($0).txt" },
            windows: (0..<12).map { "Window \($0)" }
        )
    }

    private func height(_ items: [DockMenuItem]) -> CGFloat {
        let rows = items.filter { $0.kind != .separator }.count
        let separators = items.count - rows
        return 2 * metrics.verticalPadding
            + CGFloat(rows) * metrics.rowHeight
            + CGFloat(separators) * metrics.separatorHeight
            + metrics.tailLength
    }

    @Test("A menu taller than the display is trimmed to fit it")
    func trimsToFitShortDisplay() {
        let available: CGFloat = 400
        let items = DockTileMenuBuilder.items(
            for: tile(running: true),
            appMenu: crowded(),
            availableHeight: available
        )

        #expect(height(items) <= available)
    }

    @Test("Trimming never removes Dockyard's own commands")
    func trimmingKeepsBaseCommands() {
        let items = DockTileMenuBuilder.items(
            for: tile(running: true),
            appMenu: crowded(),
            availableHeight: 200
        )

        #expect(titles(items).contains("Show"))
        #expect(titles(items).contains("Hide"))
        #expect(titles(items).contains("Quit"))
        #expect(titles(items).contains("Force Quit"))
        #expect(titles(items).contains("Show in Finder"))
    }

    @Test("Recent documents give way before the window list does")
    func recentsAreTrimmedFirst() {
        let items = DockTileMenuBuilder.items(
            for: tile(running: true),
            appMenu: crowded(),
            availableHeight: 500
        )
        let shown = titles(items)

        #expect(shown.contains("Window 0"))
        #expect(!shown.contains("recent7.txt"))
    }

    @Test("A display with room for everything trims nothing")
    func noTrimmingWhenItFits() {
        let untrimmed = DockTileMenuBuilder.items(for: tile(running: true), appMenu: crowded())
        let roomy = DockTileMenuBuilder.items(
            for: tile(running: true),
            appMenu: crowded(),
            availableHeight: 2000
        )

        #expect(untrimmed == roomy)
        #expect(titles(roomy).contains("recent7.txt"))
        #expect(titles(roomy).contains("Window 11"))
    }

    @Test("The window list gives way before the app's own commands do")
    func windowsTrimmedBeforeCommands() {
        let items = DockTileMenuBuilder.items(
            for: tile(running: true),
            appMenu: crowded(),
            availableHeight: 320
        )
        let shown = titles(items)

        #expect(shown.contains("Command 0"))
        #expect(!shown.contains("Window 11"))
    }

    @Test("An impossibly short display still yields a usable menu")
    func degradesToBaseCommands() {
        let items = DockTileMenuBuilder.items(
            for: tile(running: true),
            appMenu: crowded(),
            availableHeight: 1
        )

        #expect(titles(items) == ["Show", "Hide", "—", "Show in Finder", "—", "Quit", "Force Quit"])
    }
}
