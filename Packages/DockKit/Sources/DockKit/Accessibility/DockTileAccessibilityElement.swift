import AppKit
import DockCore
import Foundation

final class DockTileAccessibilityElement: NSAccessibilityElement {
    let identifier: DockTileID
    var onPress: (@MainActor (DockTileID) -> Void)?
    var onShowMenu: (@MainActor (DockTileID) -> Void)?

    private var roleDescription: String

    init(tile: DockTile, parent: NSView) {
        identifier = tile.id
        roleDescription = Self.description(of: tile)
        super.init()
        setAccessibilityParent(parent)
        setAccessibilityRole(.button)
        setAccessibilityRoleDescription(roleDescription)
        setAccessibilityLabel(tile.label)
        setAccessibilityEnabled(tile.isInteractive)
    }

    func update(with tile: DockTile) {
        roleDescription = Self.description(of: tile)
        setAccessibilityLabel(tile.label)
        setAccessibilityRoleDescription(roleDescription)
        setAccessibilityEnabled(tile.isInteractive)
        setAccessibilityValue(Self.value(of: tile))
    }

    override func isAccessibilityElement() -> Bool { true }

    override func accessibilityPerformPress() -> Bool {
        let identifier = identifier
        let action = onPress
        MainActor.assumeIsolated { action?(identifier) }
        return true
    }

    override func accessibilityPerformShowMenu() -> Bool {
        let identifier = identifier
        let action = onShowMenu
        MainActor.assumeIsolated { action?(identifier) }
        return true
    }

    private static func description(of tile: DockTile) -> String {
        switch tile.kind {
        case .application:
            return DockKitText.string("accessibility.application")
        case .folder:
            return DockKitText.string("accessibility.folder")
        case .url:
            return DockKitText.string("accessibility.webLocation")
        case .trash:
            return DockKitText.string("accessibility.trash")
        case .minimizedWindow:
            return DockKitText.string("accessibility.minimizedWindow")
        case .separator:
            return DockKitText.string("accessibility.separator")
        case .spacer:
            return DockKitText.string("accessibility.spacer")
        }
    }

    private static func value(of tile: DockTile) -> String? {
        guard case .application = tile.kind else { return nil }
        if tile.isHidden {
            return DockKitText.string("accessibility.hidden")
        }
        return tile.isRunning ? DockKitText.string("accessibility.running") : nil
    }
}
