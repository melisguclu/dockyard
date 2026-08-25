import AppKit
import DockCore
import Foundation
import QuartzCore

public struct DockTileLabelRequest {
    public let identifier: DockTileID
    public let text: String
    public let anchor: CGRect
    public let orientation: DockOrientation
    public let screen: CGRect
    public let appearance: NSAppearance?

    public init(
        identifier: DockTileID,
        text: String,
        anchor: CGRect,
        orientation: DockOrientation,
        screen: CGRect,
        appearance: NSAppearance?
    ) {
        self.identifier = identifier
        self.text = text
        self.anchor = anchor
        self.orientation = orientation
        self.screen = screen
        self.appearance = appearance
    }
}

@MainActor
public final class DockTileLabelController {
    public private(set) var identifier: DockTileID?

    private let metrics: DockTileLabelMetrics
    private let panel: DockTileLabelPanel
    private let backdrop = DockMenuBackdrop()
    private let text: DockTileLabelTextView
    private let balloonView = DockTileLabelContainerView()
    private var presentedFrame: CGRect = .zero
    private var presentedText = ""
    private var presentedTail: CGFloat = 0
    private var presentedStage: CGSize = .zero
    private var presentedOrientation: DockOrientation?
    private var presentedAppearance: NSAppearance?
    private var measuredText = ""
    private var measuredWidth: CGFloat = 0

    public init(metrics: DockTileLabelMetrics = .current) {
        self.metrics = metrics
        panel = DockTileLabelPanel.make()
        text = DockTileLabelTextView(metrics: metrics)
        balloonView.wantsLayer = true
        balloonView.layer?.masksToBounds = false
        balloonView.addSubview(backdrop.view)
        balloonView.addSubview(text, positioned: .above, relativeTo: backdrop.view)
        panel.contentView?.addSubview(balloonView)
    }

    public func present(_ request: DockTileLabelRequest) {
        guard !request.text.isEmpty else {
            dismiss()
            return
        }

        let balloon = DockTileLabelLayout.balloon(
            width: width(of: request.text),
            anchor: request.anchor,
            orientation: request.orientation,
            screen: request.screen,
            metrics: metrics
        )
        guard balloon.panelFrame != presentedFrame || request.text != presentedText else {
            identifier = request.identifier
            return
        }

        let reshaped =
            balloon.panelFrame.size != presentedFrame.size
            || balloon.tailAlong != presentedTail
            || request.orientation != presentedOrientation
            || request.text != presentedText

        identifier = request.identifier
        presentedFrame = balloon.panelFrame
        presentedText = request.text
        presentedTail = balloon.tailAlong
        presentedOrientation = request.orientation

        if request.appearance !== presentedAppearance {
            presentedAppearance = request.appearance
            panel.appearance = request.appearance
        }

        let stage = stageSize(for: request.orientation)
        let inset = CGPoint(
            x: ((stage.width - balloon.panelFrame.width) / 2).rounded(),
            y: ((stage.height - balloon.panelFrame.height) / 2).rounded()
        )
        let origin = CGPoint(x: balloon.panelFrame.minX - inset.x, y: balloon.panelFrame.minY - inset.y)

        if stage == presentedStage {
            panel.setFrameOrigin(origin)
        } else {
            presentedStage = stage
            panel.setFrame(CGRect(origin: origin, size: stage), display: false)
            panel.contentView?.frame = CGRect(origin: .zero, size: stage)
        }

        guard reshaped else { return }

        let bounds = CGRect(origin: .zero, size: balloon.panelFrame.size)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        balloonView.frame = CGRect(origin: inset, size: balloon.panelFrame.size)
        backdrop.apply(
            path: DockMenuLayout.path(for: balloon, metrics: metrics.balloon),
            bounds: bounds
        )
        text.frame = balloon.contentFrame
        CATransaction.commit()
        text.setText(request.text)
        panel.invalidateShadow()

        guard !panel.isVisible else { return }
        panel.orderFrontRegardless()
    }

    private func stageSize(for orientation: DockOrientation) -> CGSize {
        let body = metrics.maximumWidth
        let tail = metrics.balloon.tailLength
        switch orientation {
        case .bottom:
            return CGSize(width: body, height: metrics.height + tail)
        case .left, .right:
            return CGSize(width: body + tail, height: metrics.height)
        }
    }

    private func width(of text: String) -> CGFloat {
        guard text != measuredText else { return measuredWidth }
        measuredText = text
        measuredWidth = DockTileLabelLayout.width(
            textWidth: DockTileLabelTextView.width(of: text, metrics: metrics),
            metrics: metrics
        )
        return measuredWidth
    }

    public func dismiss() {
        guard identifier != nil else { return }
        identifier = nil
        presentedFrame = .zero
        presentedText = ""
        presentedOrientation = nil
        panel.orderOut(nil)
    }
}

final class DockTileLabelTextView: NSView {
    private let metrics: DockTileLabelMetrics
    private var text = ""

    init(metrics: DockTileLabelMetrics) {
        self.metrics = metrics
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    static func font(_ metrics: DockTileLabelMetrics) -> NSFont {
        .systemFont(ofSize: metrics.fontSize)
    }

    static func width(of text: String, metrics: DockTileLabelMetrics) -> CGFloat {
        (text as NSString).size(withAttributes: [.font: font(metrics)]).width
    }

    func setText(_ value: String) {
        guard text != value else { return }
        text = value
        needsDisplay = true
    }

    override var isFlipped: Bool { false }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draw(_ dirtyRect: NSRect) {
        let font = Self.font(metrics)
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byTruncatingTail
        paragraph.alignment = .center
        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph,
        ]
        let baseline = bounds.midY - font.capHeight / 2
        let line = CGRect(
            x: metrics.textInset,
            y: baseline + font.descender,
            width: max(bounds.width - 2 * metrics.textInset, 0),
            height: NSLayoutManager().defaultLineHeight(for: font)
        )
        (text as NSString).draw(in: line, withAttributes: attributes)
    }
}

final class DockTileLabelContainerView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var isOpaque: Bool { false }
}

final class DockTileLabelPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    static func make() -> DockTileLabelPanel {
        let panel = DockTileLabelPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.ignoresMouseEvents = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.tabbingMode = .disallowed
        panel.worksWhenModal = true
        panel.contentView = NSView()
        panel.contentView?.wantsLayer = true
        return panel
    }
}
