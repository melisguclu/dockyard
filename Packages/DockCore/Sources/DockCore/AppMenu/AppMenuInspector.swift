import ApplicationServices
import Foundation

public actor AppMenuInspector {
    public static let messagingTimeout: Float = 2
    public static let commandLimit = 6
    public static let recentLimit = 8
    public static let windowLimit = 12

    private static let firstApplicationMenuIndex = 2
    private static let submenuLimit = 6
    private static let submenuItemLimit = 40
    private static let identifierAttribute = "AXIdentifier"

    public init() {}

    public func snapshot(processIdentifier: pid_t) -> AppMenuSnapshot {
        guard AccessibilityAuthorization.isTrusted else {
            return AppMenuSnapshot(processIdentifier: processIdentifier, commands: [], windows: [])
        }
        let application = AXElement.application(processIdentifier, messagingTimeout: Self.messagingTimeout)
        let items = menuItems(of: application)
        return AppMenuSnapshot(
            processIdentifier: processIdentifier,
            commands: AppMenuSelection.commands(from: items, limit: Self.commandLimit),
            recents: AppMenuSelection.recents(from: items, limit: Self.recentLimit),
            windows: windowEntries(of: application)
        )
    }

    public func windows(processIdentifier: pid_t) -> [AppWindowEntry] {
        guard AccessibilityAuthorization.isTrusted else { return [] }
        return windowEntries(of: AXElement.application(processIdentifier, messagingTimeout: Self.messagingTimeout))
    }

    public func perform(_ command: AppMenuCommand, processIdentifier: pid_t) -> Bool {
        guard AccessibilityAuthorization.isTrusted else { return false }
        let application = AXElement.application(processIdentifier, messagingTimeout: Self.messagingTimeout)
        guard let bar = application.child(kAXMenuBarAttribute) else { return false }
        guard
            let top = bar.children(kAXChildrenAttribute)
                .first(where: { $0.string(kAXTitleAttribute) == command.menuTitle })
        else { return false }

        for menu in top.children(kAXChildrenAttribute) {
            for item in menu.children(kAXChildrenAttribute) {
                guard let submenuTitle = command.submenuTitle else {
                    guard item.string(kAXTitleAttribute) == command.title else { continue }
                    guard shortcut(of: item) == command.shortcut else { continue }
                    return item.perform(kAXPressAction)
                }
                guard item.string(kAXTitleAttribute) == submenuTitle else { continue }
                for submenu in item.children(kAXChildrenAttribute) {
                    for entry in submenu.children(kAXChildrenAttribute) {
                        guard entry.string(kAXTitleAttribute) == command.title else { continue }
                        return entry.perform(kAXPressAction)
                    }
                }
            }
        }
        return false
    }

    public func raise(_ window: AppWindowEntry, processIdentifier: pid_t) -> Bool {
        guard AccessibilityAuthorization.isTrusted else { return false }
        let application = AXElement.application(processIdentifier, messagingTimeout: Self.messagingTimeout)
        let windows = application.children(kAXWindowsAttribute)
        guard window.index < windows.count else { return false }
        let element = windows[window.index]
        guard element.string(kAXTitleAttribute) == window.title else { return false }
        if element.flag(kAXMinimizedAttribute) == true {
            _ = element.clear(kAXMinimizedAttribute)
        }
        return element.perform(kAXRaiseAction)
    }

    private func windowEntries(of application: AXElement) -> [AppWindowEntry] {
        application.children(kAXWindowsAttribute)
            .prefix(Self.windowLimit)
            .enumerated()
            .compactMap { entry in
                guard let title = entry.element.string(kAXTitleAttribute), !title.isEmpty else { return nil }
                return AppWindowEntry(
                    index: entry.offset,
                    title: title,
                    isMinimized: entry.element.flag(kAXMinimizedAttribute) ?? false
                )
            }
    }

    private func menuItems(of application: AXElement) -> [RawMenuItem] {
        guard let bar = application.child(kAXMenuBarAttribute) else { return [] }
        var items: [RawMenuItem] = []
        for (index, top) in bar.children(kAXChildrenAttribute).enumerated() {
            guard index >= Self.firstApplicationMenuIndex else { continue }
            guard let menuTitle = top.string(kAXTitleAttribute) else { continue }
            var submenusRead = 0
            for menu in top.children(kAXChildrenAttribute) {
                for item in menu.children(kAXChildrenAttribute) {
                    guard let title = item.string(kAXTitleAttribute), !title.isEmpty else { continue }
                    let shortcut = shortcut(of: item)
                    let children = shortcut == nil ? item.children(kAXChildrenAttribute) : []
                    items.append(
                        RawMenuItem(
                            menuIndex: index,
                            menuTitle: menuTitle,
                            title: title,
                            identifier: item.string(Self.identifierAttribute),
                            shortcut: shortcut,
                            isEnabled: item.flag(kAXEnabledAttribute) ?? true,
                            hasSubmenu: !children.isEmpty
                        )
                    )
                    guard index == Self.firstApplicationMenuIndex, !children.isEmpty else { continue }
                    guard submenusRead < Self.submenuLimit else { continue }
                    submenusRead += 1
                    items.append(
                        contentsOf: submenuItems(
                            of: children,
                            menuIndex: index,
                            menuTitle: menuTitle,
                            submenuTitle: title
                        )
                    )
                }
            }
        }
        return items
    }

    private func submenuItems(
        of menus: [AXElement],
        menuIndex: Int,
        menuTitle: String,
        submenuTitle: String
    ) -> [RawMenuItem] {
        var items: [RawMenuItem] = []
        for menu in menus {
            for entry in menu.children(kAXChildrenAttribute).prefix(Self.submenuItemLimit) {
                guard let title = entry.string(kAXTitleAttribute), !title.isEmpty else { continue }
                items.append(
                    RawMenuItem(
                        menuIndex: menuIndex,
                        menuTitle: menuTitle,
                        submenuTitle: submenuTitle,
                        title: title,
                        identifier: entry.string(Self.identifierAttribute),
                        shortcut: shortcut(of: entry),
                        isEnabled: entry.flag(kAXEnabledAttribute) ?? true,
                        hasSubmenu: false
                    )
                )
            }
        }
        return items
    }

    private func shortcut(of item: AXElement) -> AppMenuShortcut? {
        let modifiers = item.integer(kAXMenuItemCmdModifiersAttribute)
        guard let modifiers, modifiers & AppMenuShortcut.noCommandModifier == 0 else { return nil }
        return AppMenuShortcut.resolve(key: item.string(kAXMenuItemCmdCharAttribute), modifiers: modifiers)
    }
}
