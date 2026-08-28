import AppKit
import DockCore
import Foundation

extension DockPanelController {
    func noteStackDismissal(_ identifier: DockTileID?) {
        guard let identifier else { return }
        lastStackDismissal = StackDismissal(
            identifier: identifier,
            uptime: ProcessInfo.processInfo.systemUptime
        )
    }

    func closesStack(for tile: DockTile) -> Bool {
        guard let last = lastStackDismissal, last.identifier == tile.id else { return false }
        lastStackDismissal = nil
        return ProcessInfo.processInfo.systemUptime - last.uptime < Self.stackToggleWindow
    }

    func presentStack(for tile: DockTile, presentation: FolderPresentation) {
        guard let url = tile.url else { return }
        guard !closesStack(for: tile) else { return }
        guard let anchor = contentView.screenAnchor(for: tile.id) else {
            activator.openFolder(url)
            return
        }
        contentView.holdTileSession(for: tile.id)
        stack.present(
            DockStackRequest(
                identifier: tile.id,
                url: url,
                presentation: presentation,
                anchor: anchor,
                orientation: snapshot.appearance.orientation,
                screen: contentView.hostScreenFrame,
                appearance: contentView.effectiveAppearance
            )
        )
    }
}
