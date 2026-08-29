import Foundation

public enum TileSequence {
    public static let unmatchedStep = 0.001

    public static func ordered(_ tiles: [DockTile], rank: (DockTile) -> Int?) -> [DockTile] {
        var keys: [Double] = []
        keys.reserveCapacity(tiles.count)
        var anchor = -1.0
        var run = 0

        for tile in tiles {
            guard let rank = rank(tile) else {
                run += 1
                keys.append(anchor + Double(run) * unmatchedStep)
                continue
            }
            anchor = Double(rank)
            run = 0
            keys.append(anchor)
        }

        return zip(tiles, keys)
            .enumerated()
            .sorted { left, right in
                left.element.1 == right.element.1
                    ? left.offset < right.offset
                    : left.element.1 < right.element.1
            }
            .map(\.element.0)
    }
}
