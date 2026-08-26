import CoreGraphics
import DockCore
import Foundation

public enum DockPanelExtent: Sendable, Equatable {
    case resting
    case magnified
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
        guard bar > 0, extent == .magnified else { return bar }
        let headroom = magnificationHeadroom(tiles: tiles, appearance: appearance, metrics: metrics)
        return bar + 2 * headroom
    }

    public static func panelThickness(
        _ appearance: DockAppearance,
        _ metrics: DockMetrics,
        reservedStrip: CGFloat? = nil,
        extent: DockPanelExtent = .magnified
    ) -> CGFloat {
        let margin = screenEdgeMargin(appearance, metrics, reservedStrip: reservedStrip)
        let resting = margin + barThickness(appearance, metrics)
        guard extent == .magnified else { return resting }
        let padding = barPadding(appearance, metrics)
        let magnified = margin + padding + appearance.effectiveLargeSize + padding
        return max(resting, magnified)
    }

    public static func panelFrame(
        screenFrame: CGRect,
        tiles: [DockTile],
        appearance: DockAppearance,
        metrics: DockMetrics,
        reservedStrip: CGFloat? = nil,
        extent: DockPanelExtent = .magnified
    ) -> CGRect {
        let isVertical = appearance.orientation.isVertical
        let thickness = min(
            panelThickness(appearance, metrics, reservedStrip: reservedStrip, extent: extent),
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
