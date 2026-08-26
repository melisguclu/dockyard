import CoreGraphics
import DockCore
import Foundation

public struct DockLayout: Sendable, Equatable {
    public let barRect: CGRect
    public let tileFrames: [CGRect]
    public let tileScales: [CGFloat]
    public let cornerRadius: CGFloat
    public let indicatorDiameter: CGFloat
    public let indicatorInset: CGFloat

    public init(
        barRect: CGRect,
        tileFrames: [CGRect],
        tileScales: [CGFloat],
        cornerRadius: CGFloat,
        indicatorDiameter: CGFloat,
        indicatorInset: CGFloat
    ) {
        self.barRect = barRect
        self.tileFrames = tileFrames
        self.tileScales = tileScales
        self.cornerRadius = cornerRadius
        self.indicatorDiameter = indicatorDiameter
        self.indicatorInset = indicatorInset
    }

    public static let empty = DockLayout(
        barRect: .zero,
        tileFrames: [],
        tileScales: [],
        cornerRadius: 0,
        indicatorDiameter: 0,
        indicatorInset: 0
    )
}

public struct DockLayoutInput: Sendable {
    public let tiles: [DockTile]
    public let appearance: DockAppearance
    public let metrics: DockMetrics
    public let panelSize: CGSize
    public let cursor: CGPoint?
    public let magnificationAmount: CGFloat
    public let reservedStrip: CGFloat?

    public init(
        tiles: [DockTile],
        appearance: DockAppearance,
        metrics: DockMetrics = .current,
        panelSize: CGSize,
        cursor: CGPoint? = nil,
        magnificationAmount: CGFloat = 1,
        reservedStrip: CGFloat? = nil
    ) {
        self.tiles = tiles
        self.appearance = appearance
        self.metrics = metrics
        self.panelSize = panelSize
        self.cursor = cursor
        self.magnificationAmount = magnificationAmount.clamped(to: 0...1)
        self.reservedStrip = reservedStrip
    }
}

public enum DockGeometry {
    public static let minimumSpacing: CGFloat = 2
    public static let minimumBarPadding: CGFloat = 5
    public static let minimumScreenEdgeMargin: CGFloat = 3

    public static func spacing(_ appearance: DockAppearance, _ metrics: DockMetrics) -> CGFloat {
        max((appearance.tileSize * metrics.interTileSpacingRatio).rounded(), minimumSpacing)
    }

    public static func barPadding(_ appearance: DockAppearance, _ metrics: DockMetrics) -> CGFloat {
        max((appearance.tileSize * metrics.barPaddingRatio).rounded(), minimumBarPadding)
    }

    public static func screenEdgeMargin(_ appearance: DockAppearance, _ metrics: DockMetrics) -> CGFloat {
        max((appearance.tileSize * metrics.screenEdgeMarginRatio).rounded(), minimumScreenEdgeMargin)
    }

    public static func screenEdgeMargin(
        _ appearance: DockAppearance,
        _ metrics: DockMetrics,
        reservedStrip: CGFloat?
    ) -> CGFloat {
        guard let reservedStrip else { return screenEdgeMargin(appearance, metrics) }
        let measured = reservedStrip - barThickness(appearance, metrics)
        return max(measured, minimumScreenEdgeMargin)
    }

    public static func barThickness(_ appearance: DockAppearance, _ metrics: DockMetrics) -> CGFloat {
        appearance.tileSize + 2 * barPadding(appearance, metrics)
    }

    public static func cornerRadius(_ appearance: DockAppearance, _ metrics: DockMetrics) -> CGFloat {
        barThickness(appearance, metrics) * metrics.cornerRadiusRatio
    }

    public static let minimumIndicatorDiameter: CGFloat = 2

    public static func indicatorDiameter(_ appearance: DockAppearance, _ metrics: DockMetrics) -> CGFloat {
        max(appearance.tileSize * metrics.indicatorDiameterRatio, minimumIndicatorDiameter)
    }

    public static func indicatorInset(_ appearance: DockAppearance, _ metrics: DockMetrics) -> CGFloat {
        let padding = barPadding(appearance, metrics)
        let diameter = indicatorDiameter(appearance, metrics)
        let requested = appearance.tileSize * metrics.indicatorInsetRatio
        return max(min(requested, padding - diameter), 0)
    }

