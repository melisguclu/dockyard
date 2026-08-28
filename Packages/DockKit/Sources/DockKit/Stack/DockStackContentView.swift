import AppKit
import DockCore
import Foundation

struct DockStackRow: Equatable {
    let title: String
    let cacheKey: String
    let isSelectable: Bool
    let isOverflow: Bool

    static func entry(_ entry: FolderStackEntry) -> DockStackRow {
        DockStackRow(title: entry.name, cacheKey: entry.url.path, isSelectable: true, isOverflow: false)
    }

    static func overflow(_ title: String) -> DockStackRow {
        DockStackRow(title: title, cacheKey: "", isSelectable: true, isOverflow: true)
    }

    static func message(_ title: String) -> DockStackRow {
        DockStackRow(title: title, cacheKey: "", isSelectable: false, isOverflow: false)
    }
}

@MainActor
final class DockStackContentView: NSView {
    var onSelect: ((Int) -> Void)?
    var onCancel: (() -> Void)?

    private let rows: [DockStackRow]
    private let layout: DockStackLayout
    private let metrics: DockStackMetrics
    private var icons: [String: CGImage] = [:]
    private var highlighted: Int?
    private var trackingRegion: NSTrackingArea?

    init(rows: [DockStackRow], layout: DockStackLayout, metrics: DockStackMetrics) {
        self.rows = rows
        self.layout = layout
        self.metrics = metrics
        super.init(frame: layout.balloon.contentFrame)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }

    override var acceptsFirstResponder: Bool { true }

    static func textWidth(of title: String, mode: DockStackMode, metrics: DockStackMetrics) -> CGFloat {
        (title as NSString).size(withAttributes: [.font: font(for: mode, metrics: metrics)]).width
    }

    static func font(for mode: DockStackMode, metrics: DockStackMetrics) -> NSFont {
        .systemFont(ofSize: mode == .grid ? metrics.gridLabelFontSize : metrics.labelFontSize)
    }

    func setIcon(_ image: CGImage?, forKey key: String) {
        guard let image, icons[key] == nil else { return }
        icons[key] = image
        guard let index = rows.firstIndex(where: { $0.cacheKey == key }),
            index < layout.items.count
        else { return }
        setNeedsDisplay(layout.items[index].frame)
    }

    override func draw(_ dirtyRect: NSRect) {
        for (index, row) in rows.enumerated() where index < layout.items.count {
            let item = layout.items[index]
            guard item.frame.intersects(dirtyRect) else { continue }
            if index == highlighted, row.isSelectable {
                drawHighlight(in: item.frame)
            }
            if !row.isOverflow, let image = icons[row.cacheKey], !item.iconFrame.isEmpty {
                draw(image, in: item.iconFrame)
            }
            draw(row, item: item, isHighlighted: index == highlighted)
        }
    }

    private func drawHighlight(in frame: CGRect) {
        let inset = frame.insetBy(dx: metrics.highlightInset, dy: 1)
        NSColor.selectedContentBackgroundColor.setFill()
        NSBezierPath(
            roundedRect: inset,
            xRadius: metrics.highlightRadius,
            yRadius: metrics.highlightRadius
        )
        .fill()
    }

    private func draw(_ image: CGImage, in frame: CGRect) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.translateBy(x: 0, y: frame.maxY + frame.minY)
        context.scaleBy(x: 1, y: -1)
        context.interpolationQuality = .high
        context.draw(image, in: frame)
        context.restoreGState()
    }

    private func draw(_ row: DockStackRow, item: DockStackItemLayout, isHighlighted: Bool) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingMiddle
        paragraph.alignment = item.alignment == .centre ? .center : .left
        let colour: NSColor
        if !row.isSelectable {
            colour = .disabledControlTextColor
        } else if isHighlighted {
            colour = .selectedMenuItemTextColor
        } else {
            colour = .labelColor
        }
        let attributes: [NSAttributedString.Key: Any] = [
            .font: Self.font(for: layout.mode, metrics: metrics),
            .foregroundColor: colour,
            .paragraphStyle: paragraph,
        ]
        let text = row.title as NSString
        let height = text.size(withAttributes: attributes).height
        let rect =
            layout.mode == .grid && !row.isOverflow
            ? item.textFrame
            : CGRect(
                x: item.textFrame.minX,
                y: item.textFrame.midY - height / 2,
                width: item.textFrame.width,
                height: height
            )
        text.draw(in: rect, withAttributes: attributes)
    }

    private func index(at point: CGPoint) -> Int? {
        for index in rows.indices where index < layout.items.count && rows[index].isSelectable {
            if layout.items[index].frame.contains(point) { return index }
        }
        return nil
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingRegion {
            removeTrackingArea(trackingRegion)
        }
        let area = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingRegion = area
    }

    override func mouseMoved(with event: NSEvent) {
        setHighlighted(index(at: convert(event.locationInWindow, from: nil)))
    }

    override func mouseDragged(with event: NSEvent) {
        setHighlighted(index(at: convert(event.locationInWindow, from: nil)))
    }

    override func mouseExited(with event: NSEvent) {
        setHighlighted(nil)
    }

    override func mouseUp(with event: NSEvent) {
        guard let index = index(at: convert(event.locationInWindow, from: nil)) else { return }
        onSelect?(index)
    }

    override func keyDown(with event: NSEvent) {
        switch Int(event.keyCode) {
        case 53:
            onCancel?()
        case 36, 76:
            guard let highlighted else { return }
            onSelect?(highlighted)
        case 125:
            moveHighlight(by: verticalStep)
        case 126:
            moveHighlight(by: -verticalStep)
        case 124:
            moveHighlight(by: layout.mode == .grid ? 1 : 0)
        case 123:
            moveHighlight(by: layout.mode == .grid ? -1 : 0)
        default:
            super.keyDown(with: event)
        }
    }

    private var verticalStep: Int {
        switch layout.mode {
        case .grid:
            return columns
        case .list:
            return 1
        case .fan:
            return -1
        }
    }

    private var columns: Int {
        guard let first = layout.items.first else { return 1 }
        let sameRow = layout.items.filter { abs($0.frame.minY - first.frame.minY) < 1 }
        return max(sameRow.count, 1)
    }

    private func moveHighlight(by step: Int) {
        guard step != 0 else { return }
        let selectable = rows.indices.filter { rows[$0].isSelectable && $0 < layout.items.count }
        guard !selectable.isEmpty else { return }
        guard let current = highlighted, let position = selectable.firstIndex(of: current) else {
            setHighlighted(step > 0 ? selectable.first : selectable.last)
            return
        }
        let next = ((position + step) % selectable.count + selectable.count) % selectable.count
        setHighlighted(selectable[next])
    }

    private func setHighlighted(_ index: Int?) {
        guard highlighted != index else { return }
        if let highlighted, highlighted < layout.items.count {
            setNeedsDisplay(layout.items[highlighted].frame)
        }
        highlighted = index
        if let index, index < layout.items.count {
            setNeedsDisplay(layout.items[index].frame)
        }
    }
}
