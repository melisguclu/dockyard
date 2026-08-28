import AppKit
import DockCore
import Foundation

extension DockContentView {
    override public func rightMouseDown(with event: NSEvent) {
        let point = location(of: event)
        guard let index = DockGeometry.hitIndex(in: currentLayout, at: point),
            index < snapshot.tiles.count
        else { return }
        presentTileMenu(for: snapshot.tiles[index], at: point)
    }

    func presentTileMenu(for tile: DockTile, at point: CGPoint? = nil) {
        guard let window, tile.providesMenu else { return }
        guard let index = snapshot.tiles.firstIndex(where: { $0.id == tile.id }),
            index < currentLayout.tileFrames.count
        else { return }

        let screen = window.screen?.visibleFrame ?? window.frame
        let height = screen.height - 2 * tileMenu.metrics.screenInset
        let items = delegate?.dockContentView(self, menuItemsFor: tile, availableHeight: height) ?? []
        guard !items.isEmpty else { return }

        let frame = currentLayout.tileFrames[index]
        let anchor = window.convertToScreen(convert(frame, to: nil))
        beginMenuSession(for: tile.id, at: point ?? CGPoint(x: frame.midX, y: frame.midY))
        tileMenu.present(
            DockMenuRequest(
                items: items,
                anchor: anchor,
                orientation: snapshot.appearance.orientation,
                screen: screen,
                appearance: effectiveAppearance
            ),
            onSelect: { [weak self] item in
                guard let self, let command = item.command else { return }
                self.delegate?.dockContentView(self, didSelect: command, on: tile)
            },
            onDismiss: { [weak self] in
                self?.endMenuSession()
            }
        )
    }

    func beginMenuSession(for identifier: DockTileID, at point: CGPoint) {
        menuIdentifier = identifier
        dismissTileLabel()
        setPressed(identifier)
        guard magnificationAvailable else { return }
        requestMagnification(true)
        cursor = pointerLocation() ?? point
        magnificationTarget = 1
        startFrameLink()
    }

    func endMenuSession() {
        menuIdentifier = nil
        setPressed(nil)
        startFrameLink()
    }
}
