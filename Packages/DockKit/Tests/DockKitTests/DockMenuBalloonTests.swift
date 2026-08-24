import CoreGraphics
import DockCore
import DockKit
import Foundation
import Testing

@Suite("Dock menu balloon")
struct DockMenuBalloonTests {
    private let metrics = DockMenuMetrics.current
    private let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private let content = CGSize(width: 160, height: 120)

    private func balloon(
        anchor: CGRect,
        orientation: DockOrientation,
        contentSize: CGSize? = nil
    ) -> DockMenuBalloon {
        DockMenuLayout.balloon(
            contentSize: contentSize ?? content,
            anchor: anchor,
            orientation: orientation,
            screen: screen,
            metrics: metrics
        )
    }

    @Test("A bottom dock puts the tail under the body, pointing at the tile")
    func bottomTail() {
        let anchor = CGRect(x: 700, y: 8, width: 48, height: 48)
        let result = balloon(anchor: anchor, orientation: .bottom)

        #expect(result.panelFrame.height == content.height + metrics.tailLength)
        #expect(result.panelFrame.minY == anchor.maxY + metrics.tileGap)
        #expect(result.bodyRect.minY == metrics.tailLength)
        #expect(abs(result.panelFrame.minX + result.tailAlong - anchor.midX) < 0.001)
    }

    @Test("A side dock puts the tail on the edge facing the tile")
    func sideTail() {
        let anchor = CGRect(x: 8, y: 500, width: 48, height: 48)
        let left = balloon(anchor: anchor, orientation: .left)
        #expect(left.panelFrame.width == content.width + metrics.tailLength)
        #expect(left.panelFrame.minX == anchor.maxX + metrics.tileGap)
        #expect(left.bodyRect.minX == metrics.tailLength)

        let mirrored = CGRect(x: screen.maxX - 56, y: 500, width: 48, height: 48)
        let right = balloon(anchor: mirrored, orientation: .right)
        #expect(right.panelFrame.maxX == mirrored.minX - metrics.tileGap)
        #expect(right.bodyRect.minX == 0)
    }

    @Test("A balloon at either end of the screen keeps the tail clear of the corners")
    func clampedTail() {
        for x in [CGFloat(0), screen.maxX - 48] {
            let result = balloon(
                anchor: CGRect(x: x, y: 8, width: 48, height: 48),
                orientation: .bottom
            )
            #expect(result.panelFrame.minX >= screen.minX + metrics.screenInset)
            #expect(result.panelFrame.maxX <= screen.maxX - metrics.screenInset)
            #expect(result.tailAlong >= metrics.cornerRadius)
            #expect(result.tailAlong <= result.panelFrame.width - metrics.cornerRadius)
        }
    }

    @Test("The outline covers the panel and reaches the tail tip in every orientation")
    func outlineBounds() {
        let cases: [(DockOrientation, CGRect)] = [
            (.bottom, CGRect(x: 700, y: 8, width: 48, height: 48)),
            (.left, CGRect(x: 8, y: 500, width: 48, height: 48)),
            (.right, CGRect(x: screen.maxX - 56, y: 500, width: 48, height: 48)),
        ]

        for (orientation, anchor) in cases {
            let result = balloon(anchor: anchor, orientation: orientation)
            let box = DockMenuLayout.path(for: result, metrics: metrics).boundingBox
            let panel = CGRect(origin: .zero, size: result.panelFrame.size)
            #expect(abs(box.width - panel.width) < 0.5)
            #expect(abs(box.height - panel.height) < 0.5)
            #expect(abs(box.minX) < 0.5)
            #expect(abs(box.minY) < 0.5)
        }
    }

    @Test("A narrow menu is widened to the minimum width")
    func minimumWidth() {
        let result = balloon(
            anchor: CGRect(x: 700, y: 8, width: 48, height: 48),
            orientation: .bottom,
            contentSize: CGSize(width: 40, height: 60)
        )
        #expect(result.panelFrame.width == metrics.minimumWidth)
    }
}
