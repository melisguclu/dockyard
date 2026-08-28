import CoreGraphics
import DockCore
import Foundation

public enum DockStackMode: Sendable, Equatable {
    case fan
    case grid
    case list
}

public enum DockStackTextAlignment: Sendable, Equatable {
    case leading
    case centre
}

public struct DockStackItemLayout: Sendable, Equatable {
    public let frame: CGRect
    public let iconFrame: CGRect
    public let textFrame: CGRect
    public let alignment: DockStackTextAlignment

    public init(frame: CGRect, iconFrame: CGRect, textFrame: CGRect, alignment: DockStackTextAlignment) {
        self.frame = frame
        self.iconFrame = iconFrame
        self.textFrame = textFrame
        self.alignment = alignment
    }
}

public struct DockStackLayout: Sendable, Equatable {
    public let mode: DockStackMode
    public let balloon: DockMenuBalloon
    public let items: [DockStackItemLayout]
    public let visibleCount: Int
    public let overflowCount: Int

    public var hasOverflowRow: Bool { overflowCount > 0 }

    public var overflowIndex: Int? { hasOverflowRow ? visibleCount : nil }

    public init(
        mode: DockStackMode,
        balloon: DockMenuBalloon,
        items: [DockStackItemLayout],
        visibleCount: Int,
        overflowCount: Int
    ) {
        self.mode = mode
        self.balloon = balloon
        self.items = items
        self.visibleCount = visibleCount
        self.overflowCount = overflowCount
    }
}

public struct DockStackLayoutInput: Sendable {
    public let textWidths: [CGFloat]
    public let requested: FolderStackViewMode
    public let anchor: CGRect
    public let orientation: DockOrientation
    public let screen: CGRect
    public let truncated: Int
    public let metrics: DockStackMetrics

    public init(
        textWidths: [CGFloat],
        requested: FolderStackViewMode,
        anchor: CGRect,
        orientation: DockOrientation,
        screen: CGRect,
        truncated: Int = 0,
        metrics: DockStackMetrics = .current
    ) {
        self.textWidths = textWidths
        self.requested = requested
        self.anchor = anchor
        self.orientation = orientation
        self.screen = screen
        self.truncated = truncated
        self.metrics = metrics
    }

    var count: Int { textWidths.count }
}

public enum DockStackGeometry {
    public static func layout(_ input: DockStackLayoutInput) -> DockStackLayout {
        let limits = bodyLimits(input)
        let mode = resolve(input, limits: limits)
        switch mode {
        case .grid:
            return grid(input, limits: limits)
        case .fan, .list:
            return column(input, mode: mode, limits: limits)
        }
    }

    public static func resolve(_ input: DockStackLayoutInput, limits: CGSize) -> DockStackMode {
        switch input.requested {
        case .fan:
            return .fan
        case .grid:
            return .grid
        case .list:
            return .list
        case .automatic:
            let rows = rowCapacity(input, mode: .fan, limits: limits)
            let fits = input.count <= min(rows, input.metrics.fanAutomaticLimit)
            return fits && input.truncated == 0 ? .fan : .grid
        }
    }

    static func bodyLimits(_ input: DockStackLayoutInput) -> CGSize {
        let metrics = input.metrics.balloon
        let screen = input.screen
        switch input.orientation {
        case .bottom:
            let ceiling =
                screen.maxY - metrics.screenInset - metrics.tailLength
                - (input.anchor.maxY + metrics.tileGap)
            return CGSize(
                width: max(screen.width - 2 * metrics.screenInset, input.metrics.minimumWidth),
                height: max(ceiling, input.metrics.rowHeight)
            )
        case .left, .right:
            let ceiling =
                screen.width - 2 * metrics.screenInset - metrics.tailLength
                - input.anchor.width - metrics.tileGap
            return CGSize(
                width: max(ceiling, input.metrics.minimumWidth),
                height: max(screen.height - 2 * metrics.screenInset, input.metrics.rowHeight)
            )
        }
    }

