public struct DockSnapshot: Sendable, Equatable {
    public let tiles: [DockTile]
    public let appearance: DockAppearance
    public let generation: UInt64

    public init(tiles: [DockTile], appearance: DockAppearance, generation: UInt64 = 0) {
        self.tiles = tiles
        self.appearance = appearance
        self.generation = generation
    }

    public static let empty = DockSnapshot(tiles: [], appearance: .default, generation: 0)

    public func withAppearance(_ appearance: DockAppearance) -> DockSnapshot {
        DockSnapshot(tiles: tiles, appearance: appearance, generation: generation)
    }

    public func tile(with id: DockTileID) -> DockTile? {
        tiles.first { $0.id == id }
    }
}
