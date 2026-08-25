import CoreGraphics
import DockCore
import DockKit
import Foundation
import Testing

@Suite("Dock tile label")
struct DockTileLabelTests {
    private let metrics = DockTileLabelMetrics.current
    private let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)

    private func balloon(
        anchor: CGRect,
        orientation: DockOrientation,
        width: CGFloat = 149
    ) -> DockMenuBalloon {
        DockTileLabelLayout.balloon(
            width: width,
            anchor: anchor,
            orientation: orientation,
            screen: screen,
            metrics: metrics
        )
    }

    @Test("The capsule pads the measured text by one inset on each side")
    func width() {
        #expect(DockTileLabelLayout.width(textWidth: 122.22, metrics: metrics) == 123 + 2 * metrics.textInset)
        #expect(DockTileLabelLayout.width(textWidth: 0, metrics: metrics) == 2 * metrics.textInset)
    }

    @Test("A title too long for the capsule stops at the maximum width")
    func clampedWidth() {
        #expect(DockTileLabelLayout.width(textWidth: 2000, metrics: metrics) == metrics.maximumWidth)
    }

    @Test("A bottom dock hangs the tail under the body, pointing at the tile")
    func bottomPlacement() {
        let anchor = CGRect(x: 700, y: 12, width: 54, height: 54)
        let result = balloon(anchor: anchor, orientation: .bottom)

        #expect(result.panelFrame.minY == anchor.maxY + metrics.balloon.tileGap)
        #expect(result.panelFrame.height == metrics.height + metrics.balloon.tailLength)
        #expect(result.bodyRect.height == metrics.height)
        #expect(result.bodyRect.minY == metrics.balloon.tailLength)
        #expect(abs(result.panelFrame.minX + result.tailAlong - anchor.midX) < 0.001)
    }

    @Test("A side dock puts the tail on the edge facing the tile")
    func sidePlacement() {
        let anchor = CGRect(x: 6, y: 500, width: 54, height: 54)
        let left = balloon(anchor: anchor, orientation: .left)
        #expect(left.panelFrame.minX == anchor.maxX + metrics.balloon.tileGap)
        #expect(left.bodyRect.minX == metrics.balloon.tailLength)
        #expect(abs(left.panelFrame.minY + left.tailAlong - anchor.midY) < 0.001)

        let mirrored = CGRect(x: screen.maxX - 60, y: 500, width: 54, height: 54)
        let right = balloon(anchor: mirrored, orientation: .right)
        #expect(right.panelFrame.maxX == mirrored.minX - metrics.balloon.tileGap)
        #expect(right.bodyRect.minX == 0)
    }

    @Test("A label at either end of the screen stays on screen, tail clear of the corners")
    func clampedPlacement() {
        for x in [CGFloat(0), screen.maxX - 54] {
            let result = balloon(
                anchor: CGRect(x: x, y: 12, width: 54, height: 54),
                orientation: .bottom,
                width: 341
            )
            #expect(result.panelFrame.minX >= screen.minX + metrics.balloon.screenInset)
            #expect(result.panelFrame.maxX <= screen.maxX - metrics.balloon.screenInset)
            #expect(result.tailAlong >= metrics.balloon.cornerRadius)
            #expect(result.tailAlong <= result.panelFrame.width - metrics.balloon.cornerRadius)
        }
    }

    @Test("The body is a capsule and the outline reaches the tail tip")
    func outline() {
        let result = balloon(
            anchor: CGRect(x: 700, y: 12, width: 54, height: 54),
            orientation: .bottom
        )
        let box = DockMenuLayout.path(for: result, metrics: metrics.balloon).boundingBox
        #expect(abs(box.width - result.panelFrame.width) < 0.5)
        #expect(abs(box.height - result.panelFrame.height) < 0.5)
        #expect(metrics.balloon.cornerRadius == metrics.height / 2)
    }
}
