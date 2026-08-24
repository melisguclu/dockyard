import AppKit
import DockCore
import Foundation
import Testing

@Suite("Minimized windows occupy the region between the separator and the Trash")
struct MinimizedWindowTests {
    private func tiles(
        _ fixture: Fixture,
        windows: [MinimizedWindow],
        appearance: DockAppearance? = nil
    ) -> [DockTile] {
        let resolved = fixture.resolved(environment: TestEnvironment.standard)
        let preferences = ResolvedDockPreferences(
            finder: resolved.finder,
            pinnedApps: resolved.pinnedApps,
            others: resolved.others,
            recents: resolved.recents,
            appearance: appearance ?? resolved.appearance
        )
        return TileOrdering.tiles(
            preferences: preferences,
            running: [],
            minimizedWindows: windows,
            trashIsEmpty: true
        )
    }

    @Test("A minimized window follows the separator and precedes the Trash")
    func placement() {
        let result = tiles(.minimal, windows: [TestWindows.minimized(token: 0, title: "Downloads")])

        #expect(result.count == 4)
        #expect(result[1].isSeparator)
        #expect(result[2].isMinimizedWindow)
        #expect(result[2].label == "Downloads")
        #expect(result[3].isTrash)
    }

    @Test("Minimized windows precede the pinned folders and stacks")
    func precedeOthers() {
        let result = tiles(.withFolders, windows: [TestWindows.minimized(token: 0)])
        guard let separator = result.firstIndex(where: \.isSeparator),
            let window = result.firstIndex(where: \.isMinimizedWindow),
            let folder = result.lastIndex(where: { $0.url?.hasDirectoryPath == true })
        else {
            Issue.record("The fixture produced no separator, window, or folder tile")
            return
        }
        #expect(separator < window)
        #expect(window < folder)
    }

    @Test("The tiles keep the order the store publishes")
    func order() {
        let result = tiles(
            .minimal,
            windows: [
                TestWindows.minimized(token: 4, title: "First"),
                TestWindows.minimized(token: 9, title: "Second"),
                TestWindows.minimized(token: 11, title: "Third"),
            ]
        )
        #expect(result.filter(\.isMinimizedWindow).map(\.label) == ["First", "Second", "Third"])
    }

    @Test("A window tile carries the owning application, not the window, as its icon source")
    func iconSource() {
        let result = tiles(.minimal, windows: [TestWindows.minimized(token: 0)])
        let window = result.first { $0.isMinimizedWindow }

        #expect(window?.bundleIdentifier == "com.example.app")
        #expect(window?.url?.lastPathComponent == "Safari.app")
        #expect(window?.isRunning == false)
    }

    @Test("minimize-to-application suppresses the region entirely")
    func minimizeToApplication() {
        let appearance = DockAppearance(minimizeToApplication: true)
        let result = tiles(.minimal, windows: [TestWindows.minimized(token: 0)], appearance: appearance)

        #expect(result.contains(where: \.isMinimizedWindow) == false)
    }

    @Test("Two windows sharing a title stay two tiles")
    func duplicateTitles() {
        let result = tiles(
            .minimal,
            windows: [
                TestWindows.minimized(token: 0, index: 0, title: "Untitled"),
                TestWindows.minimized(token: 1, index: 1, title: "Untitled"),
            ]
        )
        #expect(result.filter(\.isMinimizedWindow).count == 2)
    }

    @Test("The card is drawn at the requested size and refuses degenerate ones")
    func cardRendering() throws {
        let badge = try #require(
            NSWorkspace.shared.icon(forFile: "/System/Library/CoreServices/Finder.app")
                .cgImage(forProposedRect: nil, context: nil, hints: nil)
        )
        let card = try #require(MinimizedWindowTileRenderer.card(badge: badge, pixelSize: 128))

        #expect(card.width == 128)
        #expect(card.height == 128)
        #expect(MinimizedWindowTileRenderer.card(badge: badge, pixelSize: 8) == nil)
        #expect(MinimizedWindowTileRenderer.badgePixelSize(for: 128) < 128)

        if let path = ProcessInfo.processInfo.environment["DOCKYARD_WINDOW_PREVIEW"] {
            let representation = NSBitmapImageRep(cgImage: card)
            try representation.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        }
    }
}
