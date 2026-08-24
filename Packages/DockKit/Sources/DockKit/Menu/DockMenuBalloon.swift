import CoreGraphics
import DockCore
import Foundation

public struct DockMenuMetrics: Sendable, Equatable {
    public var cornerRadius: CGFloat
    public var tailLength: CGFloat
    public var tailBaseHalfWidth: CGFloat
    public var tailBaseFillet: CGFloat
    public var tailApexDepth: CGFloat
    public var tailTipRadius: CGFloat
    public var tileGap: CGFloat
    public var screenInset: CGFloat
    public var rowHeight: CGFloat
    public var separatorHeight: CGFloat
    public var separatorInset: CGFloat
    public var leadingTextInset: CGFloat
    public var trailingTextInset: CGFloat
    public var verticalPadding: CGFloat
    public var highlightInset: CGFloat
    public var highlightRadius: CGFloat
    public var minimumWidth: CGFloat
    public var maximumWidth: CGFloat
    public var borderWidth: CGFloat

    public static let current = DockMenuMetrics(
        cornerRadius: 11,
        tailLength: 10.6,
        tailBaseHalfWidth: 9,
        tailBaseFillet: 6.5,
        tailApexDepth: 14,
        tailTipRadius: 4.2,
        tileGap: 6,
        screenInset: 8,
        rowHeight: 24,
        separatorHeight: 11,
        separatorInset: 17,
        leadingTextInset: 24,
        trailingTextInset: 20,
        verticalPadding: 6,
        highlightInset: 5,
        highlightRadius: 7,
        minimumWidth: 108,
        maximumWidth: 320,
        borderWidth: 1
    )

    var tailClearance: CGFloat {
        cornerRadius + tailBaseHalfWidth + tailBaseFillet
    }
}

public struct DockMenuBalloon: Equatable {
    public let panelFrame: CGRect
    public let bodyRect: CGRect
    public let tailAlong: CGFloat
    public let orientation: DockOrientation

    public var contentFrame: CGRect { bodyRect }
}

public enum DockMenuLayout {
    public static func balloon(
        contentSize: CGSize,
        anchor: CGRect,
        orientation: DockOrientation,
        screen: CGRect,
        metrics: DockMenuMetrics = .current
    ) -> DockMenuBalloon {
        let body = CGSize(
            width: max(contentSize.width, metrics.minimumWidth),
            height: contentSize.height
        )

        switch orientation {
        case .bottom:
            let size = CGSize(width: body.width, height: body.height + metrics.tailLength)
            let originX = clampedOrigin(
                preferred: anchor.midX - size.width / 2,
                length: size.width,
                lower: screen.minX,
                upper: screen.maxX,
                inset: metrics.screenInset
            )
            let originY = clampedOrigin(
                preferred: anchor.maxY + metrics.tileGap,
                length: size.height,
                lower: screen.minY,
                upper: screen.maxY,
                inset: metrics.screenInset
            )
            return DockMenuBalloon(
                panelFrame: CGRect(origin: CGPoint(x: originX, y: originY), size: size),
                bodyRect: CGRect(x: 0, y: metrics.tailLength, width: body.width, height: body.height),
                tailAlong: tailAlong(
                    preferred: anchor.midX - originX,
                    span: size.width,
                    metrics: metrics
                ),
                orientation: orientation
            )
        case .left, .right:
            let size = CGSize(width: body.width + metrics.tailLength, height: body.height)
            let preferredX =
                orientation == .left
                ? anchor.maxX + metrics.tileGap
                : anchor.minX - metrics.tileGap - size.width
            let originX = clampedOrigin(
                preferred: preferredX,
                length: size.width,
                lower: screen.minX,
                upper: screen.maxX,
                inset: metrics.screenInset
            )
            let originY = clampedOrigin(
                preferred: anchor.midY - size.height / 2,
                length: size.height,
                lower: screen.minY,
                upper: screen.maxY,
                inset: metrics.screenInset
            )
            return DockMenuBalloon(
                panelFrame: CGRect(origin: CGPoint(x: originX, y: originY), size: size),
                bodyRect: CGRect(
                    x: orientation == .left ? metrics.tailLength : 0,
                    y: 0,
                    width: body.width,
                    height: body.height
                ),
                tailAlong: tailAlong(
                    preferred: anchor.midY - originY,
                    span: size.height,
                    metrics: metrics
                ),
                orientation: orientation
            )
        }
    }

