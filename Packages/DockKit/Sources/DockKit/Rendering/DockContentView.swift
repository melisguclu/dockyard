import AppKit
import DockCore
import Foundation
import QuartzCore

@MainActor
public protocol DockContentViewDelegate: AnyObject {
    func dockContentView(_ view: DockContentView, didActivate tile: DockTile)
    func dockContentView(_ view: DockContentView, menuFor tile: DockTile) -> NSMenu?
    func dockContentView(_ view: DockContentView, didDrop urls: [URL], on tile: DockTile)
    func dockContentView(_ view: DockContentView, needsIconFor tile: DockTile, pixelSize: Int)
}

public final class DockContentView: NSView {
    public weak var delegate: DockContentViewDelegate?
    public var metrics: DockMetrics = .current
    public var iconPixelSize: Int = 256
    public var reservedStrip: CGFloat?

    public private(set) var snapshot: DockSnapshot = .empty
    public private(set) var currentLayout: DockLayout = .empty

    private let backdrop = DockBackdrop()
    private let tileContainer = DockTileContainerView()
    private let tileHost = CALayer()
    private var tileLayers: [DockTileID: DockTileLayer] = [:]
    private var cursor: CGPoint?
    private var pressedIdentifier: DockTileID?
    private var dropTargetIdentifier: DockTileID?
    private var trackingRegion: NSTrackingArea?
    private var frameLink: CADisplayLink?
    private var magnification: CGFloat = 0
    private var magnificationTarget: CGFloat = 0
    private var lastTick: CFTimeInterval = 0
    private var appliedCursor: CGPoint?
    private var appliedMagnification: CGFloat = .nan
    private var settledTicks = 0
    private var appliedIndicator: CGImage?

