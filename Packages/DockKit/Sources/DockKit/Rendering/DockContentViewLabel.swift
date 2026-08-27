import AppKit
import DockCore
import Foundation

extension DockContentView {
    public func dismissTileLabel() {
        labelIdentifier = nil
        tileLabel.dismiss()
    }

    func updateTileLabel(at point: CGPoint?) {
        guard menuIdentifier == nil, dropTargetIdentifier == nil, let point, let window,
            let index = DockGeometry.hitIndex(in: currentLayout, at: point), index < snapshot.tiles.count
        else {
            dismissTileLabel()
            return
        }

        let tile = snapshot.tiles[index]
        guard tile.isInteractive, !tile.label.isEmpty else {
            dismissTileLabel()
            return
        }

        labelIdentifier = tile.id
        tileLabel.present(
            DockTileLabelRequest(
                identifier: tile.id,
                text: tile.label,
                anchor: window.convertToScreen(convert(currentLayout.tileFrames[index], to: nil)),
                orientation: snapshot.appearance.orientation,
                screen: window.screen?.visibleFrame ?? window.frame,
                appearance: effectiveAppearance
            )
        )
    }
}