    static func rowCapacity(_ input: DockStackLayoutInput, mode: DockStackMode, limits: CGSize) -> Int {
        let metrics = input.metrics
        let usable = limits.height - 2 * metrics.verticalPadding
        let height = metrics.rowHeight(for: mode)
        guard height > 0 else { return 1 }
        return max(Int((usable / height).rounded(.down)), 1)
    }

    private static func column(
        _ input: DockStackLayoutInput,
        mode: DockStackMode,
        limits: CGSize
    ) -> DockStackLayout {
        let metrics = input.metrics
        let capacity = rowCapacity(input, mode: mode, limits: limits)
        let split = split(count: input.count, capacity: capacity, truncated: input.truncated)
        let rowHeight = metrics.rowHeight(for: mode)
        let rows = split.visible + (split.overflow > 0 ? 1 : 0)

        let arc = mode == .fan && input.orientation == .bottom ? metrics.fanArcDepth : 0
        let icon = metrics.iconSize(for: mode)
        let widest = input.textWidths.prefix(split.visible).reduce(0) { max($0, min($1, metrics.maximumTextWidth)) }
        let bodyWidth = min(
            max(
                metrics.horizontalPadding + arc + icon + metrics.iconTextGap + widest + metrics.trailingTextInset,
                metrics.minimumWidth
            ),
            limits.width
        )
        let bodyHeight = 2 * metrics.verticalPadding + rowHeight * CGFloat(rows)

        let balloon = DockMenuLayout.balloon(
            contentSize: CGSize(width: bodyWidth, height: bodyHeight),
            anchor: input.anchor,
            orientation: input.orientation,
            screen: input.screen,
            metrics: metrics.balloon
        )

        let direction: CGFloat = input.anchor.midX <= input.screen.midX ? 1 : -1
        var items: [DockStackItemLayout] = []
        items.reserveCapacity(rows)
        for index in 0..<rows {
            let offset = arcOffset(
                index: index,
                rows: rows,
                depth: arc,
                direction: direction
            )
            let top =
                mode == .fan
                ? bodyHeight - metrics.verticalPadding - rowHeight * CGFloat(index + 1)
                : metrics.verticalPadding + rowHeight * CGFloat(index)
            let frame = CGRect(x: 0, y: top, width: bodyWidth, height: rowHeight)
            let iconOrigin = metrics.horizontalPadding + offset
            items.append(
                DockStackItemLayout(
                    frame: frame,
                    iconFrame: CGRect(
                        x: iconOrigin,
                        y: top + (rowHeight - icon) / 2,
                        width: icon,
                        height: icon
                    ),
                    textFrame: CGRect(
                        x: iconOrigin + icon + metrics.iconTextGap,
                        y: top,
                        width: max(
                            bodyWidth - iconOrigin - icon - metrics.iconTextGap - metrics.trailingTextInset,
                            0
                        ),
                        height: rowHeight
                    ),
                    alignment: .leading
                )
            )
        }

        return DockStackLayout(
            mode: mode,
            balloon: balloon,
            items: items,
            visibleCount: split.visible,
            overflowCount: split.overflow
        )
    }

    private static func grid(_ input: DockStackLayoutInput, limits: CGSize) -> DockStackLayout {
        let metrics = input.metrics
        let columns = gridColumns(input, limits: limits)
        let usable = limits.height - 2 * metrics.verticalPadding
        let rowsCapacity = max(Int((usable / metrics.gridCellHeight).rounded(.down)), 1)
        var division = split(count: input.count, capacity: columns * rowsCapacity, truncated: input.truncated)
        if division.overflow > 0 {
            let reduced = max(
                Int(((usable - metrics.rowHeight) / metrics.gridCellHeight).rounded(.down)),
                1
            )
            division = split(
                count: input.count,
                capacity: columns * reduced,
                truncated: input.truncated,
                reserve: false
            )
        }

        let rows = max(
            Int((Double(division.visible) / Double(columns)).rounded(.up)),
            division.visible > 0 ? 1 : 0
        )
        let bodyWidth = min(
            max(2 * metrics.horizontalPadding + metrics.gridCellWidth * CGFloat(columns), metrics.minimumWidth),
            limits.width
        )
        let bodyHeight =
            2 * metrics.verticalPadding + metrics.gridCellHeight * CGFloat(rows)
            + (division.overflow > 0 ? metrics.rowHeight : 0)

        let balloon = DockMenuLayout.balloon(
            contentSize: CGSize(width: bodyWidth, height: bodyHeight),
            anchor: input.anchor,
            orientation: input.orientation,
            screen: input.screen,
            metrics: metrics.balloon
        )

        return DockStackLayout(
            mode: .grid,
            balloon: balloon,
            items: gridItems(
                GridBody(
                    visible: division.visible,
                    overflow: division.overflow,
                    columns: columns,
                    size: CGSize(width: bodyWidth, height: bodyHeight)
                ),
                metrics: metrics
            ),
            visibleCount: division.visible,
            overflowCount: division.overflow
        )
    }

