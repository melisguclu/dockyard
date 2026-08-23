import Foundation

public struct RunningApplicationState: Sendable, Equatable, Identifiable {
    public let processIdentifier: pid_t
    public let bundleIdentifier: String?
    public let bundleURL: URL?
    public let localizedName: String
    public let isActive: Bool
    public let isHidden: Bool
    public let launchSequence: UInt64

    public var id: pid_t { processIdentifier }

    public init(
        processIdentifier: pid_t,
        bundleIdentifier: String?,
        bundleURL: URL?,
        localizedName: String,
        isActive: Bool,
        isHidden: Bool,
        launchSequence: UInt64
    ) {
        self.processIdentifier = processIdentifier
        self.bundleIdentifier = bundleIdentifier
        self.bundleURL = bundleURL
        self.localizedName = localizedName
        self.isActive = isActive
        self.isHidden = isHidden
        self.launchSequence = launchSequence
    }

    public var canonicalPath: String? {
        bundleURL?.standardizedFileURL.resolvingSymlinksInPath().path
    }
}
