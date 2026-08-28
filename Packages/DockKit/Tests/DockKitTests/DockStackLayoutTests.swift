import DockCore
import DockKit
import Foundation
import Testing

@Suite("A stack lays its folder out as a fan, a grid, or a list")
struct DockStackLayoutTests {
    private let metrics = DockStackMetrics.current
    private let screen = CGRect(x: 0, y: 0, width: 1512, height: 944)
    private let anchor = CGRect(x: 700, y: 8, width: 48, height: 48)

    private func input(
        _ count: Int,
        requested: FolderStackViewMode = .automatic,
        orientation: DockOrientation = .bottom,
        truncated: Int = 0,
        screen: CGRect? = nil,
        anchor: CGRect? = nil
    ) -> DockStackLayoutInput {
        DockStackLayoutInput(
            textWidths: Array(repeating: 120, count: count),
            requested: requested,
            anchor: anchor ?? self.anchor,
            orientation: orientation,
            screen: screen ?? self.screen,
            truncated: truncated,
            metrics: metrics
        )
    }

    @Test("A small folder set to Automatic comes up as a fan, a large one as a grid")
    func automaticResolution() {
        #expect(DockStackGeometry.layout(input(6)).mode == .fan)
        #expect(DockStackGeometry.layout(input(metrics.fanAutomaticLimit)).mode == .fan)
        #expect(DockStackGeometry.layout(input(metrics.fanAutomaticLimit + 1)).mode == .grid)
    }

    @Test("An explicit choice in the Dock's own settings is honoured whatever the count")
    func explicitModes() {
        #expect(DockStackGeometry.layout(input(40, requested: .fan)).mode == .fan)
        #expect(DockStackGeometry.layout(input(3, requested: .grid)).mode == .grid)
        #expect(DockStackGeometry.layout(input(3, requested: .list)).mode == .list)
    }

    @Test("Every mode puts the balloon on the screen it was given")
    func staysOnScreen() {
        for mode in [FolderStackViewMode.fan, .grid, .list] {
            let layout = DockStackGeometry.layout(input(30, requested: mode))
            let frame = layout.balloon.panelFrame
            #expect(frame.minX >= screen.minX)
            #expect(frame.maxX <= screen.maxX)
            #expect(frame.maxY <= screen.maxY)
            #expect(frame.minY >= screen.minY)
        }
    }

    @Test("The balloon sits above a bottom bar and beside a side one")
    func placement() {
        let bottom = DockStackGeometry.layout(input(5, requested: .list))
        #expect(bottom.balloon.panelFrame.minY >= anchor.maxY)

        let sideAnchor = CGRect(x: 8, y: 500, width: 48, height: 48)
        let left = DockStackGeometry.layout(
            input(5, requested: .list, orientation: .left, anchor: sideAnchor)
        )
        #expect(left.balloon.panelFrame.minX >= sideAnchor.maxX)
    }

    @Test("A list too tall for the screen ends in a row that says what is missing")
    func overflowRow() {
        let short = CGRect(x: 0, y: 0, width: 1512, height: 260)
        let layout = DockStackGeometry.layout(input(60, requested: .list, screen: short))

        #expect(layout.hasOverflowRow)
        #expect(layout.visibleCount < 60)
        #expect(layout.overflowCount == 60 - layout.visibleCount)
        #expect(layout.items.count == layout.visibleCount + 1)
        #expect(layout.overflowIndex == layout.visibleCount)
    }

    @Test("Entries the reader itself dropped are counted in the same overflow row")
    func truncationIsReported() {
        let layout = DockStackGeometry.layout(input(4, requested: .list, truncated: 30))

        #expect(layout.hasOverflowRow)
        #expect(layout.overflowCount >= 30)
    }

    @Test("A folder that fits has no overflow row at all")
    func noOverflowWhenItFits() {
        let layout = DockStackGeometry.layout(input(8, requested: .list))

        #expect(!layout.hasOverflowRow)
        #expect(layout.visibleCount == 8)
        #expect(layout.items.count == 8)
    }

    @Test("A list runs top to bottom and a fan runs up from the tile")
    func rowOrder() {
        let list = DockStackGeometry.layout(input(5, requested: .list))
        let listTops = list.items.map(\.frame.minY)
        #expect(listTops == listTops.sorted())

        let fan = DockStackGeometry.layout(input(5, requested: .fan))
        let fanTops = fan.items.map(\.frame.minY)
        #expect(fanTops == fanTops.sorted(by: >))
    }

    @Test("The fan's icons follow an arc that starts at the tile and leans away from it")
    func fanArc() {
        let layout = DockStackGeometry.layout(input(6, requested: .fan))
        let offsets = layout.items.map(\.iconFrame.minX)

        #expect(offsets.first == metrics.horizontalPadding)
        #expect(offsets == offsets.sorted())
        #expect((offsets.last ?? 0) - metrics.horizontalPadding <= metrics.fanArcDepth)
    }

    @Test("A side dock gets a straight column, because a sideways arc has nowhere to go")
    func noArcOnASideDock() {
        let layout = DockStackGeometry.layout(
            input(6, requested: .fan, orientation: .right, anchor: CGRect(x: 1456, y: 500, width: 48, height: 48))
        )
        let offsets = Set(layout.items.map(\.iconFrame.minX))

        #expect(offsets.count == 1)
    }

    @Test("A grid is as square as it can be and never wider than its column limit")
    func gridShape() {
        let layout = DockStackGeometry.layout(input(9, requested: .grid))
        let firstRow = layout.items.filter { $0.frame.minY == layout.items[0].frame.minY }

        #expect(firstRow.count == 3)
        #expect(firstRow.count <= metrics.gridMaximumColumns)

        let wide = DockStackGeometry.layout(input(64, requested: .grid))
        let wideRow = wide.items.filter { $0.frame.minY == wide.items[0].frame.minY }
        #expect(wideRow.count <= metrics.gridMaximumColumns)
    }

    @Test("A grid labels under its icons, a list and a fan beside them")
    func labelPlacement() {
        let grid = DockStackGeometry.layout(input(4, requested: .grid))
        #expect(grid.items[0].alignment == .centre)
        #expect(grid.items[0].textFrame.minY > grid.items[0].iconFrame.minY)

        let list = DockStackGeometry.layout(input(4, requested: .list))
        #expect(list.items[0].alignment == .leading)
        #expect(list.items[0].textFrame.minX > list.items[0].iconFrame.maxX)
    }

    @Test("An empty folder still gets a balloon, for the row that says so")
    func emptyFolder() {
        let layout = DockStackGeometry.layout(input(1, requested: .list))

        #expect(layout.items.count == 1)
        #expect(layout.balloon.panelFrame.width >= metrics.minimumWidth)
    }
}
