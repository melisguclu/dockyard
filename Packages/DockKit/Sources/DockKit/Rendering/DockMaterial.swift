import AppKit
import Foundation

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

    public static func shadow(on layer: CALayer, radius: CGFloat) {
        layer.shadowColor = NSColor.black.cgColor
        layer.shadowOpacity = 0.28
        layer.shadowRadius = radius
        layer.shadowOffset = CGSize(width: 0, height: -1)
    }
}
