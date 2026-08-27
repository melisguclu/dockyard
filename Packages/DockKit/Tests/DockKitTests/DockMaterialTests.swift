import AppKit
import DockKit
import Foundation
import Testing

@MainActor
@Suite("The bar answers Reduce Transparency and Increase Contrast")
struct DockMaterialTests {
    private func appearance(_ name: NSAppearance.Name) throws -> NSAppearance {
        try #require(NSAppearance(named: name))
    }

    @Test("Without Increase Contrast the hairline stays the measured one")
    func measuredBorder() throws {
        let dark = try appearance(.darkAqua)
        #expect(
            DockMaterial.borderColor(style: .glass, accessibility: .standard, appearance: dark)
                == DockMaterial.glassBorderColor
        )
        #expect(
            DockMaterial.borderColor(style: .blur, accessibility: .standard, appearance: dark)
                == DockMaterial.borderColor
        )
    }

    @Test("Increase Contrast draws an outline far stronger than the measured hairline")
    func contrastBorder() throws {
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let contrasted = DockMaterial.borderColor(
                style: .glass,
                accessibility: DockAccessibilityAppearance(increaseContrast: true),
                appearance: try appearance(name)
            )
            #expect(contrasted != DockMaterial.glassBorderColor)
            #expect(contrasted.alpha > DockMaterial.glassBorderColor.alpha)
        }
    }

    @Test("Under Reduce Transparency the hairline becomes the system's own separator")
    func reducedBorder() throws {
        let light = DockMaterial.borderColor(
            style: .glass,
            accessibility: DockAccessibilityAppearance(reduceTransparency: true),
            appearance: try appearance(.aqua)
        )
        let dark = DockMaterial.borderColor(
            style: .glass,
            accessibility: DockAccessibilityAppearance(reduceTransparency: true),
            appearance: try appearance(.darkAqua)
        )
        #expect(light != DockMaterial.glassBorderColor)
        #expect(light != dark)
    }

    @Test("The dimming wash is measured per appearance and never covers the material")
    func reducedTransparencyFill() throws {
        let light = DockMaterial.reducedTransparencyFill(for: try appearance(.aqua))
        let dark = DockMaterial.reducedTransparencyFill(for: try appearance(.darkAqua))

        #expect(light != dark)
        #expect(light.alpha < 1)
        #expect(dark.alpha < 1)
        #expect((light.components?.first ?? 0) > (dark.components?.first ?? 1))
    }

    @Test("Reduce Transparency and Increase Contrast are independent")
    func flags() {
        let value = DockAccessibilityAppearance(reduceTransparency: true)
        #expect(value.reduceTransparency)
        #expect(!value.increaseContrast)
        #expect(value != .standard)
    }
}
