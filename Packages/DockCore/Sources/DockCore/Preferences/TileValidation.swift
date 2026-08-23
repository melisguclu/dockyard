import Foundation

public struct DockEntry: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case application
        case folder(FolderPresentation)
        case url
        case spacer(SpacerWidth)
    }

    public let kind: Kind
    public let label: String
    public let url: URL?
    public let bundleIdentifier: String?

    public init(kind: Kind, label: String, url: URL?, bundleIdentifier: String?) {
        self.kind = kind
        self.label = label
        self.url = url
        self.bundleIdentifier = bundleIdentifier
    }

    public var canonicalPath: String? {
        url?.isFileURL == true ? url?.path : nil
    }
}

public enum TileValidation {
    public static func resolve(
        entries: [RawDockEntry],
        environment: TileEnvironment = .live
    ) -> [DockEntry] {
        entries.compactMap { resolve(entry: $0, environment: environment) }
    }

    public static func resolve(
        entry: RawDockEntry,
        environment: TileEnvironment = .live
    ) -> DockEntry? {
        switch entry.tileType {
        case .file:
            return resolveApplication(entry, environment: environment)
        case .directory:
            return resolveDirectory(entry, environment: environment)
        case .url:
            return resolveWebURL(entry)
        case .spacer:
            return DockEntry(kind: .spacer(.full), label: "", url: nil, bundleIdentifier: nil)
        case .smallSpacer:
            return DockEntry(kind: .spacer(.small), label: "", url: nil, bundleIdentifier: nil)
        case .flexSpacer:
            return DockEntry(kind: .spacer(.flexible), label: "", url: nil, bundleIdentifier: nil)
        }
    }

    public static func resolveApplicationURL(
        from urlString: String?,
        environment: TileEnvironment = .live
    ) -> URL? {
        guard let candidate = resolveFileURL(from: urlString, environment: environment) else { return nil }
        guard candidate.pathExtension == "app",
            environment.fileExists(candidate),
            environment.isLaunchableApplicationBundle(candidate)
        else { return nil }
        return candidate
    }

    public static func resolveFileURL(
        from urlString: String?,
        environment: TileEnvironment = .live
    ) -> URL? {
        guard let urlString, let url = URL(string: urlString), url.isFileURL else { return nil }
        let resolved = environment.resolveSymlinks(url).standardizedFileURL
        guard !resolved.path.isEmpty, resolved.path != "/" else { return nil }
        return resolved
    }

    public static func resolveWebURL(from urlString: String?) -> URL? {
        guard let urlString,
            let url = URL(string: urlString),
            let scheme = url.scheme?.lowercased(),
            scheme == "http" || scheme == "https",
            url.host?.isEmpty == false
        else { return nil }
        return url
    }

    public static func sanitizedLabel(_ label: String?, fallback: String) -> String {
        let candidate = label?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let chosen = candidate.isEmpty ? fallback : candidate
        return
            chosen
            .components(separatedBy: .newlines)
            .joined(separator: " ")
            .clampedLength(to: DockTile.maximumLabelLength)
    }

    private static func resolveApplication(
        _ entry: RawDockEntry,
        environment: TileEnvironment
    ) -> DockEntry? {
        guard let url = resolveApplicationURL(from: entry.urlString, environment: environment) else {
            DockLog.preferences.debug("Dropping unlaunchable file-tile")
            return nil
        }
        return DockEntry(
            kind: .application,
            label: sanitizedLabel(entry.label, fallback: url.deletingPathExtension().lastPathComponent),
            url: url,
            bundleIdentifier: entry.bundleIdentifier
        )
    }

    private static func resolveDirectory(
        _ entry: RawDockEntry,
        environment: TileEnvironment
    ) -> DockEntry? {
        guard let url = resolveFileURL(from: entry.urlString, environment: environment),
            environment.directoryExists(url)
        else {
            DockLog.preferences.debug("Dropping directory-tile with unresolvable path")
            return nil
        }
        let presentation = FolderPresentation(
            displayAs: FolderStackDisplay(rawValue: entry.displayAs ?? 0) ?? .stack,
            showAs: FolderStackViewMode(rawValue: entry.showAs ?? 0) ?? .automatic
        )
        return DockEntry(
            kind: .folder(presentation),
            label: sanitizedLabel(entry.label, fallback: url.lastPathComponent),
            url: url,
            bundleIdentifier: nil
        )
    }

    private static func resolveWebURL(_ entry: RawDockEntry) -> DockEntry? {
        guard let url = resolveWebURL(from: entry.urlString) else {
            DockLog.preferences.debug("Dropping url-tile with unsupported scheme")
            return nil
        }
        return DockEntry(
            kind: .url,
            label: sanitizedLabel(entry.label, fallback: url.host ?? url.absoluteString),
            url: url,
            bundleIdentifier: nil
        )
    }
}