    public static func baseLength(
        of tile: DockTile,
        appearance: DockAppearance,
        metrics: DockMetrics
    ) -> CGFloat {
        switch tile.kind {
        case .separator:
            return (appearance.tileSize * metrics.separatorLengthRatio).rounded()
        case .spacer(let width):
            switch width {
            case .small:
                return (appearance.tileSize * metrics.smallSpacerLengthRatio).rounded()
            case .full, .flexible:
                return appearance.tileSize
            }
        default:
            return appearance.tileSize
        }
    }

    public static func barLength(
        tiles: [DockTile],
        appearance: DockAppearance,
        metrics: DockMetrics
    ) -> CGFloat {
        guard !tiles.isEmpty else { return 0 }
        let lengths = tiles.map { baseLength(of: $0, appearance: appearance, metrics: metrics) }
        let gaps = spacing(appearance, metrics) * CGFloat(tiles.count - 1)
        return lengths.reduce(0, +) + gaps + 2 * barPadding(appearance, metrics)
    }

    public static func layout(_ input: DockLayoutInput) -> DockLayout {
        let appearance = input.appearance
        let metrics = input.metrics
        let tiles = input.tiles

        guard !tiles.isEmpty else { return .empty }

        let padding = barPadding(appearance, metrics)
        let gap = spacing(appearance, metrics)
        let margin = screenEdgeMargin(appearance, metrics, reservedStrip: input.reservedStrip)
        let isVertical = appearance.orientation.isVertical
        let available = isVertical ? input.panelSize.height : input.panelSize.width

        let baseLengths = tiles.map { baseLength(of: $0, appearance: appearance, metrics: metrics) }
        let unmagnifiedContent = baseLengths.reduce(0, +) + gap * CGFloat(tiles.count - 1)
        let unmagnifiedBar = unmagnifiedContent + 2 * padding
        let contentStart = (available - unmagnifiedBar) / 2 + padding

        var unmagnifiedStarts: [CGFloat] = []
        unmagnifiedStarts.reserveCapacity(tiles.count)
        var cursorWalk = contentStart
        for length in baseLengths {
            unmagnifiedStarts.append(cursorWalk)
            cursorWalk += length + gap
        }

        let cursorAlong = tileStripCursor(
            input,
            unmagnifiedStarts: unmagnifiedStarts,
            baseLengths: baseLengths
        )

        let scales = tileScales(
            tiles: tiles,
            baseLengths: baseLengths,
            unmagnifiedStarts: unmagnifiedStarts,
            cursorAlong: cursorAlong,
            input: input
        )
        let magnifiedLengths = zip(baseLengths, scales).map { $0 * $1 }

        var starts = unmagnifiedStarts
        if let cursorAlong {
            starts = anchoredStarts(
                cursorAlong: cursorAlong,
                unmagnifiedStarts: unmagnifiedStarts,
                baseLengths: baseLengths,
                magnifiedLengths: magnifiedLengths,
                gap: gap
            )
        }

        let barStart = (starts.first ?? contentStart) - padding
        let barEnd = (starts.last ?? contentStart) + (magnifiedLengths.last ?? 0) + padding
        let shift = edgeShift(barStart: barStart, barEnd: barEnd, available: available)
        if shift != 0 {
            starts = starts.map { $0 + shift }
        }

        let thickness = barThickness(appearance, metrics)
        let barRect = rect(
            along: Span(start: (starts.first ?? contentStart) - padding, length: max(barEnd - barStart, 0)),
            across: Span(start: margin, length: thickness),
            panelSize: input.panelSize,
            orientation: appearance.orientation
        )

        var frames: [CGRect] = []
        frames.reserveCapacity(tiles.count)
        for index in tiles.indices {
            let scale = tiles[index].occupiesTileSlot ? scales[index] : 1
            let acrossLength = appearance.tileSize * scale
            frames.append(
                rect(
                    along: Span(start: starts[index], length: magnifiedLengths[index]),
                    across: Span(start: margin + padding, length: acrossLength),
                    panelSize: input.panelSize,
                    orientation: appearance.orientation
                )
            )
        }

        return DockLayout(
            barRect: barRect,
            tileFrames: frames,
            tileScales: scales,
            cornerRadius: cornerRadius(appearance, metrics),
            indicatorDiameter: indicatorDiameter(appearance, metrics),
            indicatorInset: indicatorInset(appearance, metrics)
        )
    }