    public static func path(for balloon: DockMenuBalloon, metrics: DockMenuMetrics = .current) -> CGPath {
        let body = balloon.bodyRect.size
        switch balloon.orientation {
        case .bottom:
            return canonicalPath(bodySize: body, tailAlong: balloon.tailAlong, metrics: metrics)
        case .left:
            let canonical = canonicalPath(
                bodySize: CGSize(width: body.height, height: body.width),
                tailAlong: body.height - balloon.tailAlong,
                metrics: metrics
            )
            var transform = CGAffineTransform(rotationAngle: -.pi / 2)
                .concatenating(CGAffineTransform(translationX: 0, y: body.height))
            return canonical.copy(using: &transform) ?? canonical
        case .right:
            let canonical = canonicalPath(
                bodySize: CGSize(width: body.height, height: body.width),
                tailAlong: balloon.tailAlong,
                metrics: metrics
            )
            var transform = CGAffineTransform(rotationAngle: .pi / 2)
                .concatenating(CGAffineTransform(translationX: body.width + metrics.tailLength, y: 0))
            return canonical.copy(using: &transform) ?? canonical
        }
    }

    private static func canonicalPath(
        bodySize: CGSize,
        tailAlong: CGFloat,
        metrics: DockMenuMetrics
    ) -> CGPath {
        let path = CGMutablePath()
        let radius = min(metrics.cornerRadius, min(bodySize.width, bodySize.height) / 2)
        let edge = metrics.tailLength
        let top = edge + bodySize.height
        let right = bodySize.width
        let centre = tailAlong
        let half = metrics.tailBaseHalfWidth
        let fillet = metrics.tailBaseFillet
        let apex = CGPoint(x: centre, y: edge - metrics.tailApexDepth)
        let leftBase = CGPoint(x: centre - half, y: edge)
        let rightBase = CGPoint(x: centre + half, y: edge)

        path.move(to: CGPoint(x: radius, y: edge))
        path.addArc(tangent1End: leftBase, tangent2End: apex, radius: fillet)
        path.addArc(tangent1End: apex, tangent2End: rightBase, radius: metrics.tailTipRadius)
        path.addArc(
            tangent1End: rightBase,
            tangent2End: CGPoint(x: right - radius, y: edge),
            radius: fillet
        )
        path.addLine(to: CGPoint(x: right - radius, y: edge))
        path.addArc(
            tangent1End: CGPoint(x: right, y: edge),
            tangent2End: CGPoint(x: right, y: edge + radius),
            radius: radius
        )
        path.addLine(to: CGPoint(x: right, y: top - radius))
        path.addArc(
            tangent1End: CGPoint(x: right, y: top),
            tangent2End: CGPoint(x: right - radius, y: top),
            radius: radius
        )
        path.addLine(to: CGPoint(x: radius, y: top))
        path.addArc(
            tangent1End: CGPoint(x: 0, y: top),
            tangent2End: CGPoint(x: 0, y: top - radius),
            radius: radius
        )
        path.addLine(to: CGPoint(x: 0, y: edge + radius))
        path.addArc(
            tangent1End: CGPoint(x: 0, y: edge),
            tangent2End: CGPoint(x: radius, y: edge),
            radius: radius
        )
        path.closeSubpath()
        return path
    }

    public static func tailBounds(for balloon: DockMenuBalloon, metrics: DockMenuMetrics = .current) -> CGRect {
        let clearance = metrics.tailBaseHalfWidth + metrics.tailBaseFillet
        let size = balloon.panelFrame.size
        switch balloon.orientation {
        case .bottom:
            return CGRect(
                x: balloon.tailAlong - clearance,
                y: 0,
                width: 2 * clearance,
                height: metrics.tailLength
            )
        case .left:
            return CGRect(
                x: 0,
                y: balloon.tailAlong - clearance,
                width: metrics.tailLength,
                height: 2 * clearance
            )
        case .right:
            return CGRect(
                x: size.width - metrics.tailLength,
                y: balloon.tailAlong - clearance,
                width: metrics.tailLength,
                height: 2 * clearance
            )
        }
    }

    private static func clampedOrigin(
        preferred: CGFloat,
        length: CGFloat,
        lower: CGFloat,
        upper: CGFloat,
        inset: CGFloat
    ) -> CGFloat {
        let minimum = lower + inset
        let maximum = max(upper - inset - length, minimum)
        return min(max(preferred, minimum), maximum)
    }

    private static func tailAlong(preferred: CGFloat, span: CGFloat, metrics: DockMenuMetrics) -> CGFloat {
        let clearance = min(metrics.tailClearance, span / 2)
        return min(max(preferred, clearance), span - clearance)
    }
}
