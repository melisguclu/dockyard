import AppKit
import DockCore
import Foundation
import QuartzCore

public final class DockContentView: NSView {
    public weak var delegate: DockContentViewDelegate?
    public var metrics: DockMetrics = .current
    public var iconPixelSize: Int = 256
    public var measuredEdgeMargin: CGFloat?
    public var accessibilityAppearance: DockAccessibilityAppearance = .current {
        didSet {
            guard accessibilityAppearance != oldValue else { return }
            relayout()
        }
    }

    public private(set) var snapshot: DockSnapshot = .empty

    let tileMenu = DockTileMenuController()
    let tileLabel = DockTileLabelController()
    public private(set) var currentLayout: DockLayout = .empty

    private let backdrop = DockBackdrop()
    private let tileContainer = DockTileContainerView()
    private let tileHost = CALayer()
    var tileLayers: [DockTileID: DockTileLayer] = [:]
    var cursor: CGPoint?
    private var pressedIdentifier: DockTileID?
    private var dimmedIdentifier: DockTileID?
    var menuIdentifier: DockTileID?
    var labelIdentifier: DockTileID?
    var dropTargetIdentifier: DockTileID?
    private var trackingRegion: NSTrackingArea?
    private var pointerInside = false
    private var frameLink: CADisplayLink?
    private var magnification: CGFloat = 0
    var magnificationTarget: CGFloat = 0
    private var lastTick: CFTimeInterval = 0
    private var appliedCursor: CGPoint?
    private var appliedMagnification: CGFloat = .nan
    private var settledTicks = 0
    private var appliedIndicator: CGImage?
    var panelExtent: DockPanelExtent = .resting
    var wantsMagnification = false
    var requestedLaunching: Set<DockTileID> = []
    var launchingTiles: Set<DockTileID> = []
    var appliedBounce: DockLaunchBounce?
    var launchSettleTask: Task<Void, Never>?
    var springIdentifier: DockTileID?
    var springTask: Task<Void, Never>?
    var keyboardIdentifier: DockTileID?
    var wantsKeyboardFocus = false
    var typeSelect = ""
    var typeSelectTask: Task<Void, Never>?
    var accessibilityProxies: [DockTileID: DockTileAccessibilityElement] = [:]
    var accessibilityProxiesAreLive = false
    public var onKeyboardFocusEnded: (@MainActor () -> Void)?

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
        tileContainer.layer?.addSublayer(backdrop.fillLayer)
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
        refreshLaunchAnimations()

