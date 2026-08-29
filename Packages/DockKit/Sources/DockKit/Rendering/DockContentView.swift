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

    public var tiles: [DockTile] { reorderedTiles ?? snapshot.tiles }

    let tileMenu = DockTileMenuController()
    let tileLabel = DockTileLabelController()
    public private(set) var currentLayout: DockLayout = .empty

    private let backdrop = DockBackdrop()
    private let tileContainer = DockTileContainerView()
    private let tileHost = CALayer()
    var tileLayers: [DockTileID: DockTileLayer] = [:]
    var cursor: CGPoint?
    var pressedIdentifier: DockTileID?
    var dimmedIdentifier: DockTileID?
    var menuIdentifier: DockTileID?
    var labelIdentifier: DockTileID?
    var dropTargetIdentifier: DockTileID?
    private var trackingRegion: NSTrackingArea?
    var pointerInside = false
    var frameLink: CADisplayLink?
    var magnification: CGFloat = 0
    var magnificationTarget: CGFloat = 0
    var lastTick: CFTimeInterval = 0
    var appliedCursor: CGPoint?
    var appliedMagnification: CGFloat = .nan
    var settledTicks = 0
    private var appliedIndicator: CGImage?
    private var appliedBadges: [DockTileID: String] = [:]
    var panelExtent: DockPanelExtent = .resting
    var wantsMagnification = false
    var requestedLaunching: Set<DockTileID> = []
    var launchingTiles: Set<DockTileID> = []
    var appliedBounce: DockLaunchBounce?
    var launchSettleTask: Task<Void, Never>?
    var reorderIdentifier: DockTileID?
    var reorderedTiles: [DockTile]?
    var reorderPointer: CGPoint?
    var reorderGrab: CGFloat = 0.5
    var slideResiduals: [DockTileID: CGFloat] = [:]
    var appliedTileFrames: [DockTileID: CGRect] = [:]
    var pressOrigin: CGPoint?
    var exposeHoldTask: Task<Void, Never>?
    var exposeDidPresent = false
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
        rebaseReorder(with: snapshot)

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

        for tile in snapshot.tiles {
            applyBadge(to: tile)
        }
        appliedBadges = appliedBadges.filter { incoming.contains($0.key) }

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
        appliedBadges.removeAll()
        for tile in snapshot.tiles {
            requestIcon(for: tile)
            applyBadge(to: tile)
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
                tiles: tiles,
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

        appliedTileFrames.removeAll(keepingCapacity: true)
        for (index, tile) in tiles.enumerated() {
            guard index < currentLayout.tileFrames.count, let layer = tileLayers[tile.id] else { continue }
            if indicatorChanged {
                layer.setIndicator(indicator)
            }
            let frame = reorderedFrame(currentLayout.tileFrames[index], of: tile)
            appliedTileFrames[tile.id] = frame
            layer.apply(
                frame: frame,
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

    var interactiveRect: CGRect {
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
    static let rampSettleFactor: CFTimeInterval = 3
    static let rampEpsilon: CGFloat = 0.002
    static let maximumFrameDelta: CFTimeInterval = 0.1
    static let settleTicks = 12

    public func tile(with identifier: DockTileID) -> DockTile? {
        tiles.first { $0.id == identifier }
    }

    func tile(at point: CGPoint) -> DockTile? {
        guard let index = DockGeometry.hitIndex(in: currentLayout, at: point),
            index < tiles.count
        else { return nil }
        return tiles[index]
    }

    private func requestIcon(for tile: DockTile) {
        guard tile.occupiesTileSlot else { return }
        delegate?.dockContentView(self, needsIconFor: tile, pixelSize: iconPixelSize)
    }

    private func applyBadge(to tile: DockTile) {
        guard let layer = tileLayers[tile.id] else { return }
        guard appliedBadges[tile.id] != tile.badge else { return }
        guard let badge = tile.badge else {
            appliedBadges.removeValue(forKey: tile.id)
            layer.setBadge(nil, scale: 1)
            return
        }
        appliedBadges[tile.id] = badge
        let scale = window?.backingScaleFactor ?? 2
        let image = BadgeRenderer.shared.badge(text: badge, pixelDiameter: badgePixelDiameter)
        layer.setBadge(image, scale: scale)
    }

    private var badgePixelDiameter: Int {
        let scale = window?.backingScaleFactor ?? 2
        let diameter = BadgeGeometry.diameter(iconLength: snapshot.appearance.effectiveLargeSize)
        return Int(max((diameter * scale).rounded(), 1))
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
    public func screenAnchor(for identifier: DockTileID) -> CGRect? {
        guard let window,
            let index = tiles.firstIndex(where: { $0.id == identifier }),
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
