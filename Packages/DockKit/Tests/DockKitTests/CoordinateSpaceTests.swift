import CoreGraphics
import DockKit
import Foundation
import Testing

@Suite("Coordinate space conversion")
struct CoordinateSpaceTests {
    private let primaryHeight: CGFloat = 982

    @Test("A point converts and converts back")
    func pointRoundTrip() {
        let point = CGPoint(x: 120, y: 300)
        let converted = CoordinateSpace.cgToCocoa(point, primaryHeight: primaryHeight)
        #expect(converted.y == primaryHeight - point.y)
        #expect(CoordinateSpace.cocoaToCG(converted, primaryHeight: primaryHeight) == point)
    }

    @Test("A rect converts and converts back")
    func rectRoundTrip() {
        let rect = CGRect(x: 10, y: 20, width: 300, height: 60)
        let cocoa = CoordinateSpace.cgToCocoa(rect, primaryHeight: primaryHeight)
        #expect(cocoa.origin.x == rect.origin.x)
        #expect(cocoa.size == rect.size)
        #expect(cocoa.origin.y == primaryHeight - rect.maxY)
        #expect(CoordinateSpace.cocoaToCG(cocoa, primaryHeight: primaryHeight) == rect)
    }

    @Test("The bottom edge of the primary display maps to zero")
    func bottomEdge() {
        let dockRect = CGRect(x: 0, y: primaryHeight - 70, width: 1512, height: 70)
        let cocoa = CoordinateSpace.cgToCocoa(dockRect, primaryHeight: primaryHeight)
        #expect(cocoa.minY == 0)
    }

    @Test("Displays arranged left of and above the primary keep their signs")
    func negativeOrigins() {
        let left = CGRect(x: -2560, y: 0, width: 2560, height: 1440)
        let cocoaLeft = CoordinateSpace.cgToCocoa(left, primaryHeight: primaryHeight)
        #expect(cocoaLeft.minX == -2560)
        #expect(cocoaLeft.minY == primaryHeight - 1440)

        let above = CGRect(x: 0, y: -2880, width: 5120, height: 2880)
        let cocoaAbove = CoordinateSpace.cgToCocoa(above, primaryHeight: primaryHeight)
        #expect(cocoaAbove.minY == primaryHeight)
    }
}