    override public init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configure()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        configure()
    }

    override public var isFlipped: Bool { false }

    override public var isOpaque: Bool { false }

    private func configure() {
        wantsLayer = true
        layerContentsRedrawPolicy = .onSetNeedsDisplay
        layer?.backgroundColor = NSColor.clear.cgColor

        addSubview(backdrop.view)

        tileContainer.wantsLayer = true
        tileContainer.layerContentsRedrawPolicy = .never
        tileContainer.autoresizingMask = []
        addSubview(tileContainer, positioned: .above, relativeTo: backdrop.view)

        tileHost.masksToBounds = false
        tileContainer.layer?.masksToBounds = false
        backdrop.borderLayer.borderWidth = metrics.borderWidth
        tileContainer.layer?.addSublayer(backdrop.borderLayer)
        tileContainer.layer?.addSublayer(tileHost)

        registerForDraggedTypes([.fileURL])
    }

    public func apply(_ snapshot: DockSnapshot) {
        let previous = self.snapshot
        self.snapshot = snapshot

        let incoming = Set(snapshot.tiles.map(\.id))
        for (identifier, layer) in tileLayers where !incoming.contains(identifier) {
            layer.container.removeFromSuperlayer()
            tileLayers.removeValue(forKey: identifier)
        }

        for tile in snapshot.tiles {
            if let existing = tileLayers[tile.id] {
                existing.update(with: tile, showsIndicator: snapshot.appearance.showProcessIndicators)
            } else {
                let layer = DockTileLayer(tile: tile)
                layer.update(with: tile, showsIndicator: snapshot.appearance.showProcessIndicators)
                tileLayers[tile.id] = layer
                tileHost.addSublayer(layer.container)
                appliedIndicator = nil
                requestIcon(for: tile)
            }
        }

        for tile in snapshot.tiles where iconNeedsRefresh(tile, previous: previous) {
            requestIcon(for: tile)
        }

        if !magnificationAvailable {
            magnificationTarget = 0
        }

        relayout()
    }

    public func setIcon(_ image: CGImage?, for identifier: DockTileID) {
        guard let layer = tileLayers[identifier] else { return }
        layer.setIcon(image, scale: window?.backingScaleFactor ?? 2)
    }

    public func refreshIcons() {
        for tile in snapshot.tiles {
            requestIcon(for: tile)
        }
    }

    public func relayout() {
        let state = DockLog.signposts.beginInterval("panel-layout")
        defer { DockLog.signposts.endInterval("panel-layout", state) }

        currentLayout = DockGeometry.layout(
            DockLayoutInput(
                tiles: snapshot.tiles,
                appearance: snapshot.appearance,
                metrics: metrics,
                panelSize: bounds.size,
                cursor: cursor,
                magnificationAmount: magnification,
                reservedStrip: reservedStrip
            )
        )

        let indicator = IndicatorRenderer.shared.indicator(
            diameter: currentLayout.indicatorDiameter,
            scale: window?.backingScaleFactor ?? 2,
            isDark: isDarkAppearance
        )
        let indicatorChanged = indicator !== appliedIndicator
        appliedIndicator = indicator

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        backdrop.apply(
            bounds: bounds,
            barRect: currentLayout.barRect,
            cornerRadius: currentLayout.cornerRadius
        )

        tileContainer.frame = bounds
        tileHost.frame = bounds

        for (index, tile) in snapshot.tiles.enumerated() {
            guard index < currentLayout.tileFrames.count, let layer = tileLayers[tile.id] else { continue }
            if indicatorChanged {
                layer.setIndicator(indicator)
            }
            layer.apply(
                frame: currentLayout.tileFrames[index],
                indicatorDiameter: currentLayout.indicatorDiameter,
                indicatorInset: currentLayout.indicatorInset,
                orientation: snapshot.appearance.orientation
            )
        }

        CATransaction.commit()

        appliedCursor = cursor
        appliedMagnification = magnification
    }

    override public func layout() {
        super.layout()
        relayout()
        updateTrackingAreas()
    }

    override public func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            stopFrameLink()
            magnification = 0
            magnificationTarget = 0
            cursor = nil
        }
    }

    override public func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        IndicatorRenderer.shared.invalidate()
        relayout()
    }

    override public func updateTrackingAreas() {
        super.updateTrackingAreas()
        guard trackingRegion?.rect != bounds else { return }
        if let trackingRegion {
            removeTrackingArea(trackingRegion)
        }
        guard !bounds.isEmpty else {
            trackingRegion = nil
            return
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

    override public func hitTest(_ point: NSPoint) -> NSView? {
        let local = convert(point, from: superview)
        guard interactiveRect.contains(local) else { return nil }
        return self
    }

    override public func mouseEntered(with event: NSEvent) {
        startFrameLink()
    }

    override public func mouseMoved(with event: NSEvent) {
        startFrameLink()
    }

    override public func mouseExited(with event: NSEvent) {
        magnificationTarget = 0
        startFrameLink()
    }

    override public func mouseDown(with event: NSEvent) {
        pressedIdentifier = tile(at: location(of: event))?.id
    }

    override public func mouseUp(with event: NSEvent) {
        defer { pressedIdentifier = nil }
        guard let tile = tile(at: location(of: event)), tile.id == pressedIdentifier else { return }
        guard tile.isInteractive else { return }
        delegate?.dockContentView(self, didActivate: tile)
    }

    override public func rightMouseDown(with event: NSEvent) {
        let point = location(of: event)
        guard let index = DockGeometry.hitIndex(in: currentLayout, at: point),
            index < snapshot.tiles.count
        else { return }

        let tile = snapshot.tiles[index]
        guard tile.isInteractive, let menu = delegate?.dockContentView(self, menuFor: tile) else { return }

        let frame = currentLayout.tileFrames[index]
        let width = menu.size.width
        let anchor = CGPoint(
            x: min(max(frame.midX - width / 2, bounds.minX + 4), max(bounds.maxX - width - 4, bounds.minX + 4)),
            y: frame.maxY + Self.contextMenuGap
        )
        menu.popUp(positioning: nil, at: anchor, in: self)
    }

    private static let contextMenuGap: CGFloat = 6

    private var isDarkAppearance: Bool {
        effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    private var interactiveRect: CGRect {
        guard !currentLayout.barRect.isEmpty else { return .zero }
        return currentLayout.tileFrames.reduce(currentLayout.barRect) { $0.union($1) }
    }

    private func location(of event: NSEvent) -> CGPoint {
        convert(event.locationInWindow, from: nil)
    }

    private var magnificationAvailable: Bool {
        snapshot.appearance.magnificationEnabled
            && snapshot.appearance.effectiveLargeSize > snapshot.appearance.tileSize
    }

    private func startFrameLink() {
        guard frameLink == nil, magnificationAvailable, window != nil else { return }
        let link = displayLink(target: self, selector: #selector(stepFrame(_:)))
        link.add(to: .main, forMode: .common)
        lastTick = CACurrentMediaTime()
        frameLink = link
    }

    private func stopFrameLink() {
        frameLink?.invalidate()
        frameLink = nil
        settledTicks = 0
    }

    @objc private func stepFrame(_ link: CADisplayLink) {
        let now = CACurrentMediaTime()
        let delta = (now - lastTick).clamped(to: 0...Self.maximumFrameDelta)
        lastTick = now

        if magnificationAvailable, let point = pointerLocation(), interactiveRect.contains(point) {
            cursor = point
            magnificationTarget = 1
        } else {
            magnificationTarget = 0
        }

        let constant =
            magnificationTarget > magnification
            ? Self.enterRampDuration / Self.rampSettleFactor
            : Self.exitRampDuration / Self.rampSettleFactor
        magnification += (magnificationTarget - magnification) * (1 - exp(-delta / constant))
        if abs(magnificationTarget - magnification) < Self.rampEpsilon {
            magnification = magnificationTarget
        }

        if magnification == 0, magnificationTarget == 0 {
            cursor = nil
            stopFrameLink()
        }

        guard cursor != appliedCursor || magnification != appliedMagnification else {
            settledTicks += 1
            if settledTicks >= Self.settleTicks {
                stopFrameLink()
            }
            return
        }

        settledTicks = 0
        relayout()
    }

    private func pointerLocation() -> CGPoint? {
        guard let window else { return nil }
        return convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
    }

    public static let enterRampDuration: CFTimeInterval = 0.20
    public static let exitRampDuration: CFTimeInterval = 0.16
    private static let rampSettleFactor: CFTimeInterval = 3
    private static let rampEpsilon: CGFloat = 0.002
    private static let maximumFrameDelta: CFTimeInterval = 0.1
    private static let settleTicks = 12

    private func tile(at point: CGPoint) -> DockTile? {
        guard let index = DockGeometry.hitIndex(in: currentLayout, at: point),
            index < snapshot.tiles.count
        else { return nil }
        return snapshot.tiles[index]
    }

    private func requestIcon(for tile: DockTile) {
        guard tile.occupiesTileSlot else { return }
        delegate?.dockContentView(self, needsIconFor: tile, pixelSize: iconPixelSize)
    }

    private func iconNeedsRefresh(_ tile: DockTile, previous: DockSnapshot) -> Bool {
        guard let old = previous.tile(with: tile.id) else { return false }
        if case .trash(let wasEmpty) = old.kind, case .trash(let isEmpty) = tile.kind {
            return wasEmpty != isEmpty
        }
        return old.url != tile.url
    }

}

extension DockContentView {
    override public func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        dragOperation(for: sender)
    }

    override public func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        dragOperation(for: sender)
    }

    override public func draggingExited(_ sender: (any NSDraggingInfo)?) {
        setDropTarget(nil)
    }

    override public func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        defer { setDropTarget(nil) }
        guard let identifier = dropTargetIdentifier,
            let tile = snapshot.tile(with: identifier),
            let urls = fileURLs(from: sender), !urls.isEmpty
        else { return false }
        delegate?.dockContentView(self, didDrop: urls, on: tile)
        return true
    }

    private func dragOperation(for sender: any NSDraggingInfo) -> NSDragOperation {
        let point = convert(sender.draggingLocation, from: nil)
        guard let tile = tile(at: point), canAcceptDrop(on: tile) else {
            setDropTarget(nil)
            return []
        }
        setDropTarget(tile.id)
        return .copy
    }

    private func canAcceptDrop(on tile: DockTile) -> Bool {
        switch tile.kind {
        case .application:
            return true
        default:
            return false
        }
    }

    private func setDropTarget(_ identifier: DockTileID?) {
        guard dropTargetIdentifier != identifier else { return }
        if let previous = dropTargetIdentifier {
            tileLayers[previous]?.setHighlighted(false)
        }
        dropTargetIdentifier = identifier
        if let identifier {
            tileLayers[identifier]?.setHighlighted(true)
        }
    }

    private func fileURLs(from sender: any NSDraggingInfo) -> [URL]? {
        sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL]
    }

}

final class DockTileContainerView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override var isOpaque: Bool { false }
}
