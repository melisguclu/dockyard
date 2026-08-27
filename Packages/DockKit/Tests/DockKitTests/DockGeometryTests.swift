import CoreGraphics
import DockCore
import DockKit
import Foundation
import Testing

@Suite("Dock geometry")
struct DockGeometryTests {
    private let metrics = DockMetrics.sonoma
    private let appearance = DockAppearance(tileSize: 48, largeSize: 128, magnificationEnabled: true)
    private let plain = DockAppearance(tileSize: 48, largeSize: 128, magnificationEnabled: false)

    private func input(
        tiles: [DockTile],
        appearance: DockAppearance,
        panelSize: CGSize = CGSize(width: 1512, height: 200),
        cursor: CGPoint? = nil,
        magnificationAmount: CGFloat = 1
    ) -> DockLayoutInput {
        DockLayoutInput(
            tiles: tiles,
            appearance: appearance,
            metrics: metrics,
            panelSize: panelSize,
            cursor: cursor,
            magnificationAmount: magnificationAmount
        )
    }

    @Test("Bar thickness is the tile plus symmetric padding")
    func barThickness() {
        let padding = DockGeometry.barPadding(plain, metrics)
        #expect(DockGeometry.barThickness(plain, metrics) == plain.tileSize + 2 * padding)
    }

    @Test("Bar length accounts for every tile, every gap, and both paddings")
    func barLength() {
        let tiles = TileFactory.applications(5)
        let gap = DockGeometry.spacing(plain, metrics)
        let padding = DockGeometry.barPadding(plain, metrics)
        let expected = 5 * plain.tileSize + 4 * gap + 2 * padding

        #expect(DockGeometry.barLength(tiles: tiles, appearance: plain, metrics: metrics) == expected)
        #expect(DockGeometry.barLength(tiles: [], appearance: plain, metrics: metrics) == 0)
    }

    @Test("A separator and a small spacer are narrower than a tile")
    func specialTileLengths() {
        let tile = DockGeometry.baseLength(
            of: TileFactory.application("A"),
            appearance: plain,
            metrics: metrics
        )
        let separator = DockGeometry.baseLength(
            of: TileFactory.separator,
            appearance: plain,
            metrics: metrics
        )
        let small = DockGeometry.baseLength(
            of: TileFactory.spacer(.small),
            appearance: plain,
            metrics: metrics
        )
        let full = DockGeometry.baseLength(
            of: TileFactory.spacer(.full),
            appearance: plain,
            metrics: metrics
        )

        #expect(separator < tile)
        #expect(small < tile)
        #expect(full == tile)
    }

    @Test("The panel sits on the bottom edge of its own display, centred on the bar")
    func panelFrameBottom() {
        let tiles = TileFactory.applications(5)
        for screen in [Displays.builtIn, Displays.leftOfBuiltIn, Displays.aboveBuiltIn] {
            let frame = DockGeometry.panelFrame(
                screenFrame: screen,
                tiles: tiles,
                appearance: plain,
                metrics: metrics
            )
            #expect(frame.minY == screen.minY)
            #expect(abs(frame.midX - screen.midX) < 0.001)
            #expect(frame.width == DockGeometry.barLength(tiles: tiles, appearance: plain, metrics: metrics))
            #expect(frame.height == DockGeometry.panelThickness(plain, metrics))
        }
    }

    @Test("Without magnification the panel is nothing but the bar")
    func panelHugsTheBarAtRest() {
        let tiles = TileFactory.applications(8) + [TileFactory.separator, TileFactory.trash]
        let bar = DockGeometry.barLength(tiles: tiles, appearance: appearance, metrics: metrics)
        let margin = DockGeometry.screenEdgeMargin(appearance, metrics)

        let resting = DockGeometry.panelFrame(
            screenFrame: Displays.builtIn,
            tiles: tiles,
            appearance: appearance,
            metrics: metrics,
            extent: .resting
        )
        #expect(resting.width == bar)
        #expect(resting.height == margin + DockGeometry.barThickness(appearance, metrics))
        #expect(resting.width < Displays.builtIn.width)

        let layout = DockGeometry.layout(
            input(tiles: tiles, appearance: appearance, panelSize: resting.size)
        )
        #expect(abs(layout.barRect.width - bar) < 0.001)
        #expect(layout.barRect.minX == 0)
        #expect(layout.barRect.maxY == resting.height)
    }

