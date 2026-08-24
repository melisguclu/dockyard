import AppKit
import DockCore
import Foundation
import QuartzCore

@MainActor
final class DockMenuBackdrop {
    let view = NSView()

    private let effect = NSVisualEffectView()
    private let mask = CAShapeLayer()
    private let outline = DockMenuOutlineView()

    init() {
        view.wantsLayer = true
        view.layer?.masksToBounds = false

        effect.material = .menu
        effect.blendingMode = .behindWindow
        effect.state = .active
        effect.isEmphasized = false
        effect.wantsLayer = true
        effect.layer?.mask = mask
        view.addSubview(effect)

        outline.shapeLayer.fillColor = NSColor.clear.cgColor
        outline.shapeLayer.strokeColor = DockMaterial.glassBorderColor
        outline.shapeLayer.lineWidth = DockMenuMetrics.current.borderWidth
        view.addSubview(outline, positioned: .above, relativeTo: effect)
    }

    func apply(balloon: DockMenuBalloon, metrics: DockMenuMetrics) {
        let bounds = CGRect(origin: .zero, size: balloon.panelFrame.size)
        let path = DockMenuLayout.path(for: balloon, metrics: metrics)

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        view.frame = bounds
        effect.frame = bounds
        mask.frame = bounds
        mask.path = path

        outline.frame = bounds
        outline.shapeLayer.frame = bounds
        outline.shapeLayer.path = path

        CATransaction.commit()
    }
}

final class DockMenuOutlineView: NSView {
    var shapeLayer: CAShapeLayer {
        layer as? CAShapeLayer ?? CAShapeLayer()
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func makeBackingLayer() -> CALayer { CAShapeLayer() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
