import Foundation

public enum AppMenuSelection {
    public static let creationMenuIndex = 2

    static let creationShortcuts: [AppMenuShortcut] = [
        AppMenuShortcut(key: "N", modifiers: 0),
        AppMenuShortcut(key: "N", modifiers: 1),
        AppMenuShortcut(key: "N", modifiers: 2),
        AppMenuShortcut(key: "T", modifiers: 0),
    ]

    static let previousShortcut = AppMenuShortcut(key: "\u{F702}", modifiers: 0)
    static let nextShortcut = AppMenuShortcut(key: "\u{F703}", modifiers: 0)

    public static let recentDocumentIdentifier = "_openRecentDocument:"

    public static func commands(from items: [RawMenuItem], limit: Int) -> [AppMenuCommand] {
        var commands = creationCommands(from: items)
        commands.append(contentsOf: transportCommands(from: items))
        return Array(commands.prefix(limit))
    }

    public static func recents(from items: [RawMenuItem], limit: Int) -> [AppMenuCommand] {
        items
            .filter { $0.identifier == recentDocumentIdentifier }
            .filter { $0.isEnabled && !$0.hasSubmenu }
            .prefix(limit)
            .map {
                AppMenuCommand(
                    kind: .recent,
                    menuTitle: $0.menuTitle,
                    submenuTitle: $0.submenuTitle,
                    title: $0.title,
                    shortcut: nil
                )
            }
    }

    static func creationCommands(from items: [RawMenuItem]) -> [AppMenuCommand] {
        let candidates = items.enumerated().filter { entry in
            let item = entry.element
            guard item.isTopLevel, item.menuIndex == creationMenuIndex else { return false }
            guard item.isEnabled, !item.hasSubmenu else { return false }
            guard let shortcut = item.shortcut else { return false }
            return creationShortcuts.contains(shortcut)
        }

        let ordered = candidates.sorted { first, second in
            let firstRank = rank(of: first.element.shortcut)
            let secondRank = rank(of: second.element.shortcut)
            guard firstRank == secondRank else { return firstRank < secondRank }
            return first.offset < second.offset
        }

        var seen: Set<String> = []
        return ordered.compactMap { entry in
            guard seen.insert(entry.element.title).inserted else { return nil }
            return AppMenuCommand(
                kind: .creation,
                menuTitle: entry.element.menuTitle,
                title: entry.element.title,
                shortcut: entry.element.shortcut
            )
        }
    }

    static func transportCommands(from items: [RawMenuItem]) -> [AppMenuCommand] {
        guard let menuIndex = transportMenuIndex(in: items) else { return [] }
        let menu = items.filter { $0.isTopLevel && $0.menuIndex == menuIndex }

        var toggleFound = false
        return menu.compactMap { item in
            guard item.isEnabled, !item.hasSubmenu else { return nil }
            if let shortcut = item.shortcut {
                guard shortcut == previousShortcut || shortcut == nextShortcut else { return nil }
            } else {
                guard !toggleFound else { return nil }
                toggleFound = true
            }
            return AppMenuCommand(
                kind: .transport,
                menuTitle: item.menuTitle,
                title: item.title,
                shortcut: item.shortcut
            )
        }
    }

    static func transportMenuIndex(in items: [RawMenuItem]) -> Int? {
        var withNext: Set<Int> = []
        var withPrevious: Set<Int> = []
        for item in items where item.isTopLevel {
            guard let shortcut = item.shortcut else { continue }
            if shortcut == nextShortcut { withNext.insert(item.menuIndex) }
            if shortcut == previousShortcut { withPrevious.insert(item.menuIndex) }
        }
        return withNext.intersection(withPrevious).min()
    }

    private static func rank(of shortcut: AppMenuShortcut?) -> Int {
        guard let shortcut, let index = creationShortcuts.firstIndex(of: shortcut) else {
            return creationShortcuts.count
        }
        return index
    }
}
