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
        if !window.isVisible {
            window.center()
        }
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    private func makeWindow() -> NSWindow {
        let tabs = NSTabViewController()
        tabs.tabStyle = .toolbar
        for pane in SettingsPane.allCases {
            let item = NSTabViewItem(viewController: controller(for: pane))
            item.label = pane.title
            item.image = NSImage(systemSymbolName: pane.symbol, accessibilityDescription: nil)
            tabs.addTabViewItem(item)
        }

        let window = NSWindow(contentViewController: tabs)
        window.title = SettingsPane.general.title
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.toolbarStyle = .preference
        window.isReleasedWhenClosed = false
        window.delegate = WindowDelegate.shared
        return window
    }

    private func controller(for pane: SettingsPane) -> NSViewController {
        let controller: NSHostingController<AnyView>
        switch pane {
        case .general:
            controller = NSHostingController(rootView: AnyView(GeneralSettingsView(preferences: preferences)))
        case .displays:
            controller = NSHostingController(rootView: AnyView(DisplaysSettingsView(preferences: preferences)))
        case .about:
            controller = NSHostingController(rootView: AnyView(AboutSettingsView()))
        }
        controller.sizingOptions = [.preferredContentSize]
        controller.title = pane.title
        return controller
    }
}

@MainActor
private final class WindowDelegate: NSObject, NSWindowDelegate {
    static let shared = WindowDelegate()

    func windowWillClose(_ notification: Notification) {
        NSApplication.shared.setActivationPolicy(.accessory)
    }
}
