import CoreGraphics
import DockCore
import Foundation

public struct DockTileLabelMetrics: Sendable, Equatable {
    public var fontSize: CGFloat
    public var height: CGFloat
    public var textInset: CGFloat
    public var maximumWidth: CGFloat
    public var balloon: DockBalloonMetrics

    public init(
        fontSize: CGFloat,
        height: CGFloat,
        textInset: CGFloat,
        maximumWidth: CGFloat,
        balloon: DockBalloonMetrics
    ) {
        self.fontSize = fontSize
        self.height = height
        self.textInset = textInset
        self.maximumWidth = maximumWidth
        self.balloon = balloon
    }

    public func balloon(for orientation: DockOrientation) -> DockBalloonMetrics {
        guard orientation.isVertical else { return balloon }
        var untailed = balloon
        untailed.tileGap += untailed.tailLength
        untailed.tailLength = 0
        return untailed
    }

    public static let current = DockTileLabelMetrics(
        fontSize: 14,
        height: 26,
        textInset: 13,
        maximumWidth: 420,
        balloon: DockBalloonMetrics(
            cornerRadius: 13,
            tailLength: 6.5,
            tailBaseHalfWidth: 9,
            tailBaseFillet: 6.5,
            tailApexDepth: 7.2,
            tailTipRadius: 2.5,
            tileGap: 10.5,
            screenInset: 8,
            minimumWidth: 0
        )
    )
}

public enum DockTileLabelLayout {
    public static func width(textWidth: CGFloat, metrics: DockTileLabelMetrics = .current) -> CGFloat {
        let padded = textWidth.rounded(.up) + 2 * metrics.textInset
        return min(padded, metrics.maximumWidth)
    }

    public static func balloon(
        width: CGFloat,
        anchor: CGRect,
        orientation: DockOrientation,
        screen: CGRect,
        metrics: DockTileLabelMetrics = .current
    ) -> DockMenuBalloon {
        DockMenuLayout.balloon(
            contentSize: CGSize(width: width, height: metrics.height),
            anchor: anchor,
            orientation: orientation,
            screen: screen,
            metrics: metrics.balloon(for: orientation)
        )
    }
}
