import Foundation

public struct FolderStackEntry: Sendable, Equatable, Identifiable {
    public let url: URL
    public let name: String
    public let isDirectory: Bool
    public let isApplication: Bool

    public var id: String { url.path }

    public init(url: URL, name: String, isDirectory: Bool, isApplication: Bool) {
        self.url = url
        self.name = name
        self.isDirectory = isDirectory
        self.isApplication = isApplication
    }
}

public struct FolderStackContents: Sendable, Equatable {
    public let url: URL
    public let entries: [FolderStackEntry]
    public let truncated: Int
    public let isReadable: Bool

    public init(url: URL, entries: [FolderStackEntry], truncated: Int = 0, isReadable: Bool = true) {
        self.url = url
        self.entries = entries
        self.truncated = truncated
        self.isReadable = isReadable
    }

    public static func unreadable(_ url: URL) -> FolderStackContents {
        FolderStackContents(url: url, entries: [], truncated: 0, isReadable: false)
    }

    public var isEmpty: Bool {
        entries.isEmpty && truncated == 0
    }
}
