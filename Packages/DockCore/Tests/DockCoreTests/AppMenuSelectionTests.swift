import DockCore
import Foundation
import Testing

@Suite("App menu selection picks the commands a Dock menu would show")
struct AppMenuSelectionTests {
    private func item(
        menuIndex: Int,
        menuTitle: String,
        submenuTitle: String? = nil,
        title: String,
        identifier: String? = nil,
        key: String? = nil,
        modifiers: Int? = nil,
        isEnabled: Bool = true,
        hasSubmenu: Bool = false
    ) -> RawMenuItem {
        RawMenuItem(
            menuIndex: menuIndex,
            menuTitle: menuTitle,
            submenuTitle: submenuTitle,
            title: title,
            identifier: identifier,
            shortcut: AppMenuShortcut.resolve(key: key, modifiers: modifiers),
            isEnabled: isEnabled,
            hasSubmenu: hasSubmenu
        )
    }

    private var xcode: [RawMenuItem] {
        [
            item(menuIndex: 2, menuTitle: "File", title: "New", hasSubmenu: true),
            item(
                menuIndex: 2, menuTitle: "File", submenuTitle: "New", title: "Window",
                identifier: "newWindowForTab:", key: "N", modifiers: 1
            ),
            item(menuIndex: 2, menuTitle: "File", title: "Open Recent", hasSubmenu: true),
            item(
                menuIndex: 2, menuTitle: "File", submenuTitle: "Open Recent", title: "Taurus.xcodeproj",
                identifier: AppMenuSelection.recentDocumentIdentifier
            ),
            item(
                menuIndex: 2, menuTitle: "File", submenuTitle: "Open Recent", title: "CMakePresets.json",
                identifier: AppMenuSelection.recentDocumentIdentifier
            ),
            item(
                menuIndex: 2, menuTitle: "File", submenuTitle: "Open Recent", title: "Clear Menu",
                identifier: "clearRecentDocuments:"
            ),
        ]
    }

    private var chrome: [RawMenuItem] {
        [
            item(menuIndex: 2, menuTitle: "File", title: "New Tab", key: "T", modifiers: 0),
            item(menuIndex: 2, menuTitle: "File", title: "New Window", key: "N", modifiers: 0),
            item(menuIndex: 2, menuTitle: "File", title: "New Incognito Window", key: "N", modifiers: 1),
            item(menuIndex: 2, menuTitle: "File", title: "Reopen Closed Tab", key: "T", modifiers: 1),
            item(menuIndex: 2, menuTitle: "File", title: "Open File…", key: "O", modifiers: 0),
            item(menuIndex: 2, menuTitle: "File", title: "Close Window", key: "W", modifiers: 1),
            item(menuIndex: 3, menuTitle: "Edit", title: "Undo", key: "Z", modifiers: 0),
        ]
    }

    private var spotify: [RawMenuItem] {
        [
            item(menuIndex: 2, menuTitle: "File", title: "New Playlist", key: "N", modifiers: 0, isEnabled: false),
            item(menuIndex: 5, menuTitle: "Playback", title: "Play", modifiers: 8),
            item(menuIndex: 5, menuTitle: "Playback", title: "Next", key: "\u{F703}", modifiers: 0),
            item(menuIndex: 5, menuTitle: "Playback", title: "Previous", key: "\u{F702}", modifiers: 0),
            item(menuIndex: 5, menuTitle: "Playback", title: "Seek Forward", key: "\u{F703}", modifiers: 1),
            item(menuIndex: 5, menuTitle: "Playback", title: "Volume Up", key: "\u{F700}", modifiers: 0),
        ]
    }

    @Test("Window creation commands lead, ordered by shortcut rather than menu position")
    func creationOrder() {
        let commands = AppMenuSelection.commands(from: chrome, limit: 6)

        #expect(commands.map(\.title) == ["New Window", "New Incognito Window", "New Tab"])
        #expect(commands.allSatisfy { $0.kind == .creation })
    }

    @Test("A transport menu contributes its toggle and its track commands")
    func transportCommands() {
        let commands = AppMenuSelection.commands(from: spotify, limit: 6)

        #expect(commands.map(\.title) == ["Play", "Next", "Previous"])
        #expect(commands.allSatisfy { $0.kind == .transport })
        #expect(commands.allSatisfy { !$0.activatesApplication })
    }

    @Test("A disabled creation command is left out")
    func disabledCommand() {
        let commands = AppMenuSelection.commands(from: spotify, limit: 6)

        #expect(!commands.contains { $0.title == "New Playlist" })
    }

    @Test("A command that only opens a submenu is left out")
    func submenuCommand() {
        let items = [
            item(menuIndex: 2, menuTitle: "Shell", title: "New Window", hasSubmenu: true),
            item(menuIndex: 2, menuTitle: "Shell", title: "New Command…", key: "N", modifiers: 1),
        ]

        let commands = AppMenuSelection.commands(from: items, limit: 6)

        #expect(commands.map(\.title) == ["New Command…"])
    }

