import AppKit
import DockCore
import Foundation

extension DockContentView {
    public func setLaunching(_ identifiers: Set<DockTileID>) {
        guard requestedLaunching != identifiers else { return }
        requestedLaunching = identifiers
        refreshLaunchAnimations()
    }

    func refreshLaunchAnimations() {
        let bounce = DockLaunchBounce(appearance: snapshot.appearance)
        let active: Set<DockTileID> = bounce == nil ? [] : requestedLaunching.filter(bounces)
        guard active != launchingTiles || bounce != appliedBounce else { return }

        let previous = launchingTiles
        let previousBounce = appliedBounce
        launchingTiles = active
        appliedBounce = bounce

        var settle: Double = 0
        for identifier in previous.subtracting(active) {
            settle = max(settle, tileLayers[identifier]?.finishLaunching() ?? 0)
        }

        if active.isEmpty, settle > 0 {
            shrinkAfterSettle(settle)
        } else {
            launchSettleTask?.cancel()
            launchSettleTask = nil
            syncPanelExtent()
        }

        guard let bounce else { return }
        let restarts = bounce != previousBounce
        for identifier in active where restarts || !previous.contains(identifier) {
            tileLayers[identifier]?.setLaunching(bounce)
        }
    }

    private func shrinkAfterSettle(_ settle: Double) {
        launchSettleTask?.cancel()
        launchSettleTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(settle))
            guard !Task.isCancelled, let self else { return }
            self.launchSettleTask = nil
            self.syncPanelExtent()
        }
    }

    private func bounces(_ identifier: DockTileID) -> Bool {
        guard tileLayers[identifier] != nil, let tile = snapshot.tile(with: identifier) else { return false }
        guard case .application = tile.kind else { return false }
        return true
    }

    @discardableResult
    func requestMagnification(_ magnified: Bool) -> Bool {
        wantsMagnification = magnified
        return syncPanelExtent()
    }

    @discardableResult
    func syncPanelExtent() -> Bool {
        var extent: DockPanelExtent = .resting
        if wantsMagnification {
            extent.insert(.magnified)
        }
        if !launchingTiles.isEmpty {
            extent.insert(.bouncing)
        }
        guard panelExtent != extent else { return false }
        panelExtent = extent
        delegate?.dockContentView(self, needs: extent)
        return true
    }
}
