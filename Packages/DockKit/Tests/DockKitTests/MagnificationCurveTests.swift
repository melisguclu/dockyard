import CoreGraphics
import DockKit
import Foundation
import Testing

@Suite("Magnification curve")
struct MagnificationCurveTests {
    private let window: CGFloat = 3
    private let maximum: CGFloat = 128.0 / 48.0

    @Test("The cursor position gets the maximum scale")
    func peakAtCursor() {
        let scale = MagnificationCurve.scale(
            distanceInTiles: 0,
            window: window,
            maximumScale: maximum
        )
        #expect(abs(scale - maximum) < 0.0001)
    }

    @Test("Scale returns to unity at the window edge and beyond")
    func unityAtEdge() {
        for distance in [window, window + 0.5, window * 10] {
            let scale = MagnificationCurve.scale(
                distanceInTiles: distance,
                window: window,
                maximumScale: maximum
            )
            #expect(abs(scale - 1) < 0.0001)
        }
    }

    @Test("Scale falls off monotonically")
    func monotonicFalloff() {
        var previous = maximum + 1
        for step in 0...30 {
            let distance = CGFloat(step) / 10
            let scale = MagnificationCurve.scale(
                distanceInTiles: distance,
                window: window,
                maximumScale: maximum
            )
            #expect(scale <= previous + 0.0001)
            #expect(scale >= 1)
            previous = scale
        }
    }

    @Test("The curve is symmetric around the cursor")
    func symmetry() {
        for step in 1...30 {
            let distance = CGFloat(step) / 10
            let left = MagnificationCurve.scale(
                distanceInTiles: -distance,
                window: window,
                maximumScale: maximum
            )
            let right = MagnificationCurve.scale(
                distanceInTiles: distance,
                window: window,
                maximumScale: maximum
            )
            #expect(abs(left - right) < 0.000001)
        }
    }

    @Test("A disabled or degenerate configuration never scales")
    func degenerateConfigurations() {
        #expect(MagnificationCurve.scale(distanceInTiles: 0, window: 0, maximumScale: 3) == 1)
        #expect(MagnificationCurve.scale(distanceInTiles: 0, window: 3, maximumScale: 1) == 1)
        #expect(MagnificationCurve.scale(distanceInTiles: 0, window: 3, maximumScale: 0.5) == 1)
    }

    @Test("Maximum scale is the ratio of large size to tile size, never below one")
    func maximumScaleDerivation() {
        #expect(MagnificationCurve.maximumScale(tileSize: 48, largeSize: 128) == 128.0 / 48.0)
        #expect(MagnificationCurve.maximumScale(tileSize: 64, largeSize: 32) == 1)
        #expect(MagnificationCurve.maximumScale(tileSize: 0, largeSize: 128) == 1)
    }
}
