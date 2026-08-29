import AppKit
import DockCore
import Foundation

extension DockContentView {
    override public func isAccessibilityElement() -> Bool { false }

    override public func accessibilityRole() -> NSAccessibility.Role? { .group }

    override public func accessibilityRoleDescription() -> String? {
        DockKitText.string("accessibility.dockDescription")
    }

    override public func accessibilityLabel() -> String? {
        DockKitText.string("accessibility.dock")
    }

    override public func accessibilityChildren() -> [Any]? {
        accessibilityProxiesAreLive = true
        refreshAccessibilityProxies()
        return orderedAccessibilityProxies()
    }

    func refreshAccessibilityProxies() {
        guard accessibilityProxiesAreLive, let window else { return }
        let live = Set(tiles.map(\.id))
        for identifier in accessibilityProxies.keys where !live.contains(identifier) {
            accessibilityProxies.removeValue(forKey: identifier)
        }
        for (index, tile) in tiles.enumerated() where index < currentLayout.tileFrames.count {
            let frame = window.convertToScreen(convert(currentLayout.tileFrames[index], to: nil))
            guard let existing = accessibilityProxies[tile.id] else {
                let element = DockTileAccessibilityElement(tile: tile, parent: self)
                element.setAccessibilityFrame(frame)
                element.onPress = { [weak self] identifier in self?.performAccessibilityPress(identifier) }
                element.onShowMenu = { [weak self] identifier in self?.showAccessibilityMenu(identifier) }
                accessibilityProxies[tile.id] = element
                continue
            }
            existing.update(with: tile)
            existing.setAccessibilityFrame(frame)
        }
    }

    func orderedAccessibilityProxies() -> [DockTileAccessibilityElement] {
        tiles.compactMap { accessibilityProxies[$0.id] }
    }

    func announceAccessibilityFocus(_ identifier: DockTileID) {
        guard accessibilityProxiesAreLive, let element = accessibilityProxies[identifier] else { return }
        NSAccessibility.post(element: element, notification: .focusedUIElementChanged)
    }

    private func performAccessibilityPress(_ identifier: DockTileID) {
        guard let tile = tile(with: identifier), tile.isInteractive else { return }
        delegate?.dockContentView(self, didActivate: tile)
    }

    private func showAccessibilityMenu(_ identifier: DockTileID) {
        guard let tile = tile(with: identifier), tile.providesMenu else { return }
        presentTileMenu(for: tile)
    }
}
