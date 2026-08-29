import AppKit
import DockCore
import Foundation

extension DockContentView {
    public static let exposeHoldDelay: TimeInterval = 0.65

    func beginExposeHold(for tile: DockTile) {
        cancelExposeHold()
        guard case .application = tile.kind, tile.isRunning else { return }
        let identifier = tile.id
        exposeHoldTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(Self.exposeHoldDelay))
            guard !Task.isCancelled, let self else { return }
            self.exposeHoldTask = nil
            self.presentAppExpose(for: identifier)
        }
    }

    func cancelExposeHold() {
        exposeHoldTask?.cancel()
        exposeHoldTask = nil
    }

    private func presentAppExpose(for identifier: DockTileID) {
        guard let target = tile(with: identifier), menuIdentifier == nil else { return }
        guard let pointer = pointerLocation(), tile(at: pointer)?.id == identifier else { return }
        exposeDidPresent = true
        presentTileMenu(for: target, content: .windows)
    }
}
