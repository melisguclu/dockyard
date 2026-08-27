import CoreGraphics
import DockCore
import Foundation

public struct DockPanelExtent: OptionSet, Sendable, Equatable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let magnified = DockPanelExtent(rawValue: 1 << 0)
    public static let bouncing = DockPanelExtent(rawValue: 1 << 1)
    public static let resting: DockPanelExtent = []
}

extension DockGeometry {
    public static let headroomPhaseSamples = 16

    public static func magnificationHeadroom(
        tiles: [DockTile],
        appearance: DockAppearance,
        metrics: DockMetrics
    ) -> CGFloat {
        guard appearance.magnificationEnabled, !tiles.isEmpty else { return 0 }
        let maximum = MagnificationCurve.maximumScale(
            tileSize: appearance.tileSize,
            largeSize: appearance.effectiveLargeSize
        )
        guard maximum > 1 else { return 0 }

        let window = metrics.magnificationWindowTiles
        let reach = Int(window.rounded(.up))
        var worst: CGFloat = 0
        for sample in 0..<headroomPhaseSamples {
            let phase = CGFloat(sample) / CGFloat(headroomPhaseSamples)
            var growth: CGFloat = 0
            for offset in -reach...reach {
                let scale = MagnificationCurve.scale(
                    distanceInTiles: CGFloat(offset) + phase,
                    window: window,
                    maximumScale: maximum
                )
                growth += appearance.tileSize * (scale - 1)
            }
            worst = max(worst, growth)
        }

        let ceiling = tiles.reduce(CGFloat(0)) {
            $0 + baseLength(of: $1, appearance: appearance, metrics: metrics) * (maximum - 1)
        }
        let slack = appearance.tileSize + spacing(appearance, metrics)
        return min(worst + slack, ceiling)
    }

    public static func panelLength(
        tiles: [DockTile],
        appearance: DockAppearance,
        metrics: DockMetrics,
        extent: DockPanelExtent
    ) -> CGFloat {
        let bar = barLength(tiles: tiles, appearance: appearance, metrics: metrics)
        guard bar > 0, extent.contains(.magnified) else { return bar }
        let headroom = magnificationHeadroom(tiles: tiles, appearance: appearance, metrics: metrics)
        return bar + 2 * headroom
    }

    public static func panelThickness(
        _ appearance: DockAppearance,
        _ metrics: DockMetrics,
        measuredEdgeMargin: CGFloat? = nil,
        extent: DockPanelExtent = .magnified
    ) -> CGFloat {
        let margin = screenEdgeMargin(appearance, metrics, measuredEdgeMargin: measuredEdgeMargin)
        let padding = barPadding(appearance, metrics)
        let magnified = extent.contains(.magnified)
        var thickness = margin + barThickness(appearance, metrics)
        if magnified {
            thickness = max(thickness, margin + padding + appearance.effectiveLargeSize + padding)
        }
        if extent.contains(.bouncing) {
            let icon = magnified ? appearance.effectiveLargeSize : appearance.tileSize
            thickness = max(thickness, margin + padding + icon + DockLaunchBounce.travel(appearance))
        }
        return thickness
    }

    public static func panelFrame(
        screenFrame: CGRect,
        tiles: [DockTile],
        appearance: DockAppearance,
        metrics: DockMetrics,
        measuredEdgeMargin: CGFloat? = nil,
        extent: DockPanelExtent = .magnified
    ) -> CGRect {
        let isVertical = appearance.orientation.isVertical
        let thickness = min(
            panelThickness(appearance, metrics, measuredEdgeMargin: measuredEdgeMargin, extent: extent),
            isVertical ? screenFrame.width : screenFrame.height
        )
        let along = min(
            panelLength(tiles: tiles, appearance: appearance, metrics: metrics, extent: extent),
            isVertical ? screenFrame.height : screenFrame.width
        )
        switch appearance.orientation {
        case .bottom:
            return CGRect(
                x: screenFrame.minX + (screenFrame.width - along) / 2,
                y: screenFrame.minY,
                width: along,
                height: thickness
            )
        case .left:
            return CGRect(
                x: screenFrame.minX,
                y: screenFrame.minY + (screenFrame.height - along) / 2,
                width: thickness,
                height: along
            )
        case .right:
            return CGRect(
                x: screenFrame.maxX - thickness,
                y: screenFrame.minY + (screenFrame.height - along) / 2,
                width: thickness,
                height: along
            )
        }
    }
}