    @Test("An app whose third menu is not a File menu contributes nothing")
    func noCreationMenu() {
        let items = [
            item(menuIndex: 2, menuTitle: "Edit", title: "Undo", key: "Z", modifiers: 0),
            item(menuIndex: 2, menuTitle: "Edit", title: "Cut", key: "X", modifiers: 0),
            item(menuIndex: 3, menuTitle: "View", title: "Zoom In", key: "+", modifiers: 0),
        ]

        #expect(AppMenuSelection.commands(from: items, limit: 6).isEmpty)
    }

    @Test("Creation commands are only read from the menu next to the application menu")
    func creationMenuIsPositional() {
        let items = [
            item(menuIndex: 4, menuTitle: "Bookmarks", title: "New Folder", key: "N", modifiers: 0)
        ]

        #expect(AppMenuSelection.commands(from: items, limit: 6).isEmpty)
    }

    @Test("A shortcut without the command key is not a shortcut")
    func noCommandModifier() {
        #expect(AppMenuShortcut.resolve(key: "E", modifiers: 24) == nil)
        #expect(AppMenuShortcut.resolve(key: "N", modifiers: 10) == nil)
        #expect(AppMenuShortcut.resolve(key: nil, modifiers: 0) == nil)
        #expect(AppMenuShortcut.resolve(key: "n", modifiers: 1) == AppMenuShortcut(key: "N", modifiers: 1))
    }

    @Test("Both kinds combine, creation first, capped at the limit")
    func combinedAndCapped() {
        let commands = AppMenuSelection.commands(from: chrome + spotify, limit: 4)

        #expect(commands.count == 4)
        #expect(commands.map(\.title) == ["New Window", "New Incognito Window", "New Tab", "Play"])
    }

    @Test("A duplicated command title is surfaced once")
    func duplicateTitles() {
        let items = [
            item(menuIndex: 2, menuTitle: "File", title: "New Window", key: "N", modifiers: 0),
            item(menuIndex: 2, menuTitle: "File", title: "New Window", key: "N", modifiers: 2),
        ]

        #expect(AppMenuSelection.commands(from: items, limit: 6).count == 1)
    }

    @Test("A menu needs both track directions to count as a transport menu")
    func incompleteTransportMenu() {
        let items = [
            item(menuIndex: 5, menuTitle: "Go", title: "Forward", key: "\u{F703}", modifiers: 0),
            item(menuIndex: 5, menuTitle: "Go", title: "Enclosing Folder", key: "\u{F700}", modifiers: 0),
        ]

        #expect(AppMenuSelection.commands(from: items, limit: 6).isEmpty)
    }
}

extension AppMenuSelectionTests {
    @Test("Recent documents come from the standard AppKit identifier, not from titles")
    func recentDocuments() {
        let recents = AppMenuSelection.recents(from: xcode, limit: 8)

        #expect(recents.map(\.title) == ["Taurus.xcodeproj", "CMakePresets.json"])
        #expect(recents.allSatisfy { $0.kind == .recent })
        #expect(recents.allSatisfy { $0.submenuTitle == "Open Recent" })
        #expect(recents.allSatisfy { $0.activatesApplication })
    }

    @Test("Clearing the recents list is not offered as a recent document")
    func clearMenuExcluded() {
        #expect(!AppMenuSelection.recents(from: xcode, limit: 8).contains { $0.title == "Clear Menu" })
    }

    @Test("The recents list is capped")
    func recentLimit() {
        let many = (0..<20).map {
            item(
                menuIndex: 2, menuTitle: "File", submenuTitle: "Open Recent", title: "file\($0).txt",
                identifier: AppMenuSelection.recentDocumentIdentifier
            )
        }

        #expect(AppMenuSelection.recents(from: many, limit: 8).count == 8)
    }

    @Test("A disabled recent document is left out")
    func disabledRecent() {
        let items = [
            item(
                menuIndex: 2, menuTitle: "File", submenuTitle: "Open Recent", title: "gone.txt",
                identifier: AppMenuSelection.recentDocumentIdentifier, isEnabled: false
            )
        ]

        #expect(AppMenuSelection.recents(from: items, limit: 8).isEmpty)
    }

    @Test("A submenu entry never becomes a creation command, however it is bound")
    func submenuEntriesAreNotCommands() {
        #expect(AppMenuSelection.commands(from: xcode, limit: 6).isEmpty)
    }

    @Test("A submenu entry never becomes a transport command")
    func submenuEntriesAreNotTransport() {
        let items = [
            item(
                menuIndex: 5, menuTitle: "Playback", submenuTitle: "Queue", title: "Next",
                key: "\u{F703}", modifiers: 0
            ),
            item(
                menuIndex: 5, menuTitle: "Playback", submenuTitle: "Queue", title: "Previous",
                key: "\u{F702}", modifiers: 0
            ),
        ]

        #expect(AppMenuSelection.commands(from: items, limit: 6).isEmpty)
    }

    @Test("An app with no recents list contributes none")
    func noRecents() {
        #expect(AppMenuSelection.recents(from: chrome, limit: 8).isEmpty)
    }
}