    public static func hitIndex(in layout: DockLayout, at point: CGPoint) -> Int? {
        for (index, frame) in layout.tileFrames.enumerated() where frame.contains(point) {
            return index
        }
        return nil
    }

    private static func alongCursor(_ input: DockLayoutInput) -> CGFloat? {
        guard input.appearance.magnificationEnabled, let cursor = input.cursor else { return nil }
        guard input.appearance.effectiveLargeSize > input.appearance.tileSize else { return nil }
        guard input.magnificationAmount > 0 else { return nil }
        switch input.appearance.orientation {
        case .bottom:
            return cursor.x
        case .left, .right:
            return input.panelSize.height - cursor.y
        }
    }

    private static func tileStripCursor(
        _ input: DockLayoutInput,
        unmagnifiedStarts: [CGFloat],
        baseLengths: [CGFloat]
    ) -> CGFloat? {
        guard let cursorAlong = alongCursor(input) else { return nil }
        guard let stripStart = unmagnifiedStarts.first,
            let lastStart = unmagnifiedStarts.last,
            let lastLength = baseLengths.last
        else { return nil }
        return cursorAlong.clamped(to: stripStart...(lastStart + lastLength))
    }

    private static func tileScales(
        tiles: [DockTile],
        baseLengths: [CGFloat],
        unmagnifiedStarts: [CGFloat],
        cursorAlong: CGFloat?,
        input: DockLayoutInput
    ) -> [CGFloat] {
        guard let cursorAlong else {
            return Array(repeating: 1, count: tiles.count)
        }

        let appearance = input.appearance
        let metrics = input.metrics
        let pitch = appearance.tileSize + spacing(appearance, metrics)
        let maximum = MagnificationCurve.maximumScale(
            tileSize: appearance.tileSize,
            largeSize: appearance.effectiveLargeSize,
            amount: input.magnificationAmount
        )

        return tiles.indices.map { index in
            guard tiles[index].occupiesTileSlot else { return 1 }
            let center = unmagnifiedStarts[index] + baseLengths[index] / 2
            let distance = (center - cursorAlong) / max(pitch, 1)
            return MagnificationCurve.scale(
                distanceInTiles: distance,
                window: metrics.magnificationWindowTiles,
                maximumScale: maximum
            )
        }
    }

    private static func anchoredStarts(
        cursorAlong: CGFloat,
        unmagnifiedStarts: [CGFloat],
        baseLengths: [CGFloat],
        magnifiedLengths: [CGFloat],
        gap: CGFloat
    ) -> [CGFloat] {
        let count = baseLengths.count
        guard count > 0 else { return [] }

        var anchorIndex = 0
        for index in 0..<count where unmagnifiedStarts[index] <= cursorAlong {
            anchorIndex = index
        }

        let anchorSpan = baseLengths[anchorIndex] + gap
        let fraction = ((cursorAlong - unmagnifiedStarts[anchorIndex]) / max(anchorSpan, 1))
            .clamped(to: 0...1)

        var starts = Array(repeating: CGFloat(0), count: count)
        starts[anchorIndex] = cursorAlong - fraction * (magnifiedLengths[anchorIndex] + gap)

        if anchorIndex > 0 {
            for index in stride(from: anchorIndex - 1, through: 0, by: -1) {
                starts[index] = starts[index + 1] - gap - magnifiedLengths[index]
            }
        }
        if anchorIndex + 1 < count {
            for index in (anchorIndex + 1)..<count {
                starts[index] = starts[index - 1] + magnifiedLengths[index - 1] + gap
            }
        }
        return starts
    }

    private static func edgeShift(barStart: CGFloat, barEnd: CGFloat, available: CGFloat) -> CGFloat {
        if barStart < 0 { return -barStart }
        if barEnd > available { return max(available - barEnd, -barStart) }
        return 0
    }

    private static func rect(
        along: Span,
        across: Span,
        panelSize: CGSize,
        orientation: DockOrientation
    ) -> CGRect {
        switch orientation {
        case .bottom:
            return CGRect(x: along.start, y: across.start, width: along.length, height: across.length)
        case .left:
            return CGRect(
                x: across.start,
                y: panelSize.height - along.start - along.length,
                width: across.length,
                height: along.length
            )
        case .right:
            return CGRect(
                x: panelSize.width - across.start - across.length,
                y: panelSize.height - along.start - along.length,
                width: across.length,
                height: along.length
            )
        }
    }
}

private struct Span {
    let start: CGFloat
    let length: CGFloat
}
