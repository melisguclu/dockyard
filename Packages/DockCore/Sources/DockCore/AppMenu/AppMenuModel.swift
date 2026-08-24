import Foundation

public struct AppMenuShortcut: Sendable, Equatable, Hashable {
    public static let noCommandModifier = 8

    public let key: String
    public let modifiers: Int

    public init(key: String, modifiers: Int) {
        self.key = key
        self.modifiers = modifiers
    }

    public static func resolve(key: String?, modifiers: Int?) -> AppMenuShortcut? {
        guard let key, !key.isEmpty else { return nil }
        let modifiers = modifiers ?? noCommandModifier
        guard modifiers & noCommandModifier == 0 else { return nil }
        return AppMenuShortcut(key: key.uppercased(), modifiers: modifiers)
    }
}

public enum AppMenuCommandKind: Sendable, Equatable, Hashable {
    case creation
    case transport
    case recent
}

public struct AppMenuCommand: Sendable, Equatable, Hashable {
    public let kind: AppMenuCommandKind
    public let menuTitle: String
    public let submenuTitle: String?
    public let title: String
    public let shortcut: AppMenuShortcut?

    public init(
        kind: AppMenuCommandKind,
        menuTitle: String,
        submenuTitle: String? = nil,
        title: String,
        shortcut: AppMenuShortcut?
    ) {
        self.kind = kind
        self.menuTitle = menuTitle
        self.submenuTitle = submenuTitle
        self.title = title
        self.shortcut = shortcut
    }

    public var activatesApplication: Bool {
        kind != .transport
    }
}

public struct AppWindowEntry: Sendable, Equatable, Hashable {
    public let index: Int
    public let title: String
    public let isMinimized: Bool

    public init(index: Int, title: String, isMinimized: Bool) {
        self.index = index
        self.title = title
        self.isMinimized = isMinimized
    }
}

public struct AppMenuSnapshot: Sendable, Equatable {
    public let processIdentifier: pid_t
    public let commands: [AppMenuCommand]
    public let recents: [AppMenuCommand]
    public let windows: [AppWindowEntry]

    public init(
        processIdentifier: pid_t,
        commands: [AppMenuCommand],
        recents: [AppMenuCommand] = [],
        windows: [AppWindowEntry]
    ) {
        self.processIdentifier = processIdentifier
        self.commands = commands
        self.recents = recents
        self.windows = windows
    }

    public var isEmpty: Bool {
        commands.isEmpty && recents.isEmpty && windows.isEmpty
    }
}

public struct RawMenuItem: Sendable, Equatable {
    public let menuIndex: Int
    public let menuTitle: String
    public let submenuTitle: String?
    public let title: String
    public let identifier: String?
    public let shortcut: AppMenuShortcut?
    public let isEnabled: Bool
    public let hasSubmenu: Bool

    public init(
        menuIndex: Int,
        menuTitle: String,
        submenuTitle: String? = nil,
        title: String,
        identifier: String? = nil,
        shortcut: AppMenuShortcut?,
        isEnabled: Bool,
        hasSubmenu: Bool
    ) {
        self.menuIndex = menuIndex
        self.menuTitle = menuTitle
        self.submenuTitle = submenuTitle
        self.title = title
        self.identifier = identifier
        self.shortcut = shortcut
        self.isEnabled = isEnabled
        self.hasSubmenu = hasSubmenu
    }

    public var isTopLevel: Bool {
        submenuTitle == nil
    }
}
