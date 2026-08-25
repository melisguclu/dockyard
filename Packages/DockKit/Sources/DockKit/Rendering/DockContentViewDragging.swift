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
    }

    override public func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        defer { setDropTarget(nil) }
        guard let identifier = dropTargetIdentifier,
            let tile = snapshot.tile(with: identifier),
            let urls = fileURLs(from: sender), !urls.isEmpty
        else { return false }
        delegate?.dockContentView(self, didDrop: urls, on: tile)
        return true
    }

    private func dragOperation(for sender: any NSDraggingInfo) -> NSDragOperation {
        dismissTileLabel()
        let point = convert(sender.draggingLocation, from: nil)
        guard let tile = tile(at: point), canAcceptDrop(on: tile) else {
            setDropTarget(nil)
            return []
        }
        setDropTarget(tile.id)
        return .copy
    }

    private func canAcceptDrop(on tile: DockTile) -> Bool {
        switch tile.kind {
        case .application:
            return true
        default:
            return false
        }
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
