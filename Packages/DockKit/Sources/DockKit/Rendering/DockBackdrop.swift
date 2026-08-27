import AppKit
import Foundation

@MainActor
public final class DockBackdrop {
    public enum Style: Sendable, Equatable {
        case glass
        case blur
    }

    public static var preferredStyle: Style {
        if #available(macOS 26.0, *) {
            return .glass
        }
        return .blur
    }

    public let style: Style
    public let view: NSView
    public let borderLayer = CALayer()
    public let fillLayer = CALayer()

    private let maskLayer: CALayer?
    private var accessibility = DockAccessibilityAppearance.standard
    private var resolvedAppearance: NSAppearance.Name?

    public init(style: Style = DockBackdrop.preferredStyle) {
        if style == .glass, let glass = Self.makeGlassView() {
            self.style = .glass
            self.view = glass
            self.maskLayer = nil
        } else {
            let effect = NSVisualEffectView()
            DockMaterial.configure(effect)
            let mask = CALayer()
            mask.backgroundColor = NSColor.black.cgColor
            effect.layer?.mask = mask

            self.style = .blur
            self.view = effect
            self.maskLayer = mask
        }

        view.autoresizingMask = []
        borderLayer.backgroundColor = NSColor.clear.cgColor
        borderLayer.borderColor =
            self.style == .glass
            ? DockMaterial.glassBorderColor
            : DockMaterial.borderColor
        fillLayer.isHidden = true
    }

    public func setAccessibility(_ value: DockAccessibilityAppearance, appearance: NSAppearance) {
        guard value != accessibility || appearance.name != resolvedAppearance else { return }
        accessibility = value
        resolvedAppearance = appearance.name
        fillLayer.isHidden = !value.reduceTransparency
        fillLayer.backgroundColor = DockMaterial.reducedTransparencyFill(for: appearance)
        borderLayer.borderColor = DockMaterial.borderColor(
            style: style,
            accessibility: value,
            appearance: appearance
        )
    }

    public func apply(bounds: CGRect, barRect: CGRect, cornerRadius: CGFloat) {
        if let maskLayer {
            view.frame = bounds
            if view.layer?.mask !== maskLayer {
                view.layer?.mask = maskLayer
            }
            maskLayer.frame = barRect
            maskLayer.cornerRadius = cornerRadius
        } else {
            view.frame = barRect
            applyGlassCornerRadius(cornerRadius)
        }

        fillLayer.frame = barRect
        fillLayer.cornerRadius = cornerRadius
        borderLayer.frame = barRect
        borderLayer.cornerRadius = cornerRadius
    }

    private static func makeGlassView() -> NSView? {
        guard #available(macOS 26.0, *) else { return nil }
        let glass = NSGlassEffectView()
        glass.style = .clear
        glass.tintColor = nil
        return glass
    }

    private func applyGlassCornerRadius(_ radius: CGFloat) {
        guard #available(macOS 26.0, *), let glass = view as? NSGlassEffectView else { return }
        guard glass.cornerRadius != radius else { return }
        glass.cornerRadius = radius
    }
}
