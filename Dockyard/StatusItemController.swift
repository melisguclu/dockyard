import AppKit
import DockCore
import Foundation

@MainActor
final class StatusItemController: NSObject, NSMenuDelegate {
    private let statusItem: NSStatusItem
    private let preferences: Preferences
    private let onOpenSettings: () -> Void
    private let onRefresh: () -> Void
    private let onQuit: () -> Void

    init(
        preferences: Preferences,
        onOpenSettings: @escaping () -> Void,
        onRefresh: @escaping () -> Void,
        onQuit: @escaping () -> Void
    ) {
        self.preferences = preferences
        self.onOpenSettings = onOpenSettings
        self.onRefresh = onRefresh
        self.onQuit = onQuit
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        if let button = statusItem.button {
            button.image = NSImage(
                systemSymbolName: "rectangle.bottomthird.inset.filled",
                accessibilityDescription: "Dockyard"
            )
            button.image?.isTemplate = true
        }
        statusItem.menu = makeMenu()
    }

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.delegate = self

        let settings = NSMenuItem(
            title: "Settings…",
            action: #selector(openSettings),
            keyEquivalent: ","
        )
        settings.target = self
        menu.addItem(settings)

        let refresh = NSMenuItem(title: "Refresh", action: #selector(refresh), keyEquivalent: "r")
        refresh.target = self
        menu.addItem(refresh)

        menu.addItem(.separator())

        let launchAtLogin = NSMenuItem(
            title: "Launch at Login",
            action: #selector(toggleLaunchAtLogin),
            keyEquivalent: ""
        )
        launchAtLogin.target = self
        launchAtLogin.tag = Tag.launchAtLogin
        menu.addItem(launchAtLogin)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Dockyard", action: #selector(quit), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)

        return menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        preferences.refreshLaunchAtLoginState()
        menu.item(withTag: Tag.launchAtLogin)?.state = preferences.launchesAtLogin ? .on : .off
    }

    @objc private func openSettings() {
        onOpenSettings()
    }

    @objc private func refresh() {
        onRefresh()
    }

    @objc private func toggleLaunchAtLogin() {
        preferences.launchesAtLogin.toggle()
    }

    @objc private func quit() {
        onQuit()
    }

    private enum Tag {
        static let launchAtLogin = 1001
    }
}
