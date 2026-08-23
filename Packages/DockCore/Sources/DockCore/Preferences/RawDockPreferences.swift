import Foundation

public enum DockTileType: String, Sendable, Equatable, CaseIterable {
    case file = "file-tile"
    case directory = "directory-tile"
    case url = "url-tile"
    case spacer = "spacer-tile"
    case smallSpacer = "small-spacer-tile"
    case flexSpacer = "flex-spacer-tile"
}

public struct RawDockEntry: Sendable, Equatable {
    public let tileType: DockTileType
    public let label: String?
    public let bundleIdentifier: String?
    public let urlString: String?
    public let displayAs: Int?
    public let showAs: Int?

    public init(
        tileType: DockTileType,
        label: String? = nil,
        bundleIdentifier: String? = nil,
        urlString: String? = nil,
        displayAs: Int? = nil,
        showAs: Int? = nil
    ) {
        self.tileType = tileType
        self.label = label
        self.bundleIdentifier = bundleIdentifier
        self.urlString = urlString
        self.displayAs = displayAs
        self.showAs = showAs
    }
}

public struct RawDockPreferences: Sendable, Equatable {
    public let persistentApps: [RawDockEntry]
    public let persistentOthers: [RawDockEntry]
    public let recentApps: [RawDockEntry]
    public let appearance: DockAppearance

    public init(
        persistentApps: [RawDockEntry] = [],
        persistentOthers: [RawDockEntry] = [],
        recentApps: [RawDockEntry] = [],
        appearance: DockAppearance = .default
    ) {
        self.persistentApps = persistentApps
        self.persistentOthers = persistentOthers
        self.recentApps = recentApps
        self.appearance = appearance
    }

    public static let empty = RawDockPreferences()
}
