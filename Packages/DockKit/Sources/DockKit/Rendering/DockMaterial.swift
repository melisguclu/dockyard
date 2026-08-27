import AppKit
import Foundation

public struct DockAccessibilityAppearance: Sendable, Equatable {
    public let reduceTransparency: Bool
    public let increaseContrast: Bool

    public init(reduceTransparency: Bool = false, increaseContrast: Bool = false) {
        self.reduceTransparency = reduceTransparency
        self.increaseContrast = increaseContrast
    }

    public static let standard = DockAccessibilityAppearance()

    @MainActor
    public static var current: DockAccessibilityAppearance {
        let workspace = NSWorkspace.shared
        return DockAccessibilityAppearance(
            reduceTransparency: workspace.accessibilityDisplayShouldReduceTransparency,
            increaseContrast: workspace.accessibilityDisplayShouldIncreaseContrast
        )
    }
}

@MainActor
public enum DockMaterial {
    public static let material: NSVisualEffectView.Material = .hudWindow

    public static func configure(_ view: NSVisualEffectView) {
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        view.isEmphasized = false
        view.wantsLayer = true
        view.layer?.masksToBounds = true
    }

    public static let borderColor: CGColor = NSColor.white.withAlphaComponent(0.12).cgColor

    public static let glassBorderColor: CGColor = NSColor.white.withAlphaComponent(0.22).cgColor

    public static func borderColor(
        style: DockBackdrop.Style,
        accessibility: DockAccessibilityAppearance,
        appearance: NSAppearance
    ) -> CGColor {
        if accessibility.increaseContrast {
            return resolve(NSColor.labelColor, for: appearance)
        }
        if accessibility.reduceTransparency {
            return resolve(NSColor.separatorColor, for: appearance)
        }
        return style == .glass ? glassBorderColor : borderColor
    }

    public static let reducedTransparencyDimming = NSColor(name: "DockReducedTransparencyDimming") { appearance in
        isDark(appearance)
            ? NSColor(white: 0, alpha: 0.35)
            : NSColor(white: 87 / 255, alpha: 0.46)
    }

    public static func reducedTransparencyFill(for appearance: NSAppearance) -> CGColor {
        resolve(reducedTransparencyDimming, for: appearance)
    }

    public static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    public static func resolve(_ color: NSColor, for appearance: NSAppearance) -> CGColor {
        var resolved = color.cgColor
        appearance.performAsCurrentDrawingAppearance {
            resolved = color.cgColor
        }
        return resolved
    }

    public static func shadow(on layer: CALayer, radius: CGFloat) {
        layer.shadowColor = NSColor.black.cgColor
        layer.shadowOpacity = 0.28
        layer.shadowRadius = radius
        layer.shadowOffset = CGSize(width: 0, height: -1)
    }
}