    @Test("A resting and a magnified panel put the bar in the same place on screen")
    func extentsAgreeOnTheBarPosition() {
        let tiles = TileFactory.applications(8) + [TileFactory.separator, TileFactory.trash]
        for orientation in [DockOrientation.bottom, .left, .right] {
            let candidate = DockAppearance(
                tileSize: 48,
                largeSize: 128,
                magnificationEnabled: true,
                orientation: orientation
            )
            var origins: [CGPoint] = []
            for extent in [DockPanelExtent.resting, .magnified] {
                let frame = DockGeometry.panelFrame(
                    screenFrame: Displays.leftOfBuiltIn,
                    tiles: tiles,
                    appearance: candidate,
                    metrics: metrics,
                    extent: extent
                )
                let layout = DockGeometry.layout(
                    input(tiles: tiles, appearance: candidate, panelSize: frame.size)
                )
                origins.append(
                    CGPoint(x: frame.minX + layout.barRect.minX, y: frame.minY + layout.barRect.minY)
                )
            }
            #expect(abs(origins[0].x - origins[1].x) < 0.001)
            #expect(abs(origins[0].y - origins[1].y) < 0.001)
        }
    }

    @Test("A magnified panel holds the longest bar magnification can produce")
    func panelHoldsTheMagnifiedBar() {
        let tiles = TileFactory.applications(12) + [TileFactory.separator, TileFactory.trash]
        let panelSize = CGSize(width: 4000, height: 200)
        let stage = DockGeometry.panelLength(
            tiles: tiles,
            appearance: appearance,
            metrics: metrics,
            extent: .magnified
        )
        let bar = DockGeometry.barLength(tiles: tiles, appearance: appearance, metrics: metrics)

        var widest: CGFloat = 0
        var leftmost: CGFloat = .greatestFiniteMagnitude
        var rightmost: CGFloat = 0
        for step in 0...400 {
            let x = (panelSize.width - bar) / 2 + bar * CGFloat(step) / 400
            let layout = DockGeometry.layout(
                input(tiles: tiles, appearance: appearance, panelSize: panelSize, cursor: CGPoint(x: x, y: 20))
            )
            widest = max(widest, layout.barRect.width)
            leftmost = min(leftmost, layout.barRect.minX)
            rightmost = max(rightmost, layout.barRect.maxX)
        }

        #expect(widest > bar)
        #expect(stage >= widest)
        #expect(stage >= rightmost - leftmost)
    }

