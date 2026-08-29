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
    private let badgeLayer = CALayer()
    private let highlightLayer = CALayer()
    private let pressLayer = CALayer()
    private let pressMask = CALayer()

    private var kind: DockTile.Kind
    private var badge: String?
    private var badgeAspect: CGFloat = 1
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

        pressMask.contentsGravity = .resizeAspect
        pressLayer.backgroundColor = NSColor.black.withAlphaComponent(Self.pressDimAlpha).cgColor
        pressLayer.opacity = 0
        pressLayer.mask = pressMask
        container.addSublayer(pressLayer)

        indicatorLayer.contentsGravity = .resizeAspect
        indicatorLayer.opacity = 0
        container.addSublayer(indicatorLayer)

        separatorLayer.backgroundColor = NSColor.white.withAlphaComponent(0.2).cgColor
        separatorLayer.opacity = 0
        container.addSublayer(separatorLayer)

        badgeLayer.contentsGravity = .resizeAspect
        badgeLayer.opacity = 0
        container.addSublayer(badgeLayer)
    }

    public func update(with tile: DockTile, showsIndicator: Bool) {
        kind = tile.kind
        badge = tile.badge
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
        badgeLayer.opacity = tile.badge == nil ? 0 : 1
    }

    public func setIcon(_ image: CGImage?, scale: CGFloat) {
        iconLayer.contents = image
        iconLayer.contentsScale = max(scale, 1)
        pressMask.contents = image
        pressMask.contentsScale = max(scale, 1)
    }

    public func setIndicator(_ image: CGImage?) {
        indicatorLayer.contents = image
    }

    public func setBadge(_ image: CGImage?, scale: CGFloat) {
        badgeLayer.contents = image
        badgeLayer.contentsScale = max(scale, 1)
        guard let image, image.height > 0 else {
            badgeAspect = 1
            return
        }
        badgeAspect = CGFloat(image.width) / CGFloat(image.height)
    }

    public func setHighlighted(_ highlighted: Bool) {
        highlightLayer.opacity = highlighted ? 1 : 0
    }

    public func setLaunching(_ bounce: DockLaunchBounce) {
        let start = iconLayer.convertTime(CACurrentMediaTime(), from: nil)
        for layer in [iconLayer, pressLayer] {
            let animation = Self.animation(for: bounce)
            animation.beginTime = start
            layer.add(animation, forKey: Self.bounceKey)
        }
    }

    @discardableResult
    public func finishLaunching() -> Double {
        [iconLayer, pressLayer].reduce(0) { max($0, Self.finish($1)) }
    }

    private static func finish(_ layer: CALayer) -> Double {
        guard
            let running = layer.animation(forKey: bounceKey) as? CAKeyframeAnimation,
            running.repeatCount.isInfinite,
            running.duration > 0,
            let finishing = running.copy() as? CAKeyframeAnimation
        else { return 0 }

        let elapsed = max(layer.convertTime(CACurrentMediaTime(), from: nil) - running.beginTime, 0)
        let cycles = (elapsed / running.duration).rounded(.down) + 1
        finishing.repeatCount = Float(cycles)
        layer.add(finishing, forKey: bounceKey)
        return cycles * running.duration - elapsed
    }

    private static func animation(for bounce: DockLaunchBounce) -> CAKeyframeAnimation {
        let animation = CAKeyframeAnimation(keyPath: bounce.axis.keyPath)
        animation.values = bounce.values.map { NSNumber(value: Double($0)) }
        animation.keyTimes = bounce.keyTimes.map { NSNumber(value: $0) }
        animation.timingFunctions = [
            CAMediaTimingFunction(name: .easeOut),
            CAMediaTimingFunction(name: .easeIn),
            CAMediaTimingFunction(name: .linear),
        ]
        animation.duration = DockLaunchBounce.period
        animation.repeatCount = .infinity
        animation.isAdditive = true
        return animation
    }

    public func setLifted(_ lifted: Bool) {
        container.zPosition = lifted ? 1 : 0
    }

    public func setPressed(_ pressed: Bool) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        pressLayer.opacity = pressed ? 1 : 0
        CATransaction.commit()
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
        pressLayer.frame = bounds
        pressMask.frame = bounds
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

        badgeLayer.frame =
            badge == nil ? .zero : BadgeGeometry.frame(in: bounds, aspect: badgeAspect)

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

    private static let bounceKey = "launch-bounce"
    private static let pressDimAlpha: CGFloat = 0.525
}
