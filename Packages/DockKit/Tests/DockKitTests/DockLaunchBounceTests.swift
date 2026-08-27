import DockCore
import DockKit
import Foundation
import Testing

@Suite("A launching application bounces out of the bar")
struct DockLaunchBounceTests {
    private let metrics = DockMetrics.tahoe

    private func appearance(
        orientation: DockOrientation = .bottom,
        launchAnimation: Bool = true,
        magnification: Bool = false
    ) -> DockAppearance {
        DockAppearance(
            tileSize: 48,
            largeSize: 96,
            magnificationEnabled: magnification,
            orientation: orientation,
            launchAnimation: launchAnimation
        )
    }

    @Test("The bounce leaves the bar along the axis the dock is not on")
    func axes() throws {
        let bottom = try #require(DockLaunchBounce(appearance: appearance(orientation: .bottom)))
        let left = try #require(DockLaunchBounce(appearance: appearance(orientation: .left)))
        let right = try #require(DockLaunchBounce(appearance: appearance(orientation: .right)))

        #expect(bottom.axis == .vertical)
        #expect(bottom.axis.keyPath == "position.y")
        #expect(left.axis == .horizontal)
        #expect(right.axis == .horizontal)
        #expect(bottom.displacement > 0)
        #expect(left.displacement > 0)
        #expect(right.displacement < 0)
        #expect(left.travel == right.travel)
    }

    @Test("Travel is a fraction of the tile and scales with it")
    func travel() {
        let small = appearance().withTileSize(32)
        let large = appearance().withTileSize(64)

        #expect(DockLaunchBounce.travel(small) == (32 * DockLaunchBounce.travelRatio).rounded())
        #expect(DockLaunchBounce.travel(large) > DockLaunchBounce.travel(small))
        #expect(DockLaunchBounce.travel(large) < 64)
    }

    @Test("With launchanim off there is no bounce at all")
    func disabled() {
        let off = appearance(launchAnimation: false)

        #expect(DockLaunchBounce(appearance: off) == nil)
        #expect(DockLaunchBounce.travel(off) == 0)
    }

    @Test("The keyframes rise, fall, and rest inside one period")
    func keyframes() throws {
        let bounce = try #require(DockLaunchBounce(appearance: appearance()))
        let times = bounce.keyTimes

        #expect(bounce.values.count == times.count)
        #expect(bounce.values == [0, bounce.displacement, 0, 0])
        #expect(times.first == 0)
        #expect(times.last == 1)
        #expect(zip(times, times.dropFirst()).allSatisfy { $0 < $1 })
        #expect(DockLaunchBounce.period > DockLaunchBounce.riseDuration + DockLaunchBounce.fallDuration)
    }

    @Test("A bouncing panel is exactly tall enough to hold the icon at its peak")
    func panelThickness() {
        let plain = appearance()
        let resting = DockGeometry.panelThickness(plain, metrics, extent: .resting)
        let bouncing = DockGeometry.panelThickness(plain, metrics, extent: .bouncing)
        let margin = DockGeometry.screenEdgeMargin(plain, metrics)
        let padding = DockGeometry.barPadding(plain, metrics)

        #expect(bouncing > resting)
        #expect(bouncing == margin + padding + plain.tileSize + DockLaunchBounce.travel(plain))
    }

    @Test("Bouncing while magnified clears the magnified icon, not the resting one")
    func magnifiedThickness() {
        let magnified = appearance(magnification: true)
        let both = DockGeometry.panelThickness(magnified, metrics, extent: [.magnified, .bouncing])
        let margin = DockGeometry.screenEdgeMargin(magnified, metrics)
        let padding = DockGeometry.barPadding(magnified, metrics)

        #expect(both >= DockGeometry.panelThickness(magnified, metrics, extent: .magnified))
        #expect(both == margin + padding + magnified.effectiveLargeSize + DockLaunchBounce.travel(magnified))
    }

    @Test("With launchanim off the bouncing extent costs no pixels")
    func disabledThickness() {
        let off = appearance(launchAnimation: false)

        #expect(
            DockGeometry.panelThickness(off, metrics, extent: .bouncing)
                == DockGeometry.panelThickness(off, metrics, extent: .resting)
        )
    }

    @Test("A bounce is perpendicular to the bar, so it never lengthens the panel")
    func panelLength() {
        let plain = appearance()
        let tiles = TileFactory.applications(6)

        #expect(
            DockGeometry.panelLength(tiles: tiles, appearance: plain, metrics: metrics, extent: .bouncing)
                == DockGeometry.panelLength(tiles: tiles, appearance: plain, metrics: metrics, extent: .resting)
        )
    }
}
