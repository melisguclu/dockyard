import CoreGraphics
import DockCore
import DockKit
import Foundation
import Testing

@Suite("Dock auto-hide")
struct DockAutoHideTests {
    private let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)

    private func appearance(
        orientation: DockOrientation = .bottom,
        autoHide: Bool = true,
        delay: TimeInterval = 0.5,
        timeModifier: Double = 1
    ) -> DockAppearance {
        DockAppearance(
            orientation: orientation,
            autoHide: autoHide,
            autoHideDelay: delay,
            autoHideTimeModifier: timeModifier
        )
    }

    @Test("The hidden frame clears the bottom edge entirely")
    func hiddenFrameBottom() {
        let revealed = CGRect(x: 400, y: 0, width: 700, height: 90)
        let hidden = DockAutoHide.hiddenFrame(
            revealed: revealed,
            screenFrame: screen,
            orientation: .bottom
        )
        #expect(hidden.maxY == screen.minY)
        #expect(hidden.size == revealed.size)
        #expect(hidden.minX == revealed.minX)
    }

    @Test("The hidden frame clears the left and right edges entirely")
    func hiddenFrameVertical() {
        let left = CGRect(x: 0, y: 300, width: 90, height: 500)
        let hiddenLeft = DockAutoHide.hiddenFrame(
            revealed: left,
            screenFrame: screen,
            orientation: .left
        )
        #expect(hiddenLeft.maxX == screen.minX)
        #expect(hiddenLeft.minY == left.minY)

        let right = CGRect(x: screen.maxX - 90, y: 300, width: 90, height: 500)
        let hiddenRight = DockAutoHide.hiddenFrame(
            revealed: right,
            screenFrame: screen,
            orientation: .right
        )
        #expect(hiddenRight.minX == screen.maxX)
        #expect(hiddenRight.minY == right.minY)
    }

    @Test("The hidden frame is reachable from a display with a negative origin")
    func hiddenFrameNegativeOrigin() {
        let offset = CGRect(x: -1920, y: -300, width: 1920, height: 1080)
        let revealed = CGRect(x: -1400, y: -300, width: 700, height: 90)
        let hidden = DockAutoHide.hiddenFrame(
            revealed: revealed,
            screenFrame: offset,
            orientation: .bottom
        )
        #expect(hidden.maxY == offset.minY)
    }

    @Test("The trigger spans the whole edge it guards")
    func triggerFrames() {
        let bottom = DockAutoHide.triggerFrame(screenFrame: screen, orientation: .bottom)
        #expect(bottom.width == screen.width)
        #expect(bottom.height == DockAutoHide.triggerThickness)
        #expect(bottom.minY == screen.minY)

        let left = DockAutoHide.triggerFrame(screenFrame: screen, orientation: .left)
        #expect(left.height == screen.height)
        #expect(left.width == DockAutoHide.triggerThickness)
        #expect(left.minX == screen.minX)

        let right = DockAutoHide.triggerFrame(screenFrame: screen, orientation: .right)
        #expect(right.maxX == screen.maxX)
        #expect(right.width == DockAutoHide.triggerThickness)
    }

    @Test("The trigger stays inside a display smaller than its own thickness")
    func triggerFrameClamped() {
        let sliver = CGRect(x: 0, y: 0, width: 0.5, height: 0.5)
        let bottom = DockAutoHide.triggerFrame(screenFrame: sliver, orientation: .bottom)
        #expect(bottom.height == sliver.height)
        let left = DockAutoHide.triggerFrame(screenFrame: sliver, orientation: .left)
        #expect(left.width == sliver.width)
    }

    @Test("The reveal delay is the Dock's own, never negative")
    func revealDelay() {
        #expect(DockAutoHide.revealDelay(appearance(delay: 0.25)) == 0.25)
        #expect(DockAutoHide.revealDelay(appearance(delay: 0)) == 0)
    }

    @Test("The slide duration scales with autohide-time-modifier")
    func slideDuration() {
        #expect(DockAutoHide.slideDuration(appearance(timeModifier: 1)) == DockAutoHide.baseSlideDuration)
        #expect(
            DockAutoHide.slideDuration(appearance(timeModifier: 0.5))
                == DockAutoHide.baseSlideDuration / 2
        )
    }

    @Test("A near-zero time modifier still produces a finite slide")
    func slideDurationFloor() {
        let fastest = DockAutoHide.slideDuration(
            appearance(timeModifier: DockAppearance.autoHideTimeModifierRange.lowerBound)
        )
        #expect(fastest >= DockAutoHide.minimumSlideDuration)
    }

    @Test("Reveal states report what the panel and the trigger should be doing")
    func stateFlags() {
        #expect(DockRevealState.hidden.showsTrigger)
        #expect(!DockRevealState.revealed.showsTrigger)
        #expect(DockRevealState.revealing.isSliding)
        #expect(DockRevealState.hiding.isSliding)
        #expect(!DockRevealState.hidden.isSliding)
        #expect(DockRevealState.disabled.acceptsPointer)
        #expect(DockRevealState.revealed.acceptsPointer)
        #expect(!DockRevealState.hidden.acceptsPointer)
    }
}
