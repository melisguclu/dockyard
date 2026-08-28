import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController {
    private var window: NSWindow?
    private let preferences: Preferences

    init(preferences: Preferences) {
        self.preferences = preferences
    }

    func present() {
        if window == nil {
            window = makeWindow()
        }
        guard let window else { return }
        NSApplication.shared.setActivationPolicy(.regular)
        window.makeKeyAndOrderFront(nil)
        window.center()
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func makeWindow() -> NSWindow {
        let hostingController = NSHostingController(rootView: SettingsView(preferences: preferences))
        let window = NSWindow(contentViewController: hostingController)
        window.title = DockyardText.string("settings.title")
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.delegate = WindowDelegate.shared
        return window
    }
}

@MainActor
private final class WindowDelegate: NSObject, NSWindowDelegate {
    static let shared = WindowDelegate()

    func windowWillClose(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
    }
}
