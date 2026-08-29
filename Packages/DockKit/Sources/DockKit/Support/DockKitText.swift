import Foundation

enum DockKitText {
    static func string(_ key: String) -> String {
        NSLocalizedString(key, bundle: .module, comment: "")
    }

    static func string(_ key: String, count: Int) -> String {
        String(format: NSLocalizedString(key, bundle: .module, comment: ""), count)
    }

    static func string(_ key: String, value: String) -> String {
        String(format: NSLocalizedString(key, bundle: .module, comment: ""), value)
    }
}

enum DockMenuStrings {
    static var open: String { DockKitText.string("menu.open") }
    static var showInFinder: String { DockKitText.string("menu.showInFinder") }
    static var show: String { DockKitText.string("menu.show") }
    static var showAllWindows: String { DockKitText.string("menu.showAllWindows") }
    static var hide: String { DockKitText.string("menu.hide") }
    static var quit: String { DockKitText.string("menu.quit") }
    static var forceQuit: String { DockKitText.string("menu.forceQuit") }
    static var dockSettings: String { DockKitText.string("menu.dockSettings") }
}

enum DockStackStrings {
    static var empty: String { DockKitText.string("stack.empty") }
    static var unreadable: String { DockKitText.string("stack.unreadable") }

    static func overflow(_ count: Int) -> String {
        DockKitText.string("stack.overflow", count: count)
    }
}
