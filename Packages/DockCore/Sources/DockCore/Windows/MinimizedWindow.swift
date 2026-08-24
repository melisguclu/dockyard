import Foundation

public struct MinimizedWindow: Sendable, Equatable, Identifiable {
    public let token: UInt64
    public let processIdentifier: pid_t
    public let index: Int
    public let title: String
    public let applicationName: String
    public let bundleIdentifier: String?
    public let applicationURL: URL?

    public var id: UInt64 { token }

    public init(
        token: UInt64,
        processIdentifier: pid_t,
        index: Int,
        title: String,
        applicationName: String,
        bundleIdentifier: String? = nil,
        applicationURL: URL? = nil
    ) {
        self.token = token
        self.processIdentifier = processIdentifier
        self.index = index
        self.title = title
        self.applicationName = applicationName
        self.bundleIdentifier = bundleIdentifier
        self.applicationURL = applicationURL
    }

    public var entry: AppWindowEntry {
        AppWindowEntry(index: index, title: title, isMinimized: true)
    }

    public var tile: DockTile {
        DockTile(
            id: .window(token),
            kind: .minimizedWindow,
            label: title,
            url: applicationURL,
            bundleIdentifier: bundleIdentifier
        )
    }
}
