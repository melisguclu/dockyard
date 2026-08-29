import AppKit
import DockCore
import Foundation

extension DockContentView {
    override public func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        dragOperation(for: sender)
    }

    override public func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        dragOperation(for: sender)
    }

    override public func draggingExited(_ sender: (any NSDraggingInfo)?) {
        setDropTarget(nil)
        setSpringTarget(nil)
    }

    override public func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        defer {
            setDropTarget(nil)
            setSpringTarget(nil)
        }
        guard let identifier = dropTargetIdentifier,
            let tile = tile(with: identifier),
            let urls = fileURLs(from: sender), !urls.isEmpty
        else { return false }
        delegate?.dockContentView(self, didDrop: urls, on: tile)
        return true
    }

    private func dragOperation(for sender: any NSDraggingInfo) -> NSDragOperation {
        dismissTileLabel()
        let point = convert(sender.draggingLocation, from: nil)
        guard let tile = tile(at: point) else {
            setDropTarget(nil)
            setSpringTarget(nil)
            return []
        }
        setSpringTarget(tile)
        let operation = DockDropPolicy.operation(
            for: tile,
            allowed: sender.draggingSourceOperationMask
        )
        guard !operation.isEmpty else {
            setDropTarget(nil)
            return []
        }
        setDropTarget(tile.id)
        return operation
    }

    private func setDropTarget(_ identifier: DockTileID?) {
        guard dropTargetIdentifier != identifier else { return }
        if let previous = dropTargetIdentifier {
            tileLayers[previous]?.setHighlighted(false)
        }
        dropTargetIdentifier = identifier
        if let identifier {
            tileLayers[identifier]?.setHighlighted(true)
        }
    }

    private func setSpringTarget(_ tile: DockTile?) {
        let candidate = tile.flatMap { DockDropPolicy.springs(on: $0) ? $0 : nil }
        guard candidate?.id != springIdentifier else { return }
        springTask?.cancel()
        springTask = nil
        springIdentifier = candidate?.id
        guard let candidate else { return }

        let settings = SpringLoadingSettings.current
        guard settings.isEnabled else { return }
        springTask = Task { @MainActor [weak self] in
            if settings.delay > 0 {
                try? await Task.sleep(for: .seconds(settings.delay))
            }
            guard !Task.isCancelled, let self, self.springIdentifier == candidate.id else { return }
            self.springTask = nil
            self.delegate?.dockContentView(self, springLoaded: candidate)
        }
    }

    private func fileURLs(from sender: any NSDraggingInfo) -> [URL]? {
        sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL]
    }

}

final class DockTileContainerView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var isOpaque: Bool { false }
}