    private static func gridColumns(_ input: DockStackLayoutInput, limits: CGSize) -> Int {
        let metrics = input.metrics
        let widthCapacity = Int(
            ((limits.width - 2 * metrics.horizontalPadding) / metrics.gridCellWidth).rounded(.down)
        )
        return max(
            min(
                Int(Double(input.count).squareRoot().rounded(.up)),
                min(metrics.gridMaximumColumns, max(widthCapacity, 1))
            ),
            1
        )
    }

    private struct GridBody {
        let visible: Int
        let overflow: Int
        let columns: Int
        let size: CGSize
    }

    private static func gridItems(_ body: GridBody, metrics: DockStackMetrics) -> [DockStackItemLayout] {
        let visible = body.visible
        let overflow = body.overflow
        let columns = body.columns
        let bodyWidth = body.size.width
        let bodyHeight = body.size.height
        var items: [DockStackItemLayout] = []
        items.reserveCapacity(visible + 1)
        let leading = (bodyWidth - metrics.gridCellWidth * CGFloat(columns)) / 2
        for index in 0..<visible {
            let frame = CGRect(
                x: leading + CGFloat(index % columns) * metrics.gridCellWidth,
                y: metrics.verticalPadding + CGFloat(index / columns) * metrics.gridCellHeight,
                width: metrics.gridCellWidth,
                height: metrics.gridCellHeight
            )
            items.append(
                DockStackItemLayout(
                    frame: frame,
                    iconFrame: CGRect(
                        x: frame.midX - metrics.gridIconSize / 2,
                        y: frame.minY + metrics.gridIconInset,
                        width: metrics.gridIconSize,
                        height: metrics.gridIconSize
                    ),
                    textFrame: CGRect(
                        x: frame.minX + 2,
                        y: frame.minY + metrics.gridIconInset + metrics.gridIconSize + 2,
                        width: frame.width - 4,
                        height: metrics.gridLabelHeight
                    ),
                    alignment: .centre
                )
            )
        }
        guard overflow > 0 else { return items }
        let frame = CGRect(
            x: 0,
            y: bodyHeight - metrics.verticalPadding - metrics.rowHeight,
            width: bodyWidth,
            height: metrics.rowHeight
        )
        items.append(
            DockStackItemLayout(frame: frame, iconFrame: .zero, textFrame: frame, alignment: .centre)
        )
        return items
    }

    struct Split: Equatable {
        let visible: Int
        let overflow: Int
    }

    static func split(count: Int, capacity: Int, truncated: Int, reserve: Bool = true) -> Split {
        guard count + truncated > capacity else {
            return Split(visible: count, overflow: truncated)
        }
        let room = reserve ? max(capacity - 1, 0) : capacity
        let visible = min(count, room)
        return Split(visible: visible, overflow: count - visible + truncated)
    }

    private static func arcOffset(
        index: Int,
        rows: Int,
        depth: CGFloat,
        direction: CGFloat
    ) -> CGFloat {
        guard depth > 0, rows > 1 else { return direction < 0 ? depth : 0 }
        let position = CGFloat(index) / CGFloat(rows - 1)
        let curve = depth * sin(position * .pi / 2)
        return direction > 0 ? curve : depth - curve
    }
}
