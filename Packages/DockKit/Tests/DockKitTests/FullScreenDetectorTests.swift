import CoreGraphics
import DockCore
import DockKit
import Foundation
import Testing

@Suite("Full-screen windows suppress the bar on their own display")
struct FullScreenDetectorTests {
    private func display(_ identifier: CGDirectDisplayID, frame: CGRect) -> DisplayInfo {
        DisplayInfo(
            identity: DisplayIdentity(
                vendorNumber: 1,
                modelNumber: identifier,
                serialNumber: identifier,
                isBuiltIn: identifier == 1,
                ordinalFallback: 0
            ),
            displayID: identifier,
            frame: frame,
            visibleFrame: frame.insetBy(dx: 0, dy: 12),
            backingScaleFactor: 2,
            isMirrorSecondary: false
        )
    }

    private var builtIn: DisplayInfo { display(1, frame: Displays.builtIn) }
    private var external: DisplayInfo { display(2, frame: Displays.leftOfBuiltIn) }

    @Test("A window filling the display frame covers it")
    func exactCover() {
        let window = OnScreenWindow(layer: 0, bounds: Displays.builtIn)
        #expect(FullScreenDetector.covers(window, builtIn))
    }

    @Test("A maximized window that leaves the menu bar does not")
    func maximizedWindow() {
        let window = OnScreenWindow(layer: 0, bounds: builtIn.visibleFrame)
        #expect(!FullScreenDetector.covers(window, builtIn))
    }

    @Test("Coverage tolerates a point of rounding on every edge")
    func tolerance() {
        let inset = FullScreenDetector.coverageTolerance
        let snug = OnScreenWindow(layer: 0, bounds: Displays.builtIn.insetBy(dx: inset, dy: inset))
        #expect(FullScreenDetector.covers(snug, builtIn))
        let loose = OnScreenWindow(
            layer: 0,
            bounds: Displays.builtIn.insetBy(dx: inset + 1, dy: inset + 1)
        )
        #expect(!FullScreenDetector.covers(loose, builtIn))
    }

    @Test("The desktop below the normal layer is not a full-screen window")
    func desktopLayer() {
        let desktop = OnScreenWindow(layer: -2_147_483_603, bounds: Displays.builtIn)
        #expect(!FullScreenDetector.covers(desktop, builtIn))
    }

    @Test("Only the display the window is on is covered")
    func perDisplay() {
        let window = OnScreenWindow(layer: 0, bounds: Displays.leftOfBuiltIn)
        let covered = FullScreenDetector.coveredDisplays(
            windows: [window],
            displays: [builtIn, external]
        )
        #expect(covered == [external.displayID])
    }

    @Test("A display with a negative origin is matched on its own frame")
    func negativeOrigin() {
        let window = OnScreenWindow(layer: 0, bounds: Displays.leftOfBuiltIn)
        #expect(FullScreenDetector.covers(window, external))
        #expect(!FullScreenDetector.covers(window, builtIn))
    }

    @Test("Two full-screen windows cover two displays")
    func twoDisplays() {
        let windows = [
            OnScreenWindow(layer: 0, bounds: Displays.builtIn),
            OnScreenWindow(layer: 0, bounds: Displays.leftOfBuiltIn),
        ]
        let covered = FullScreenDetector.coveredDisplays(
            windows: windows,
            displays: [builtIn, external]
        )
        #expect(covered == [builtIn.displayID, external.displayID])
    }

    @Test("No windows means nothing is covered")
    func noWindows() {
        #expect(FullScreenDetector.coveredDisplays(windows: [], displays: [builtIn]).isEmpty)
    }
}
