import AppKit
import DockCore
import Foundation

extension DockContentView {
    public static let reorderThreshold: CGFloat = 8
    public static let slideDuration: CFTimeInterval = 0.22
    static let slideSettleFactor: CFTimeInterval = 3
    static let slideEpsilon: CGFloat = 0.4

    var reorderIsActive: Bool { reorderIdentifier != nil }

    var isSliding: Bool { !slideResiduals.isEmpty }

    func shouldBeginReorder(for tile: DockTile, from origin: CGPoint, to point: CGPoint) -> Bool {
        guard delegate?.dockContentViewAllowsReordering(self) == true else { return false }
        guard menuIdentifier == nil, !exposeDidPresent else { return false }
        guard DockReorderPolicy.canDrag(tile) else { return false }
        return travel(from: origin, to: point) >= Self.reorderThreshold
    }

    func beginReorderIfNeeded(for identifier: DockTileID, at point: CGPoint) -> Bool {
        guard let origin = pressOrigin, let pressed = tile(with: identifier) else { return false }
        guard shouldBeginReorder(for: pressed, from: origin, to: point) else { return false }
        beginReorder(for: pressed, at: point)
        trackReorder(at: point)
        return true
    }

    func beginReorder(for tile: DockTile, at point: CGPoint) {
        cancelExposeHold()
        reorderIdentifier = tile.id
        reorderedTiles = tiles
        reorderPointer = point
        reorderGrab = grabFraction(for: tile.id, at: point)
        tileLayers[tile.id]?.setLifted(true)
        setPressed(tile.id)
        startFrameLink()
    }

    func trackReorder(at point: CGPoint) {
        guard let identifier = reorderIdentifier, let ordered = reorderedTiles else { return }
        reorderPointer = point

        guard let target = DockGeometry.hitIndex(in: currentLayout, at: point),
            let moved = DockReorderPolicy.reordered(ordered, moving: identifier, to: target)
        else {
            relayout()
            return
        }

        let before = appliedTileFrames
        reorderedTiles = moved
        relayout()
        for (tile, frame) in appliedTileFrames where tile != identifier {
            guard let previous = before[tile] else { continue }
            let residual = along(CGPoint(x: previous.minX - frame.minX, y: previous.minY - frame.minY))
            guard abs(residual) >= Self.slideEpsilon else { continue }
            slideResiduals[tile] = residual
        }
        relayout()
        startFrameLink()
    }

    func advanceSlides(_ delta: CFTimeInterval) -> Bool {
        guard !slideResiduals.isEmpty else { return false }
        let constant = Self.slideDuration / Self.slideSettleFactor
        let decay = CGFloat(exp(-delta / constant))
        for (tile, residual) in slideResiduals {
            let next = residual * decay
            if abs(next) < Self.slideEpsilon {
                slideResiduals.removeValue(forKey: tile)
            } else {
                slideResiduals[tile] = next
            }
        }
        return true
    }

    func commitReorder() {
        guard let proposed = reorderedTiles, let identifier = reorderIdentifier else { return }
        let dragged = appliedTileFrames[identifier]
        reorderIdentifier = nil
        reorderedTiles = nil
        reorderPointer = nil
        tileLayers[identifier]?.setLifted(false)

        if proposed.map(\.id) != snapshot.tiles.map(\.id) {
            delegate?.dockContentView(self, didReorder: proposed)
        }
        relayout()
        settleDraggedTile(identifier, from: dragged)
        startFrameLink()
    }

    func cancelReorder() {
        guard let identifier = reorderIdentifier else { return }
        reorderIdentifier = nil
        reorderedTiles = nil
        reorderPointer = nil
        slideResiduals.removeAll()
        tileLayers[identifier]?.setLifted(false)
        setPressed(nil)
        relayout()
    }

    func rebaseReorder(with snapshot: DockSnapshot) {
        guard let ordered = reorderedTiles else { return }
        let incoming = Dictionary(snapshot.tiles.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        guard Set(incoming.keys) == Set(ordered.map(\.id)) else {
            cancelReorder()
            return
        }
        reorderedTiles = ordered.compactMap { incoming[$0.id] }
    }

    func reorderedFrame(_ frame: CGRect, of tile: DockTile) -> CGRect {
        if tile.id == reorderIdentifier, let pointer = reorderPointer {
            return draggedFrame(frame, pointer: pointer)
        }
        guard let residual = slideResiduals[tile.id] else { return frame }
        return snapshot.appearance.orientation.isVertical
            ? frame.offsetBy(dx: 0, dy: residual)
            : frame.offsetBy(dx: residual, dy: 0)
    }

    private func settleDraggedTile(_ identifier: DockTileID, from dragged: CGRect?) {
        guard let dragged, let settled = appliedTileFrames[identifier] else { return }
        let residual = along(
            CGPoint(x: dragged.minX - settled.minX, y: dragged.minY - settled.minY)
        )
        guard abs(residual) >= Self.slideEpsilon else { return }
        slideResiduals[identifier] = residual
        relayout()
    }

    private func draggedFrame(_ frame: CGRect, pointer: CGPoint) -> CGRect {
        let bar = currentLayout.barRect
        if snapshot.appearance.orientation.isVertical {
            let y = pointer.y - frame.height * reorderGrab
            return CGRect(
                x: frame.minX,
                y: y.clamped(to: bar.minY - frame.height / 2...bar.maxY - frame.height / 2),
                width: frame.width,
                height: frame.height
            )
        }
        let x = pointer.x - frame.width * reorderGrab
        return CGRect(
            x: x.clamped(to: bar.minX - frame.width / 2...bar.maxX - frame.width / 2),
            y: frame.minY,
            width: frame.width,
            height: frame.height
        )
    }

    private func grabFraction(for identifier: DockTileID, at point: CGPoint) -> CGFloat {
        guard let frame = appliedTileFrames[identifier] else { return 0.5 }
        let fraction =
            snapshot.appearance.orientation.isVertical
            ? (point.y - frame.minY) / max(frame.height, 1)
            : (point.x - frame.minX) / max(frame.width, 1)
        return fraction.clamped(to: 0...1)
    }

    private func travel(from origin: CGPoint, to point: CGPoint) -> CGFloat {
        snapshot.appearance.orientation.isVertical
            ? abs(point.y - origin.y)
            : abs(point.x - origin.x)
    }

    private func along(_ delta: CGPoint) -> CGFloat {
        snapshot.appearance.orientation.isVertical ? delta.y : delta.x
    }
}
