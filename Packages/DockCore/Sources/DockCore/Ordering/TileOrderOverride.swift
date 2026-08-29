import Foundation

public struct TileOrderOverride: Sendable, Equatable {
    public let keys: [String]

    public init(keys: [String]) {
        self.keys = keys
    }

    public static let empty = TileOrderOverride(keys: [])

    public var isEmpty: Bool { keys.isEmpty }

    public static func recorded(_ tiles: [DockTile]) -> TileOrderOverride {
        TileOrderOverride(keys: tiles.compactMap { $0.isReorderable ? $0.id.persistenceKey : nil })
    }

    public func applied(to tiles: [DockTile]) -> [DockTile] {
        guard !isEmpty, !tiles.isEmpty else { return tiles }

        var ranks: [String: Int] = [:]
        for (rank, key) in keys.enumerated() where ranks[key] == nil {
            ranks[key] = rank
        }

        let trailingTrash = tiles.last?.isTrashTile == true ? tiles.last : nil
        let body = trailingTrash == nil ? tiles : Array(tiles.dropLast())

        guard let separator = body.firstIndex(where: \.isSeparatorTile) else {
            return ordered(body, ranks: ranks) + [trailingTrash].compactMap { $0 }
        }

        let leading = ordered(Array(body[..<separator]), ranks: ranks)
        let trailing = ordered(Array(body[(separator + 1)...]), ranks: ranks)
        return leading + [body[separator]] + trailing + [trailingTrash].compactMap { $0 }
    }

    private func ordered(_ tiles: [DockTile], ranks: [String: Int]) -> [DockTile] {
        TileSequence.ordered(tiles) { tile in
            guard tile.isReorderable, let key = tile.id.persistenceKey else { return nil }
            return ranks[key]
        }
    }
}

extension DockTile {
    public var isReorderable: Bool {
        guard id.persistenceKey != nil else { return false }
        switch kind {
        case .application, .folder, .url:
            return true
        case .trash, .minimizedWindow, .separator, .spacer:
            return false
        }
    }

    public var isSeparatorTile: Bool {
        if case .separator = kind { return true }
        return false
    }

    public var isTrashTile: Bool {
        if case .trash = kind { return true }
        return false
    }
}
