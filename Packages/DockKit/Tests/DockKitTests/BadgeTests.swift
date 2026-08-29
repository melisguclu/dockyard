import CoreGraphics
import DockKit
import Foundation
import Testing

@Suite("Badges are the Dock's own disc, on the icon's top corner")
struct BadgeTests {
    private let bounds = CGRect(x: 20, y: 10, width: 62, height: 62)

    @Test("A badge is a circle proportional to the icon")
    func circleByDefault() {
        let frame = BadgeGeometry.frame(in: bounds)

        #expect(frame.width == frame.height)
        #expect(frame.height == 62 * BadgeGeometry.diameterRatio)
    }

    @Test("A wider image widens the capsule and keeps its height")
    func widerImageWidensTheCapsule() {
        let circle = BadgeGeometry.frame(in: bounds)
        let capsule = BadgeGeometry.frame(in: bounds, aspect: 1.5)

        #expect(capsule.height == circle.height)
        #expect(capsule.width == circle.height * 1.5)
        #expect(capsule.midX == circle.midX)
        #expect(capsule.midY == circle.midY)
    }

    @Test("An aspect narrower than a circle is ignored rather than squeezing the disc")
    func narrowAspectIsClamped() {
        #expect(BadgeGeometry.frame(in: bounds, aspect: 0.5) == BadgeGeometry.frame(in: bounds))
    }

    @Test("The disc sits on the icon's top-right corner, inside the tile")
    func sitsOnTheCorner() {
        let frame = BadgeGeometry.frame(in: bounds)

        #expect(frame.midX > bounds.midX)
        #expect(frame.midY > bounds.midY)
        #expect(frame.maxX <= bounds.maxX + 1)
        #expect(frame.maxY <= bounds.maxY + 1)
    }

    @Test("A tiny icon still gets a legible badge")
    func minimumDiameter() {
        let frame = BadgeGeometry.frame(in: CGRect(x: 0, y: 0, width: 16, height: 16))

        #expect(frame.height == BadgeGeometry.minimumDiameter)
    }

    @MainActor
    @Test("The renderer draws once per text and size, and refuses degenerate ones")
    func rendererCaches() {
        let renderer = BadgeRenderer()

        let first = renderer.badge(text: "12", pixelDiameter: 24)
        let again = renderer.badge(text: "12", pixelDiameter: 24)
        let other = renderer.badge(text: "3", pixelDiameter: 24)

        #expect(first != nil)
        #expect(first === again)
        #expect(other !== first)
        #expect(renderer.badge(text: "", pixelDiameter: 24) == nil)
        #expect(renderer.badge(text: "1", pixelDiameter: 0) == nil)
    }

    @MainActor
    @Test("One and two digits stay a circle, and longer text grows into a capsule")
    func widthFollowsTheText() {
        let renderer = BadgeRenderer()

        let one = renderer.badge(text: "1", pixelDiameter: 24)
        let two = renderer.badge(text: "91", pixelDiameter: 24)
        let four = renderer.badge(text: "1234", pixelDiameter: 24)

        #expect(one?.height == 24)
        #expect(one?.width == 24)
        #expect(two?.width == 24)
        #expect((four?.width ?? 0) > 24)
        #expect(four?.height == 24)
    }

    @MainActor
    @Test("A badge past the character ceiling is cut rather than drawn forever")
    func textIsClamped() {
        let renderer = BadgeRenderer()
        let clamped = renderer.badge(text: String(repeating: "8", count: 20), pixelDiameter: 24)
        let ceiling = renderer.badge(
            text: String(repeating: "8", count: BadgeGeometry.maximumCharacters),
            pixelDiameter: 24
        )

        #expect(clamped?.width == ceiling?.width)
    }
}
