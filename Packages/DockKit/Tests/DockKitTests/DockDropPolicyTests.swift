import AppKit
import DockCore
import DockKit
import Foundation
import Testing

@Suite("What a tile accepts when a file is dragged onto it")
struct DockDropPolicyTests {
    private let everything: NSDragOperation = [.copy, .move, .link, .delete, .generic]

    @Test("An application tile takes a copy, which is what opening a file with it is")
    func application() {
        #expect(DockDropPolicy.operation(for: TileFactory.application("Preview"), allowed: everything) == .copy)
    }

    @Test("The Trash takes a move")
    func trash() {
        #expect(DockDropPolicy.operation(for: TileFactory.trash, allowed: everything) == .move)
    }

    @Test("The Trash refuses what the source will not let it move")
    func trashWithoutMove() {
        let operation = DockDropPolicy.operation(for: TileFactory.trash, allowed: [.copy, .link])
        #expect(operation.isEmpty)
    }

    @Test("The separator and the spacers are not drop targets")
    func inertTiles() {
        #expect(DockDropPolicy.operation(for: TileFactory.separator, allowed: everything).isEmpty)
        #expect(DockDropPolicy.operation(for: TileFactory.spacer(.full), allowed: everything).isEmpty)
    }
}
