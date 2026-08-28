import CoreGraphics
import Foundation

public struct DockStackMetrics: Sendable, Equatable {
    public var rowHeight: CGFloat
    public var rowIconSize: CGFloat
    public var fanRowHeight: CGFloat
    public var fanIconSize: CGFloat
    public var fanArcDepth: CGFloat
    public var fanAutomaticLimit: Int
    public var gridIconSize: CGFloat
    public var gridIconInset: CGFloat
    public var gridCellWidth: CGFloat
    public var gridCellHeight: CGFloat
    public var gridMaximumColumns: Int
    public var horizontalPadding: CGFloat
    public var verticalPadding: CGFloat
    public var iconTextGap: CGFloat
    public var trailingTextInset: CGFloat
    public var minimumWidth: CGFloat
    public var maximumTextWidth: CGFloat
    public var labelFontSize: CGFloat
    public var gridLabelFontSize: CGFloat
    public var gridLabelHeight: CGFloat
    public var highlightInset: CGFloat
    public var highlightRadius: CGFloat
    public var balloon: DockBalloonMetrics

    public static let current = DockStackMetrics(
        rowHeight: 24,
        rowIconSize: 16,
        fanRowHeight: 44,
        fanIconSize: 32,
        fanArcDepth: 22,
        fanAutomaticLimit: 10,
        gridIconSize: 48,
        gridIconInset: 6,
        gridCellWidth: 84,
        gridCellHeight: 82,
        gridMaximumColumns: 5,
        horizontalPadding: 10,
        verticalPadding: 8,
        iconTextGap: 8,
        trailingTextInset: 18,
        minimumWidth: 148,
        maximumTextWidth: 260,
        labelFontSize: 13,
        gridLabelFontSize: 11,
        gridLabelHeight: 26,
        highlightInset: 5,
        highlightRadius: 7,
        balloon: DockBalloonMetrics(
            cornerRadius: 11,
            tailLength: 10.6,
            tailBaseHalfWidth: 9,
            tailBaseFillet: 6.5,
            tailApexDepth: 14,
            tailTipRadius: 4.2,
            tileGap: 6,
            screenInset: 8,
            minimumWidth: 148
        )
    )

    public func iconSize(for mode: DockStackMode) -> CGFloat {
        switch mode {
        case .fan:
            return fanIconSize
        case .list:
            return rowIconSize
        case .grid:
            return gridIconSize
        }
    }

    public func rowHeight(for mode: DockStackMode) -> CGFloat {
        switch mode {
        case .fan:
            return fanRowHeight
        case .list, .grid:
            return rowHeight
        }
    }
}
