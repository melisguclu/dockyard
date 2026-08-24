import DockCore
import Foundation

public enum DockTileMenuCommand: Sendable, Equatable {
    case activate
    case open
    case showInFinder
    case hide
    case unhide
    case quit
    case forceQuit
}

public enum DockTileMenuBuilder {
    public static func items(for tile: DockTile) -> [DockMenuItem] {
        var items: [DockMenuItem] = []

        switch tile.kind {
        case .application:
            if tile.isRunning {
                items.append(.command(.activate, title: "Show"))
                items.append(
                    .command(
                        tile.isHidden ? .unhide : .hide,
                        title: tile.isHidden ? "Show All Windows" : "Hide"
                    )
                )
            } else {
                items.append(.command(.activate, title: "Open"))
            }
            if tile.url != nil {
                items.append(.separator)
                items.append(.command(.showInFinder, title: "Show in Finder"))
            }
            if tile.isRunning {
                items.append(.separator)
                items.append(.command(.quit, title: "Quit"))
                items.append(.command(.forceQuit, title: "Force Quit"))
            }
        case .folder:
            items.append(.command(.open, title: "Open"))
            items.append(.command(.showInFinder, title: "Show in Finder"))
        case .url:
            items.append(.command(.open, title: "Open"))
        case .trash:
            items.append(.command(.open, title: "Open"))
        case .separator, .spacer:
            return []
        }

        return items
    }
}
