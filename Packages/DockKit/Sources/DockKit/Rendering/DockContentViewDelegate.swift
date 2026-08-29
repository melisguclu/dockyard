import CoreGraphics
import DockCore
import Foundation

@MainActor
public protocol DockContentViewDelegate: AnyObject {
    func dockContentView(_ view: DockContentView, needs extent: DockPanelExtent)
    func dockContentView(_ view: DockContentView, didActivate tile: DockTile)
    func dockContentView(
        _ view: DockContentView,
        menuItemsFor tile: DockTile,
        availableHeight: CGFloat
    ) -> [DockMenuItem]
    func dockContentView(
        _ view: DockContentView,
        windowItemsFor tile: DockTile,
        availableHeight: CGFloat
    ) -> [DockMenuItem]
    func dockContentView(_ view: DockContentView, didSelect command: DockTileMenuCommand, on tile: DockTile)
    func dockContentView(_ view: DockContentView, didDrop urls: [URL], on tile: DockTile)
    func dockContentViewAllowsReordering(_ view: DockContentView) -> Bool
    func dockContentView(_ view: DockContentView, didReorder tiles: [DockTile])
    func dockContentView(_ view: DockContentView, springLoaded tile: DockTile)
    func dockContentView(_ view: DockContentView, needsIconFor tile: DockTile, pixelSize: Int)
    func dockContentViewPointerDidLeave(_ view: DockContentView)
}
