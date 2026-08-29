import DockCore
import Foundation

public enum DockReorderPolicy {
    public static func canDrag(_ tile: DockTile) -> Bool {
        tile.isReorderable
    }

    public static func reordered(
        _ tiles: [DockTile],
        moving identifier: DockTileID,
        to target: Int
    ) -> [DockTile]? {
        guard target >= 0, target < tiles.count else { return nil }
        guard let current = tiles.firstIndex(where: { $0.id == identifier }), current != target else {
            return nil
        }
        guard canDrag(tiles[current]), canDrag(tiles[target]) else { return nil }
        guard sameRegion(in: tiles, current, target) else { return nil }

        var result = tiles
        let moved = result.remove(at: current)
        result.insert(moved, at: target)
        return result
    }

    private static func sameRegion(in tiles: [DockTile], _ left: Int, _ right: Int) -> Bool {
        guard let separator = tiles.firstIndex(where: \.isSeparatorTile) else { return true }
        return (left < separator) == (right < separator)
    }
}