    @Test("Magnification headroom is zero when magnification is off")
    func headroomWithoutMagnification() {
        let tiles = TileFactory.applications(5)
        #expect(
            DockGeometry.magnificationHeadroom(tiles: tiles, appearance: plain, metrics: metrics) == 0
        )
        #expect(
            DockGeometry.panelLength(tiles: tiles, appearance: plain, metrics: metrics, extent: .magnified)
                == DockGeometry.barLength(tiles: tiles, appearance: plain, metrics: metrics)
        )
    }

    @Test("A short dock never reserves more headroom than its tiles can grow")
    func headroomIsBoundedByTheTileCount() {
        let tiles = TileFactory.applications(2)
        let maximum = MagnificationCurve.maximumScale(
            tileSize: appearance.tileSize,
            largeSize: appearance.effectiveLargeSize
        )
        let ceiling = 2 * appearance.tileSize * (maximum - 1)
        #expect(
            DockGeometry.magnificationHeadroom(tiles: tiles, appearance: appearance, metrics: metrics)
                <= ceiling
        )
    }

    @Test("A panel never outgrows its display")
    func panelIsCappedByTheDisplay() {
        let tiles = TileFactory.applications(60)
        let frame = DockGeometry.panelFrame(
            screenFrame: Displays.builtIn,
            tiles: tiles,
            appearance: appearance,
            metrics: metrics,
            extent: .magnified
        )
        #expect(frame.width == Displays.builtIn.width)
        #expect(frame.minX == Displays.builtIn.minX)
    }

    @Test("The panel is tall enough for a fully magnified tile")
    func panelAccommodatesMagnification() {
        let thickness = DockGeometry.panelThickness(appearance, metrics)
        let margin = DockGeometry.screenEdgeMargin(appearance, metrics)
        let padding = DockGeometry.barPadding(appearance, metrics)

        #expect(thickness >= margin + padding + appearance.largeSize)
        #expect(thickness > DockGeometry.panelThickness(plain, metrics))
    }

    @Test("A left or right dock hugs the correct edge")
    func panelFrameVertical() {
        let tiles = TileFactory.applications(5)
        let vertical = DockAppearance(orientation: .left)
        let bar = DockGeometry.barLength(tiles: tiles, appearance: vertical, metrics: metrics)

        let left = DockGeometry.panelFrame(
            screenFrame: Displays.leftOfBuiltIn,
            tiles: tiles,
            appearance: vertical,
            metrics: metrics
        )
        #expect(left.minX == Displays.leftOfBuiltIn.minX)
        #expect(left.height == bar)
        #expect(abs(left.midY - Displays.leftOfBuiltIn.midY) < 0.001)

        let right = DockGeometry.panelFrame(
            screenFrame: Displays.leftOfBuiltIn,
            tiles: tiles,
            appearance: DockAppearance(orientation: .right),
            metrics: metrics
        )
        #expect(right.maxX == Displays.leftOfBuiltIn.maxX)
        #expect(right.height == bar)
        #expect(abs(right.midY - Displays.leftOfBuiltIn.midY) < 0.001)
    }

    @Test("At rest the tiles are contiguous, centred, and sit on the bar baseline")
    func restingLayout() {
        let tiles = TileFactory.applications(6) + [TileFactory.separator, TileFactory.trash]
        let layout = DockGeometry.layout(input(tiles: tiles, appearance: plain))
        let gap = DockGeometry.spacing(plain, metrics)
        let padding = DockGeometry.barPadding(plain, metrics)
        let margin = DockGeometry.screenEdgeMargin(plain, metrics)

        #expect(layout.tileFrames.count == tiles.count)
        #expect(abs(layout.barRect.midX - 1512 / 2) < 0.51)
        #expect(layout.barRect.minY == margin)
        #expect(layout.barRect.height == DockGeometry.barThickness(plain, metrics))
        #expect(layout.tileScales.allSatisfy { $0 == 1 })

        for frame in layout.tileFrames {
            #expect(frame.minY == margin + padding)
            #expect(frame.minX >= layout.barRect.minX + padding - 0.01)
            #expect(frame.maxX <= layout.barRect.maxX - padding + 0.01)
        }

        for index in 1..<layout.tileFrames.count {
            let previous = layout.tileFrames[index - 1]
            let current = layout.tileFrames[index]
            #expect(abs(current.minX - (previous.maxX + gap)) < 0.01)
        }
    }

    @Test("The hovered tile is the largest and its neighbours fall off")
    func magnifiedScales() {
        let tiles = TileFactory.applications(9)
        let resting = DockGeometry.layout(input(tiles: tiles, appearance: appearance))
        let hovered = 4
        let cursor = CGPoint(x: resting.tileFrames[hovered].midX, y: 20)
        let layout = DockGeometry.layout(
            input(tiles: tiles, appearance: appearance, cursor: cursor)
        )

        let maximum = MagnificationCurve.maximumScale(tileSize: 48, largeSize: 128)
        #expect(abs(layout.tileScales[hovered] - maximum) < 0.02)

        for index in (hovered + 1)..<tiles.count {
            #expect(layout.tileScales[index] <= layout.tileScales[index - 1] + 0.0001)
        }
        for index in stride(from: hovered - 1, through: 0, by: -1) {
            #expect(layout.tileScales[index] <= layout.tileScales[index + 1] + 0.0001)
        }
        #expect(layout.tileFrames[hovered].height > layout.tileFrames[0].height)
    }

    @Test("Magnification grows the bar by exactly the extra tile width")
    func magnifiedBarLength() {
        let tiles = TileFactory.applications(9)
        let resting = DockGeometry.layout(input(tiles: tiles, appearance: appearance))
        let cursor = CGPoint(x: resting.tileFrames[4].midX, y: 20)
        let layout = DockGeometry.layout(
            input(tiles: tiles, appearance: appearance, cursor: cursor)
        )

        let gap = DockGeometry.spacing(appearance, metrics)
        let padding = DockGeometry.barPadding(appearance, metrics)
        let widths = layout.tileFrames.map(\.width).reduce(0, +)
        let expected = widths + gap * CGFloat(tiles.count - 1) + 2 * padding

        #expect(abs(layout.barRect.width - expected) < 0.01)
        #expect(layout.barRect.width > resting.barRect.width)
        #expect(layout.barRect.height == resting.barRect.height)
    }

    @Test("The tile under the cursor stays under the cursor")
    func cursorStaysAnchored() {
        let tiles = TileFactory.applications(9)
        let resting = DockGeometry.layout(input(tiles: tiles, appearance: appearance))

        for index in 2..<7 {
            let cursor = CGPoint(x: resting.tileFrames[index].midX, y: 20)
            let layout = DockGeometry.layout(
                input(tiles: tiles, appearance: appearance, cursor: cursor)
            )
            let frame = layout.tileFrames[index]
            #expect(frame.minX <= cursor.x + 0.01)
            #expect(frame.maxX >= cursor.x - 0.01)
        }
    }

    @Test("Moving inside the bar padding never nudges the layout")
    func paddingDoesNotDragTheBar() {
        let tiles = TileFactory.applications(9)
        let padding = DockGeometry.barPadding(appearance, metrics)
        let resting = DockGeometry.layout(input(tiles: tiles, appearance: appearance))

        func layout(cursorX: CGFloat) -> DockLayout {
            DockGeometry.layout(
                input(tiles: tiles, appearance: appearance, cursor: CGPoint(x: cursorX, y: 20))
            )
        }

        let leadingEdge = resting.tileFrames[0].minX
        let trailingEdge = resting.tileFrames[tiles.count - 1].maxX

        for offset in stride(from: CGFloat(0), through: padding, by: 1) {
            let leading = layout(cursorX: leadingEdge - offset)
            let trailing = layout(cursorX: trailingEdge + offset)
            #expect(abs(leading.barRect.minX - layout(cursorX: leadingEdge).barRect.minX) < 0.01)
            #expect(abs(trailing.barRect.maxX - layout(cursorX: trailingEdge).barRect.maxX) < 0.01)
            #expect(leading.tileFrames[0].minX == layout(cursorX: leadingEdge).tileFrames[0].minX)
            #expect(
                trailing.tileFrames[tiles.count - 1].maxX
                    == layout(cursorX: trailingEdge).tileFrames[tiles.count - 1].maxX
            )
        }
    }

    @Test("Magnified tiles never leave the panel at either edge")
    func magnifiedLayoutIsClamped() {
        let tiles = TileFactory.applications(9)
        let panel = CGSize(width: 1512, height: 200)

        for cursorX in [CGFloat(0), 1, 200, 756, 1300, 1511, 1512] {
            let layout = DockGeometry.layout(
                input(
                    tiles: tiles,
                    appearance: appearance,
                    panelSize: panel,
                    cursor: CGPoint(x: cursorX, y: 20)
                )
            )
            #expect(layout.barRect.minX >= -0.01)
            #expect(layout.barRect.maxX <= panel.width + 0.01)
        }
    }

    @Test("A bar wider than the display is pinned to the leading edge")
    func overflowIsPinned() {
        let tiles = TileFactory.applications(60)
        let panel = CGSize(width: 900, height: 200)
        let layout = DockGeometry.layout(
            input(
                tiles: tiles,
                appearance: appearance,
                panelSize: panel,
                cursor: CGPoint(x: 450, y: 20)
            )
        )
        #expect(layout.barRect.minX >= -0.01)
    }

    @Test("Separators and spacers never magnify")
    func nonTilesDoNotScale() {
        let tiles = [
            TileFactory.application("A"),
            TileFactory.separator,
            TileFactory.spacer(.full),
            TileFactory.application("B")
        ]
        let resting = DockGeometry.layout(input(tiles: tiles, appearance: appearance))
        let cursor = CGPoint(x: resting.tileFrames[1].midX, y: 20)
        let layout = DockGeometry.layout(
            input(tiles: tiles, appearance: appearance, cursor: cursor)
        )

        #expect(layout.tileScales[1] == 1)
        #expect(layout.tileScales[2] == 1)
        #expect(layout.tileFrames[1].height == appearance.tileSize)
    }

    @Test("Magnification is ignored when the Dock has it switched off")
    func magnificationRespectsPreference() {
        let tiles = TileFactory.applications(5)
        let layout = DockGeometry.layout(
            input(tiles: tiles, appearance: plain, cursor: CGPoint(x: 700, y: 20))
        )
        #expect(layout.tileScales.allSatisfy { $0 == 1 })
    }

    @Test("A ramp amount of zero reproduces the resting layout exactly")
    func zeroRampAmountMatchesRest() {
        let tiles = TileFactory.applications(7)
        let cursor = CGPoint(x: 700, y: 20)
        let resting = DockGeometry.layout(input(tiles: tiles, appearance: appearance))
        let ramped = DockGeometry.layout(
            input(tiles: tiles, appearance: appearance, cursor: cursor, magnificationAmount: 0)
        )
        #expect(ramped.tileFrames == resting.tileFrames)
        #expect(ramped.barRect == resting.barRect)
        #expect(ramped.tileScales.allSatisfy { $0 == 1 })
    }

    @Test("The ramp amount interpolates monotonically towards full magnification")
    func rampAmountIsMonotonic() {
        let tiles = TileFactory.applications(7)
        let cursor = CGPoint(x: 700, y: 20)
        let peaks = stride(from: CGFloat(0), through: 1, by: 0.125).map { amount in
            DockGeometry.layout(
                input(tiles: tiles, appearance: appearance, cursor: cursor, magnificationAmount: amount)
            ).tileScales.max() ?? 0
        }

        for (previous, next) in zip(peaks, peaks.dropFirst()) {
            #expect(next > previous)
        }

        let full = DockGeometry.layout(input(tiles: tiles, appearance: appearance, cursor: cursor))
        #expect(peaks.last == full.tileScales.max())
    }

    @Test("A ramp amount outside the unit range is clamped rather than extrapolated")
    func rampAmountIsClamped() {
        let tiles = TileFactory.applications(5)
        let cursor = CGPoint(x: 700, y: 20)
        let full = DockGeometry.layout(input(tiles: tiles, appearance: appearance, cursor: cursor))
        let over = DockGeometry.layout(
            input(tiles: tiles, appearance: appearance, cursor: cursor, magnificationAmount: 4)
        )
        let under = DockGeometry.layout(
            input(tiles: tiles, appearance: appearance, cursor: cursor, magnificationAmount: -2)
        )
        #expect(over.tileFrames == full.tileFrames)
        #expect(under.tileScales.allSatisfy { $0 == 1 })
    }

    @Test("The macOS 26 magnification window matches the measured Dock")
    func measuredMagnificationWindow() {
        #expect(DockMetrics.tahoe.magnificationWindowTiles == 3.9)

        let real = DockMetrics.tahoe
        let candidate = DockAppearance(tileSize: 27, largeSize: 48, magnificationEnabled: true)
        let tiles = TileFactory.applications(40)
        let panel = CGSize(width: 2400, height: 200)

        func layout(cursorX: CGFloat?) -> DockLayout {
            DockGeometry.layout(
                DockLayoutInput(
                    tiles: tiles,
                    appearance: candidate,
                    metrics: real,
                    panelSize: panel,
                    cursor: cursorX.map { CGPoint(x: $0, y: 20) }
                )
            )
        }

        let cursorX = layout(cursorX: nil).tileFrames[20].midX
        let frames = layout(cursorX: cursorX).tileFrames

        var predicted: [(CGFloat, CGFloat)] = []
        for index in 0..<(frames.count - 1) {
            let pitch = frames[index + 1].midX - frames[index].midX
            let midpoint = (frames[index].midX + frames[index + 1].midX) / 2
            predicted.append((midpoint - cursorX, pitch))
        }

        func pitch(at distance: CGFloat) -> CGFloat {
            guard let after = predicted.firstIndex(where: { $0.0 >= distance }), after > 0 else {
                return predicted.last?.1 ?? 0
            }
            let (d0, p0) = predicted[after - 1]
            let (d1, p1) = predicted[after]
            return p0 + (p1 - p0) * (distance - d0) / (d1 - d0)
        }

        let measured: [(distance: CGFloat, pitch: CGFloat)] = [
            (-138.6, 30.17), (-115.2, 34.50), (-94.1, 39.12), (-64.8, 46.00),
            (-26.8, 48.50), (23.5, 47.94), (36.8, 48.12), (69.9, 42.45),
            (88.3, 39.58), (113.3, 33.96), (136.3, 30.67)
        ]

        for sample in measured {
            #expect(abs(pitch(at: sample.distance) - sample.pitch) < 3.0)
        }
    }

    @Test("A vertical dock stacks its tiles from the top down")
    func verticalStacking() {
        let vertical = DockAppearance(tileSize: 48, orientation: .left)
        let tiles = TileFactory.applications(4)
        let layout = DockGeometry.layout(
            input(
                tiles: tiles,
                appearance: vertical,
                panelSize: CGSize(width: 200, height: 1440)
            )
        )
        let margin = DockGeometry.screenEdgeMargin(vertical, metrics)
        let padding = DockGeometry.barPadding(vertical, metrics)

        for index in 1..<layout.tileFrames.count {
            #expect(layout.tileFrames[index].maxY < layout.tileFrames[index - 1].maxY)
        }
        #expect(layout.tileFrames.allSatisfy { $0.minX == margin + padding })
        #expect(layout.barRect.minX == margin)
        #expect(abs(layout.barRect.midY - 1440 / 2) < 0.51)
    }

    @Test("A measured edge margin positions the bar exactly like the real Dock")
    func measuredEdgeMargin() {
        let tiles = TileFactory.applications(5)
        let measured: CGFloat = 6
        let candidate = DockAppearance(tileSize: 27, largeSize: 48, magnificationEnabled: true)
        let thickness = DockGeometry.barThickness(candidate, metrics)

        let margin = DockGeometry.screenEdgeMargin(candidate, metrics, measuredEdgeMargin: measured)
        #expect(margin == measured)

        let layout = DockGeometry.layout(
            DockLayoutInput(
                tiles: tiles,
                appearance: candidate,
                metrics: metrics,
                panelSize: CGSize(width: 2560, height: 200),
                measuredEdgeMargin: measured
            )
        )
        #expect(layout.barRect.minY == measured)
        #expect(layout.barRect.maxY == measured + thickness)

        let frame = DockGeometry.panelFrame(
            screenFrame: Displays.builtIn,
            tiles: tiles,
            appearance: candidate,
            metrics: metrics,
            measuredEdgeMargin: measured
        )
        #expect(frame.height >= measured + thickness)
    }

    @Test("The measured margin holds the bar down whatever the tile size is")
    func measuredMarginIgnoresTheTileSize() {
        let tiles = TileFactory.applications(5)
        let measured: CGFloat = 6

        for size in [CGFloat(16), 27, 48, 128] {
            let layout = DockGeometry.layout(
                DockLayoutInput(
                    tiles: tiles,
                    appearance: DockAppearance(tileSize: size),
                    metrics: metrics,
                    panelSize: CGSize(width: 2560, height: 400),
                    measuredEdgeMargin: measured
                )
            )
            #expect(layout.barRect.minY == measured)
        }
    }

    @Test("An absurd edge margin never pushes the bar below the screen edge")
    func degenerateEdgeMargin() {
        let margin = DockGeometry.screenEdgeMargin(plain, metrics, measuredEdgeMargin: -20)
        #expect(margin == DockGeometry.minimumScreenEdgeMargin)
    }

    @Test("An empty dock produces an empty layout")
    func emptyLayout() {
        #expect(DockGeometry.layout(input(tiles: [], appearance: plain)) == DockLayout.empty)
    }

    @Test("Hit testing maps a point back to its tile")
    func hitTesting() {
        let tiles = TileFactory.applications(5)
        let layout = DockGeometry.layout(input(tiles: tiles, appearance: plain))

        for index in tiles.indices {
            let centre = CGPoint(x: layout.tileFrames[index].midX, y: layout.tileFrames[index].midY)
            #expect(DockGeometry.hitIndex(in: layout, at: centre) == index)
        }
        #expect(DockGeometry.hitIndex(in: layout, at: CGPoint(x: 5, y: 5)) == nil)
    }

    @Test("A dock that fits the display keeps the size the Dock asked for")
    func fittedSizeLeavesSmallDocksAlone() {
        let tiles = TileFactory.applications(8) + [TileFactory.trash]
        let fitted = DockGeometry.fittedTileSize(
            tiles: tiles,
            appearance: plain,
            metrics: metrics,
            available: Displays.builtIn.width
        )
        #expect(fitted == plain.tileSize)
    }

    @Test("A dock too long for the display shrinks until the bar fits")
    func fittedSizeShrinksAnOverlongDock() {
        let tiles = TileFactory.applications(60)
        let requested = DockAppearance(tileSize: 128)
        let available = Displays.builtIn.width
        let fitted = DockGeometry.fittedTileSize(
            tiles: tiles,
            appearance: requested,
            metrics: metrics,
            available: available
        )

        #expect(fitted < requested.tileSize)
        #expect(
            DockGeometry.fittedLength(
                tiles: tiles,
                appearance: requested.withTileSize(fitted),
                metrics: metrics
            ) <= available
        )
        #expect(
            DockGeometry.fittedLength(
                tiles: tiles,
                appearance: requested.withTileSize(fitted + 1),
                metrics: metrics
            ) > available
        )
    }

    @Test("The fitted size never falls below the smallest tile the Dock allows")
    func fittedSizeStopsAtTheSmallestTile() {
        let tiles = TileFactory.applications(400)
        let fitted = DockGeometry.fittedTileSize(
            tiles: tiles,
            appearance: DockAppearance(tileSize: 128),
            metrics: metrics,
            available: Displays.builtIn.width
        )
        #expect(fitted == DockAppearance.tileSizeRange.lowerBound)
    }

    @Test("The fitted size matches the cap the real Dock settles on")
    func fittedSizeMatchesTheMeasuredDock() {
        let tahoe = DockMetrics.tahoe
        let width = CGFloat(2560)
        let requested = DockAppearance(tileSize: 128)

        let twentySix =
            TileFactory.applications(24) + [TileFactory.separator, TileFactory.trash]
        let thirtyFour =
            TileFactory.applications(32) + [TileFactory.separator, TileFactory.trash]

        let wide = DockGeometry.fittedTileSize(
            tiles: twentySix,
            appearance: requested,
            metrics: tahoe,
            available: width
        )
        let crowded = DockGeometry.fittedTileSize(
            tiles: thirtyFour,
            appearance: requested,
            metrics: tahoe,
            available: width
        )

        #expect(abs(wide - 89.7) <= 2)
        #expect(abs(crowded - 68.6) <= 2)
    }

    @Test("The running indicator fits inside the bar padding")
    func indicatorFitsInPadding() {
        for size in [CGFloat(16), 32, 48, 64, 128] {
            let candidate = DockAppearance(tileSize: size)
            let padding = DockGeometry.barPadding(candidate, metrics)
            let diameter = DockGeometry.indicatorDiameter(candidate, metrics)
            let inset = DockGeometry.indicatorInset(candidate, metrics)

            #expect(diameter >= DockGeometry.minimumIndicatorDiameter)
            #expect(diameter <= size / 4)
            #expect(inset >= 0)
            #expect(inset + diameter <= padding)
        }
    }
}
