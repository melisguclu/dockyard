import DockCore
import Foundation

public struct DockMenuItem: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case command(DockTileMenuCommand)
        case separator
    }

    public let kind: Kind
    public let title: String
    public let isEnabled: Bool

    public init(kind: Kind, title: String, isEnabled: Bool = true) {
        self.kind = kind
        self.title = title
        self.isEnabled = isEnabled
    }

    public static func command(_ command: DockTileMenuCommand, title: String) -> DockMenuItem {
        DockMenuItem(kind: .command(command), title: title)
    }

    public static let separator = DockMenuItem(kind: .separator, title: "")

    public var isSelectable: Bool {
        guard case .command = kind, isEnabled else { return false }
        return true
    }

    public var command: DockTileMenuCommand? {
        guard case .command(let command) = kind else { return nil }
        return command
    }
}
