import AppKit
import DockCore
import Foundation

@MainActor
final class DockMenuContentView: NSView {
    var onSelect: ((DockMenuItem) -> Void)?
    var onCancel: (() -> Void)?

    private let items: [DockMenuItem]
    private let metrics: DockMenuMetrics
    private var highlighted: Int?
    private var trackingRegion: NSTrackingArea?

    init(items: [DockMenuItem], metrics: DockMenuMetrics) {
        self.items = items
        self.metrics = metrics
        super.init(frame: CGRect(origin: .zero, size: Self.contentSize(for: items, metrics: metrics)))
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    static func contentSize(for items: [DockMenuItem], metrics: DockMenuMetrics) -> CGSize {
        let width = items.reduce(metrics.minimumWidth) { widest, item in
            guard item.isSelectable || !item.title.isEmpty else { return widest }
            let text = item.title.size(withAttributes: [.font: menuFont]).width
            return max(widest, text + metrics.leadingTextInset + metrics.trailingTextInset)
        }
        let height = items.reduce(2 * metrics.verticalPadding) { total, item in
            total + Self.height(of: item, metrics: metrics)
        }
        return CGSize(width: min(width, metrics.maximumWidth).rounded(.up), height: height)
    }

    private static func height(of item: DockMenuItem, metrics: DockMenuMetrics) -> CGFloat {
        switch item.kind {
        case .separator:
            return metrics.separatorHeight
        case .command:
            return metrics.rowHeight
        }
    }

    private static var menuFont: NSFont { NSFont.menuFont(ofSize: 0) }

    override var isFlipped: Bool { true }

    override var acceptsFirstResponder: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        for (index, item) in items.enumerated() {
            let frame = rowFrame(at: index)
            guard frame.intersects(dirtyRect) else { continue }
            switch item.kind {
            case .separator:
                drawSeparator(in: frame)
            case .command:
                drawCommand(item, in: frame, isHighlighted: index == highlighted)
            }
        }
    }

    private func drawSeparator(in frame: CGRect) {
        let line = CGRect(
            x: frame.minX + metrics.separatorInset,
            y: frame.midY - 0.5,
            width: frame.width - 2 * metrics.separatorInset,
            height: 1
        )
        NSColor.separatorColor.setFill()
        line.fill()
    }

    private func drawCommand(_ item: DockMenuItem, in frame: CGRect, isHighlighted: Bool) {
        var color = item.isEnabled ? NSColor.labelColor : NSColor.disabledControlTextColor
        if isHighlighted {
            let highlight = frame.insetBy(dx: metrics.highlightInset, dy: 0)
            NSColor.selectedContentBackgroundColor.setFill()
            NSBezierPath(roundedRect: highlight, xRadius: metrics.highlightRadius, yRadius: metrics.highlightRadius)
                .fill()
            color = .selectedMenuItemTextColor
        }

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingMiddle
        let attributes: [NSAttributedString.Key: Any] = [
            .font: Self.menuFont,
            .foregroundColor: color,
            .paragraphStyle: paragraph,
        ]
        let text = item.title as NSString
        let size = text.size(withAttributes: attributes)
        let width = frame.width - metrics.leadingTextInset - metrics.trailingTextInset
        text.draw(
            in: CGRect(
                x: frame.minX + metrics.leadingTextInset,
                y: frame.midY - size.height / 2,
                width: max(width, 0),
                height: size.height
            ),
            withAttributes: attributes
        )
    }

    private func rowFrame(at index: Int) -> CGRect {
        var offset = metrics.verticalPadding
        for item in items.prefix(index) {
            offset += Self.height(of: item, metrics: metrics)
        }
        return CGRect(
            x: 0,
            y: offset,
            width: bounds.width,
            height: Self.height(of: items[index], metrics: metrics)
        )
    }

    private func index(at point: CGPoint) -> Int? {
        for index in items.indices where items[index].isSelectable && rowFrame(at: index).contains(point) {
            return index
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
        onSelect?(items[index])
    }

    override func keyDown(with event: NSEvent) {
        switch Int(event.keyCode) {
        case 53:
            onCancel?()
        case 36, 76:
            guard let highlighted else { return }
            onSelect?(items[highlighted])
        case 125:
            moveHighlight(by: 1)
        case 126:
            moveHighlight(by: -1)
        default:
            super.keyDown(with: event)
        }
    }

    private func moveHighlight(by step: Int) {
        let selectable = items.indices.filter { items[$0].isSelectable }
        guard !selectable.isEmpty else { return }
        guard let current = highlighted, let position = selectable.firstIndex(of: current) else {
            setHighlighted(step > 0 ? selectable.first : selectable.last)
            return
        }
        let next = (position + step + selectable.count) % selectable.count
        setHighlighted(selectable[next])
    }

    private func setHighlighted(_ index: Int?) {
        guard highlighted != index else { return }
        if let highlighted {
            setNeedsDisplay(rowFrame(at: highlighted))
        }
        highlighted = index
        if let index {
            setNeedsDisplay(rowFrame(at: index))
        }
    }
}
