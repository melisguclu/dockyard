import Foundation

public enum DockItemMatching {
    public static let minimumMatchRatio = 0.5

    public static func applied(_ list: DockItemList, to tiles: [DockTile]) -> [DockTile] {
        guard !list.isEmpty, !tiles.isEmpty else { return tiles }

        var index = ItemIndex(list)
        var matches: [DockTileID: DockItem] = [:]
        var eligible = 0

        for tile in tiles where tile.hasDockItem {
            eligible += 1
            guard let item = index.take(for: tile) else { continue }
            matches[tile.id] = item
        }

        guard eligible > 0 else { return tiles }
        guard Double(matches.count) / Double(eligible) >= minimumMatchRatio else {
            DockLog.dockItems.error(
                """
                Only \(matches.count, privacy: .public) of \(eligible, privacy: .public) tiles matched a \
                dock item, so the Dock's own order and badges are ignored
                """
            )
            return tiles
        }

        let badged = tiles.map { $0.withBadge(matches[$0.id]?.badge) }
        return TileSequence.ordered(badged) { matches[$0.id]?.index }
    }

    private struct TitleKey: Hashable {
        let kind: DockItemKind
        let title: String
    }

    private struct ItemIndex {
        private var locators: [String: [DockItem]] = [:]
        private var titles: [TitleKey: [DockItem]] = [:]
        private var byKind: [DockItemKind: [DockItem]] = [:]

        init(_ list: DockItemList) {
            for item in list.items {
                if let locator = item.locator {
                    locators[locator, default: []].append(item)
                }
                if let title = item.title, !title.isEmpty {
                    titles[TitleKey(kind: item.kind, title: title), default: []].append(item)
                }
                byKind[item.kind, default: []].append(item)
            }
        }

        mutating func take(for tile: DockTile) -> DockItem? {
            switch tile.kind {
            case .separator:
                return take(kind: .separator)
            case .trash:
                return take(kind: .trash)
            case .minimizedWindow:
                return take(title: tile.label, kind: .minimizedWindow)
            case .application, .folder, .url:
                if let locator = tile.locator, let item = take(locator: locator) { return item }
                return take(title: tile.label, kind: kind(of: tile))
            case .spacer:
                return nil
            }
        }

        private func kind(of tile: DockTile) -> DockItemKind {
            switch tile.kind {
            case .application:
                return .application
            case .folder:
                return .folder
            case .url:
                return .url
            default:
                return .unknown
            }
        }

        private mutating func take(locator: String) -> DockItem? {
            guard var queue = locators[locator], !queue.isEmpty else { return nil }
            let item = queue.removeFirst()
            locators[locator] = queue
            consume(item)
            return item
        }

        private mutating func take(title: String, kind: DockItemKind) -> DockItem? {
            let key = TitleKey(kind: kind, title: title)
            guard var queue = titles[key], !queue.isEmpty else { return nil }
            let item = queue.removeFirst()
            titles[key] = queue
            consume(item)
            return item
        }

        private mutating func take(kind: DockItemKind) -> DockItem? {
            guard var queue = byKind[kind], !queue.isEmpty else { return nil }
            let item = queue.removeFirst()
            byKind[kind] = queue
            consume(item)
            return item
        }

        private mutating func consume(_ item: DockItem) {
            if let locator = item.locator {
                locators[locator]?.removeAll { $0.index == item.index }
            }
            if let title = item.title {
                titles[TitleKey(kind: item.kind, title: title)]?.removeAll { $0.index == item.index }
            }
            byKind[item.kind]?.removeAll { $0.index == item.index }
        }
    }
}

extension DockTile {
    public var hasDockItem: Bool {
        switch kind {
        case .spacer:
            return false
        default:
            return true
        }
    }
}
