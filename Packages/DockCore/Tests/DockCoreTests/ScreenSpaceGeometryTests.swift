import DockCore
import Foundation
import Testing

@Suite("Reserved screen space only ever shrinks a window, and only off the bar")
struct ScreenSpaceGeometryTests {
    private let display = CGRect(x: 0, y: 0, width: 1512, height: 982)
    private let thickness: CGFloat = 70

    private func area(_ edge: DockOrientation) -> ReservedArea {
        ReservedArea(display: display, thickness: thickness, edge: edge)
    }

    @Test("The usable rectangle is the display less the strip, on the strip's own edge")
    func usable() {
        #expect(area(.bottom).usable == CGRect(x: 0, y: 0, width: 1512, height: 912))
        #expect(area(.left).usable == CGRect(x: 70, y: 0, width: 1442, height: 982))
        #expect(area(.right).usable == CGRect(x: 0, y: 0, width: 1442, height: 982))
    }

    @Test("A window already clear of the bar is left exactly as it is")
    func untouched() {
        let window = CGRect(x: 100, y: 100, width: 800, height: 600)
        #expect(ScreenSpaceGeometry.adjusted(window: window, avoiding: area(.bottom)) == nil)
    }

    @Test("A window over a bottom bar loses height, and its top edge does not move")
    func bottomBar() {
        let window = CGRect(x: 0, y: 25, width: 1512, height: 957)
        let adjusted = ScreenSpaceGeometry.adjusted(window: window, avoiding: area(.bottom))

        #expect(adjusted == CGRect(x: 0, y: 25, width: 1512, height: 887))
        #expect(adjusted?.minY == window.minY)
    }

    @Test("A window over a left bar moves off it and keeps its right edge")
    func leftBar() {
        let window = CGRect(x: 0, y: 40, width: 1000, height: 700)
        let adjusted = ScreenSpaceGeometry.adjusted(window: window, avoiding: area(.left))

        #expect(adjusted == CGRect(x: 70, y: 40, width: 930, height: 700))
        #expect(adjusted?.maxX == window.maxX)
    }

    @Test("A window over a right bar loses width and keeps its left edge")
    func rightBar() {
        let window = CGRect(x: 600, y: 40, width: 912, height: 700)
        let adjusted = ScreenSpaceGeometry.adjusted(window: window, avoiding: area(.right))

        #expect(adjusted == CGRect(x: 600, y: 40, width: 842, height: 700))
    }

    @Test("A window that would be shrunk below a usable size is left alone instead")
    func minimumSize() {
        let window = CGRect(x: 0, y: 900, width: 900, height: 82)
        #expect(ScreenSpaceGeometry.adjusted(window: window, avoiding: area(.bottom)) == nil)
    }

    @Test("A one-point overlap is inside the tolerance and costs no resize")
    func tolerance() {
        let window = CGRect(x: 0, y: 100, width: 900, height: 813)
        #expect(ScreenSpaceGeometry.adjusted(window: window, avoiding: area(.bottom)) == nil)
    }

    @Test("A window is judged against the display holding its centre")
    func displaySelection() {
        let second = CGRect(x: 1512, y: 0, width: 2560, height: 1440)
        let areas = [
            ReservedArea(display: display, thickness: thickness, edge: .bottom),
            ReservedArea(display: second, thickness: thickness, edge: .bottom),
        ]
        let window = CGRect(x: 2000, y: 1000, width: 1200, height: 440)
        let adjusted = ScreenSpaceGeometry.adjusted(window: window, avoiding: areas)

        #expect(adjusted == CGRect(x: 2000, y: 1000, width: 1200, height: 370))
    }

    @Test("A window on a display with no bar of its own is never touched")
    func displayWithoutBar() {
        let areas = [ReservedArea(display: display, thickness: thickness, edge: .bottom)]
        let window = CGRect(x: 2000, y: 1000, width: 1200, height: 440)

        #expect(ScreenSpaceGeometry.adjusted(window: window, avoiding: areas) == nil)
    }
}
