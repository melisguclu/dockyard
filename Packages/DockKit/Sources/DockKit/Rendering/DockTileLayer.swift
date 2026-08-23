import AppKit
import DockCore
import Foundation
import QuartzCore

@MainActor
public final class DockTileLayer {
    public let identifier: DockTileID
    public let container = CALayer()

    private let iconLayer = CALayer()
    private let indicatorLayer = CALayer()
    private let separatorLayer = CALayer()
    private let highlightLayer = CALayer()

    private var kind: DockTile.Kind
    private var isRunning = false
    private var isHidden = false
    private var showsIndicator = false

    public init(tile: DockTile) {
        identifier = tile.id
        kind = tile.kind

        container.masksToBounds = false
        container.contentsScale = 1

        highlightLayer.backgroundColor = NSColor.white.withAlphaComponent(0.16).cgColor
        highlightLayer.cornerRadius = 6
        highlightLayer.opacity = 0
        container.addSublayer(highlightLayer)

        iconLayer.contentsGravity = .resizeAspect
        iconLayer.minificationFilter = .trilinear
        iconLayer.magnificationFilter = .trilinear
        container.addSublayer(iconLayer)

        indicatorLayer.contentsGravity = .resizeAspect
        indicatorLayer.opacity = 0
        container.addSublayer(indicatorLayer)

        separatorLayer.backgroundColor = NSColor.white.withAlphaComponent(0.2).cgColor
        separatorLayer.opacity = 0
        container.addSublayer(separatorLayer)
    }

    public func update(with tile: DockTile, showsIndicator: Bool) {
        kind = tile.kind
        isRunning = tile.isRunning
        isHidden = tile.isHidden
        self.showsIndicator = showsIndicator

        switch tile.kind {
        case .separator:
            separatorLayer.opacity = 1
            iconLayer.opacity = 0
        case .spacer:
            separatorLayer.opacity = 0
            iconLayer.opacity = 0
        default:
            separatorLayer.opacity = 0
            iconLayer.opacity = tile.isHidden ? 0.55 : 1
        }

        indicatorLayer.opacity = (showsIndicator && tile.isRunning) ? 1 : 0
    }

    public func setIcon(_ image: CGImage?, scale: CGFloat) {
        iconLayer.contents = image
        iconLayer.contentsScale = max(scale, 1)
    }

    public func setIndicator(_ image: CGImage?) {
        indicatorLayer.contents = image
    }

    public func setHighlighted(_ highlighted: Bool) {
        highlightLayer.opacity = highlighted ? 1 : 0
    }

    public func apply(
        frame: CGRect,
        indicatorDiameter: CGFloat,
        indicatorInset: CGFloat,
        orientation: DockOrientation
    ) {
        container.frame = frame
        let bounds = CGRect(origin: .zero, size: frame.size)

        iconLayer.frame = bounds
        highlightLayer.frame = bounds.insetBy(dx: -2, dy: -2)
        highlightLayer.cornerRadius = min(bounds.width, bounds.height) * 0.2

        switch kind {
        case .separator:
            separatorLayer.frame =
                orientation.isVertical
                ? CGRect(x: bounds.midX - 0.5, y: bounds.minY, width: 1, height: bounds.height)
                : CGRect(x: bounds.midX - 0.5, y: bounds.minY, width: 1, height: bounds.height)
        default:
            separatorLayer.frame = .zero
        }

        let indicatorFrame: CGRect
        switch orientation {
        case .bottom:
            indicatorFrame = CGRect(
                x: bounds.midX - indicatorDiameter / 2,
                y: -indicatorInset - indicatorDiameter,
                width: indicatorDiameter,
                height: indicatorDiameter
            )
        case .left:
            indicatorFrame = CGRect(
                x: -indicatorInset - indicatorDiameter,
                y: bounds.midY - indicatorDiameter / 2,
                width: indicatorDiameter,
                height: indicatorDiameter
            )
        case .right:
            indicatorFrame = CGRect(
                x: bounds.maxX + indicatorInset,
                y: bounds.midY - indicatorDiameter / 2,
                width: indicatorDiameter,
                height: indicatorDiameter
            )
        }
        indicatorLayer.frame = indicatorFrame
    }
}
