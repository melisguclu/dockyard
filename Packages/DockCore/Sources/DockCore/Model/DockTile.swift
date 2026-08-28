import Foundation

public enum DockTileBuiltin: Hashable, Sendable {
    case trash
    case separator
    case spacer(index: Int)
}

public enum DockTileID: Hashable, Sendable {
    case bundle(String)
    case path(String)
    case builtin(DockTileBuiltin)
    case window(UInt64)

    public static func application(bundleIdentifier: String?, path: String?) -> DockTileID? {
        if let bundleIdentifier, !bundleIdentifier.isEmpty { return .bundle(bundleIdentifier) }
        if let path, !path.isEmpty { return .path(path) }
        return nil
    }
}

public enum FolderStackDisplay: Int, Sendable, Equatable, Codable {
    case stack = 0
    case folder = 1
}

public enum FolderStackViewMode: Int, Sendable, Equatable, Codable {
    case automatic = 0
    case fan = 1
    case grid = 2
    case list = 3
}

public enum FolderStackArrangement: Int, Sendable, Equatable, Codable {
    case name = 1
    case dateAdded = 2
    case dateModified = 3
    case dateCreated = 4
    case kind = 5
}

public struct FolderPresentation: Sendable, Equatable {
    public let displayAs: FolderStackDisplay
    public let showAs: FolderStackViewMode
    public let arrangement: FolderStackArrangement

    public init(
        displayAs: FolderStackDisplay = .stack,
        showAs: FolderStackViewMode = .automatic,
        arrangement: FolderStackArrangement = .name
    ) {
        self.displayAs = displayAs
        self.showAs = showAs
        self.arrangement = arrangement
    }
}

public enum SpacerWidth: Sendable, Equatable {
    case full
    case small
    case flexible
}

public struct DockTile: Sendable, Equatable, Identifiable {
    public let id: DockTileID
    public let kind: Kind
    public let label: String
    public let url: URL?
    public let bundleIdentifier: String?
    public let isRunning: Bool
    public let isActive: Bool
    public let isHidden: Bool
    public let isPinned: Bool

    public enum Kind: Sendable, Equatable {
        case application
        case folder(FolderPresentation)
        case url
        case trash(isEmpty: Bool)
        case minimizedWindow
        case separator
        case spacer(width: SpacerWidth)
    }

    public init(
        id: DockTileID,
        kind: Kind,
        label: String,
        url: URL? = nil,
        bundleIdentifier: String? = nil,
        isRunning: Bool = false,
        isActive: Bool = false,
        isHidden: Bool = false,
        isPinned: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.label = label
        self.url = url
        self.bundleIdentifier = bundleIdentifier
        self.isRunning = isRunning
        self.isActive = isActive
        self.isHidden = isHidden
        self.isPinned = isPinned
    }

    public var isInteractive: Bool {
        switch kind {
        case .application, .folder, .url, .trash, .minimizedWindow:
            return true
        case .separator, .spacer:
            return false
        }
    }

    public var providesMenu: Bool {
        switch kind {
        case .spacer:
            return false
        default:
            return true
        }
    }

    public var occupiesTileSlot: Bool {
        switch kind {
        case .separator, .spacer:
            return false
        default:
            return true
        }
    }

    public static let maximumLabelLength = 256
}
