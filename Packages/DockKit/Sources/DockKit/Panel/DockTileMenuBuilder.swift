import AppKit
import DockCore
import Foundation

public enum DockTileMenuCommand: Sendable {
    case activate
    case open
    case showInFinder
    case hide
    case unhide
    case quit
    case forceQuit
}

public final class DockTileMenuCommandBox: NSObject {
    public let command: DockTileMenuCommand
    public let tile: DockTile

    public init(command: DockTileMenuCommand, tile: DockTile) {
        self.command = command
        self.tile = tile
    }
}

@MainActor
public enum DockTileMenuBuilder {
    public static func menu(for tile: DockTile, target: AnyObject, action: Selector) -> NSMenu? {
        let menu = NSMenu()
        menu.autoenablesItems = false

        switch tile.kind {
        case .application:
            if tile.isRunning {
                append(.activate, title: "Show", to: menu, tile: tile, target: target, action: action)
                append(
                    tile.isHidden ? .unhide : .hide,
                    title: tile.isHidden ? "Show All Windows" : "Hide",
                    to: menu,
                    tile: tile,
                    target: target,
                    action: action
                )
            } else {
                append(.activate, title: "Open", to: menu, tile: tile, target: target, action: action)
            }
            if tile.url != nil {
                menu.addItem(.separator())
                append(
                    .showInFinder,
                    title: "Show in Finder",
                    to: menu,
                    tile: tile,
                    target: target,
                    action: action
                )
            }
            if tile.isRunning {
                menu.addItem(.separator())
                append(.quit, title: "Quit", to: menu, tile: tile, target: target, action: action)
                append(.forceQuit, title: "Force Quit", to: menu, tile: tile, target: target, action: action)
            }
        case .folder:
            append(.open, title: "Open", to: menu, tile: tile, target: target, action: action)
            append(
                .showInFinder,
                title: "Show in Finder",
                to: menu,
                tile: tile,
                target: target,
                action: action
            )
        case .url:
            append(.open, title: "Open", to: menu, tile: tile, target: target, action: action)
        case .trash:
            append(.open, title: "Open", to: menu, tile: tile, target: target, action: action)
        case .separator, .spacer:
            return nil
        }

        return menu.items.isEmpty ? nil : menu
    }

    private static func append(
        _ command: DockTileMenuCommand,
        title: String,
        to menu: NSMenu,
        tile: DockTile,
        target: AnyObject,
        action: Selector
    ) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = target
        item.isEnabled = true
        item.representedObject = DockTileMenuCommandBox(command: command, tile: tile)
        menu.addItem(item)
    }
}
