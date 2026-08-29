import Foundation

public enum DockItemKind: String, Sendable, Equatable {
    case application
    case folder
    case url
    case document
    case minimizedWindow
    case trash
    case separator
    case unknown

    public init(subrole: String?) {
        switch subrole {
        case "AXApplicationDockItem":
            self = .application
        case "AXFolderDockItem":
            self = .folder
        case "AXURLDockItem":
            self = .url
        case "AXDocumentDockItem":
            self = .document
        case "AXMinimizedWindowDockItem":
            self = .minimizedWindow
        case "AXTrashDockItem":
            self = .trash
        case "AXSeparatorDockItem":
            self = .separator
        default:
            self = .unknown
        }
    }
}

public struct DockItem: Sendable, Equatable {
    public static let maximumBadgeLength = 6

    public let index: Int
    public let kind: DockItemKind
    public let title: String?
    public let badge: String?
    public let locator: String?
    public let isRunning: Bool

    public init(
        index: Int,
        kind: DockItemKind,
        title: String? = nil,
        badge: String? = nil,
        locator: String? = nil,
        isRunning: Bool = false
    ) {
        self.index = index
        self.kind = kind
        self.title = title
        self.badge = Self.sanitized(badge)
        self.locator = locator
        self.isRunning = isRunning
    }

    public static func locator(for url: URL) -> String {
        url.isFileURL ? url.standardizedFileURL.path : url.absoluteString
    }

    static func sanitized(_ badge: String?) -> String? {
        guard let badge else { return nil }
        let collapsed =
            badge
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        guard !collapsed.isEmpty else { return nil }
        return collapsed.clampedLength(to: maximumBadgeLength)
    }
}

public struct DockItemList: Sendable, Equatable {
    public let items: [DockItem]

    public init(items: [DockItem]) {
        self.items = items
    }

    public static let empty = DockItemList(items: [])

    public var isEmpty: Bool { items.isEmpty }

    public var badgeCount: Int {
        items.filter { $0.badge != nil }.count
    }
}
