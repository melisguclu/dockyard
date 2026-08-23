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
        let context = Context(menu: menu, tile: tile, target: target, action: action)

        switch tile.kind {
        case .application:
            if tile.isRunning {
                append(.activate, title: "Show", to: context)
                append(
                    tile.isHidden ? .unhide : .hide,
                    title: tile.isHidden ? "Show All Windows" : "Hide",
                    to: context
                )
            } else {
                append(.activate, title: "Open", to: context)
            }
            if tile.url != nil {
                menu.addItem(.separator())
                append(.showInFinder, title: "Show in Finder", to: context)
            }
            if tile.isRunning {
                menu.addItem(.separator())
                append(.quit, title: "Quit", to: context)
                append(.forceQuit, title: "Force Quit", to: context)
            }
        case .folder:
            append(.open, title: "Open", to: context)
            append(.showInFinder, title: "Show in Finder", to: context)
        case .url:
            append(.open, title: "Open", to: context)
        case .trash:
            append(.open, title: "Open", to: context)
        case .separator, .spacer:
            return nil
        }

        return menu.items.isEmpty ? nil : menu
    }

    private struct Context {
        let menu: NSMenu
        let tile: DockTile
        let target: AnyObject
        let action: Selector
    }

    private static func append(_ command: DockTileMenuCommand, title: String, to context: Context) {
        let item = NSMenuItem(title: title, action: context.action, keyEquivalent: "")
        item.target = context.target
        item.isEnabled = true
        item.representedObject = DockTileMenuCommandBox(command: command, tile: context.tile)
        context.menu.addItem(item)
    }
}
