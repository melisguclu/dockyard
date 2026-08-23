public struct ResolvedDockPreferences: Sendable, Equatable {
    public let finder: DockEntry?
    public let pinnedApps: [DockEntry]
    public let others: [DockEntry]
    public let recents: [DockEntry]
    public let appearance: DockAppearance

    public init(
        finder: DockEntry? = nil,
        pinnedApps: [DockEntry] = [],
        others: [DockEntry] = [],
        recents: [DockEntry] = [],
        appearance: DockAppearance = .default
    ) {
        self.finder = finder
        self.pinnedApps = pinnedApps
        self.others = others
        self.recents = recents
        self.appearance = appearance
    }

    public static let empty = ResolvedDockPreferences()

    public static func resolve(
        _ raw: RawDockPreferences,
        environment: TileEnvironment = .live
    ) -> ResolvedDockPreferences {
        ResolvedDockPreferences(
            finder: resolveFinder(environment: environment),
            pinnedApps: TileValidation.resolve(entries: raw.persistentApps, environment: environment),
            others: TileValidation.resolve(entries: raw.persistentOthers, environment: environment),
            recents: TileValidation.resolve(entries: raw.recentApps, environment: environment),
            appearance: raw.appearance
        )
    }

    private static func resolveFinder(environment: TileEnvironment) -> DockEntry? {
        guard let url = environment.finderURL() else { return nil }
        return DockEntry(
            kind: .application,
            label: "Finder",
            url: url,
            bundleIdentifier: TileEnvironment.finderBundleIdentifier
        )
    }
}