        if labelIdentifier != nil {
            updateTileLabel(at: pointerLocation())
        }
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
        performLayout()
        refreshAccessibilityProxies()
    }

    private func performLayout() {
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
                measuredEdgeMargin: measuredEdgeMargin
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

        backdrop.setAccessibility(accessibilityAppearance, appearance: effectiveAppearance)
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
            stopMagnifying()
            dismissTileLabel()
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
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .assumeInside],
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

    private var isDarkAppearance: Bool {
        effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    private var interactiveRect: CGRect {
        guard !currentLayout.barRect.isEmpty else { return .zero }
        return currentLayout.tileFrames.reduce(currentLayout.barRect) { $0.union($1) }
    }

    func location(of event: NSEvent) -> CGPoint {
        convert(event.locationInWindow, from: nil)
    }

    var magnificationAvailable: Bool {
        snapshot.appearance.magnificationEnabled
            && snapshot.appearance.effectiveLargeSize > snapshot.appearance.tileSize
    }

    public static let enterRampDuration: CFTimeInterval = 0.20
    public static let exitRampDuration: CFTimeInterval = 0.16
    private static let rampSettleFactor: CFTimeInterval = 3
    private static let rampEpsilon: CGFloat = 0.002
    private static let maximumFrameDelta: CFTimeInterval = 0.1
    private static let settleTicks = 12

    func tile(at point: CGPoint) -> DockTile? {
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
    override public func mouseEntered(with event: NSEvent) {
        updatePointerPresence(true)
        startFrameLink()
    }

    override public func mouseMoved(with event: NSEvent) {
        updatePointerPresence(true)
        startFrameLink()
    }

    override public func mouseExited(with event: NSEvent) {
        magnificationTarget = 0
        dismissTileLabel()
        updatePointerPresence(false)
        startFrameLink()
    }

    public func refreshPointerPresence() {
        let pointer = pointerLocation()
        guard let pointer, bounds.contains(pointer) else {
            pointerInside = false
            delegate?.dockContentViewPointerDidLeave(self)
            return
        }
        pointerInside = true
        startFrameLink()
    }

    private func updatePointerPresence(_ inside: Bool) {
        guard menuIdentifier == nil, dropTargetIdentifier == nil else { return }
        guard pointerInside != inside else { return }
        pointerInside = inside
        guard !inside else { return }
        delegate?.dockContentViewPointerDidLeave(self)
    }

    override public func mouseDown(with event: NSEvent) {
        let tile = tile(at: location(of: event))
        pressedIdentifier = tile?.isInteractive == true ? tile?.id : nil
        setPressed(pressedIdentifier)
    }

    override public func mouseDragged(with event: NSEvent) {
        guard let pressedIdentifier else { return }
        let stillInside = tile(at: location(of: event))?.id == pressedIdentifier
        setPressed(stillInside ? pressedIdentifier : nil)
    }

    override public func mouseUp(with event: NSEvent) {
        defer {
            pressedIdentifier = nil
            setPressed(nil)
        }
        guard let tile = tile(at: location(of: event)), tile.id == pressedIdentifier else { return }
        guard tile.isInteractive else { return }
        delegate?.dockContentView(self, didActivate: tile)
    }

    func setPressed(_ identifier: DockTileID?) {
        guard dimmedIdentifier != identifier else { return }
        if let previous = dimmedIdentifier {
            tileLayers[previous]?.setPressed(false)
        }
        dimmedIdentifier = identifier
        if let identifier {
            tileLayers[identifier]?.setPressed(true)
        }
    }

    public func stopMagnifying() {
        magnification = 0
        magnificationTarget = 0
        cursor = nil
        stopFrameLink()
    }

    func startFrameLink() {
        guard frameLink == nil, window != nil else { return }
        let link = displayLink(target: self, selector: #selector(stepFrame(_:)))
        link.add(to: .main, forMode: .common)
        lastTick = CACurrentMediaTime()
        frameLink = link
    }

    private func stopFrameLink() {
        frameLink?.invalidate()
        frameLink = nil
        settledTicks = 0
        guard magnification == 0, magnificationTarget == 0, menuIdentifier == nil else { return }
        requestMagnification(false)
    }

    @objc private func stepFrame(_ link: CADisplayLink) {
        let now = CACurrentMediaTime()
        let delta = (now - lastTick).clamped(to: 0...Self.maximumFrameDelta)
        lastTick = now

        var pointer = pointerLocation()
        let hovering = pointer.map(interactiveRect.contains) ?? false
        updatePointerPresence(pointer.map(bounds.contains) ?? false)

        if menuIdentifier != nil {
            magnificationTarget = 1
        } else if magnificationAvailable, hovering {
            if requestMagnification(true) {
                pointer = pointerLocation()
            }
            cursor = pointer
            magnificationTarget = 1
        } else {
            magnificationTarget = 0
        }

        updateTileLabel(at: hovering ? pointer : nil)

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

    func pointerLocation() -> CGPoint? {
        guard let window else { return nil }
        return convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
    }

}

extension DockContentView {
    public func screenAnchor(for identifier: DockTileID) -> CGRect? {
        guard let window,
            let index = snapshot.tiles.firstIndex(where: { $0.id == identifier }),
            index < currentLayout.tileFrames.count
        else { return nil }
        return window.convertToScreen(convert(currentLayout.tileFrames[index], to: nil))
    }

    public var hostScreenFrame: CGRect {
        window?.screen?.visibleFrame ?? window?.frame ?? .zero
    }

    public func holdTileSession(for identifier: DockTileID) {
        beginMenuSession(for: identifier, at: pointerLocation() ?? .zero)
    }

    public func releaseTileSession() {
        guard menuIdentifier != nil else { return }
        endMenuSession()
    }
}
