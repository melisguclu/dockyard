import AppKit
import DockCore
import Foundation

@MainActor
public final class DockPanelController: NSObject, DockContentViewDelegate {
    public let identity: DisplayIdentity
    public private(set) var displayID: CGDirectDisplayID
    public private(set) var isVisible = false
    public var onTrashChanged: (@MainActor () -> Void)?
    public var revealState: DockRevealState { reveal.state }

    private let panel: DockPanel
    private let contentView: DockContentView
    private let reveal: DockRevealController
    private let iconProvider: IconProvider
    private let appMenuStore: AppMenuStore?
    private let minimizedWindowStore: MinimizedWindowStore?
    private let activator = ApplicationActivator()

    private var screenFrame: CGRect = .zero
    private var extent: DockPanelExtent = .resting
    private var maximumBackingScale: CGFloat = 2
    private var requested: DockSnapshot = .empty
    private var snapshot: DockSnapshot = .empty
    private var iconTasks: [DockTileID: Task<Void, Never>] = [:]

    public init(
        identity: DisplayIdentity,
        displayID: CGDirectDisplayID,
        iconProvider: IconProvider,
        appMenuStore: AppMenuStore? = nil,
        minimizedWindowStore: MinimizedWindowStore? = nil,
        metrics: DockMetrics = .current
    ) {
        self.identity = identity
        self.displayID = displayID
        self.iconProvider = iconProvider
        self.appMenuStore = appMenuStore
        self.minimizedWindowStore = minimizedWindowStore
        panel = DockPanel.make()
        contentView = DockContentView(frame: .zero)
        contentView.metrics = metrics
        reveal = DockRevealController(panel: panel)
        super.init()
        contentView.delegate = self
        panel.contentView = contentView
        reveal.applyFrame = { [weak self] frame in self?.seat(frame) }
        reveal.didReveal = { [weak self] in self?.contentView.refreshPointerPresence() }
        reveal.didHide = { [weak self] in self?.contentView.stopMagnifying() }
    }

    deinit {
        for task in iconTasks.values {
            task.cancel()
        }
    }

    public func bind(
        to screen: NSScreen,
        displayID: CGDirectDisplayID,
        maximumBackingScale: CGFloat,
        measuredEdgeMargin: CGFloat?
    ) {
        self.displayID = displayID
        let scaleChanged = maximumBackingScale != self.maximumBackingScale
        self.maximumBackingScale = maximumBackingScale
        let frameChanged = screen.frame != screenFrame
        screenFrame = screen.frame
        contentView.measuredEdgeMargin = measuredEdgeMargin
        if frameChanged, fitted(requested) != snapshot {
            apply(requested)
        } else {
            updatePanelFrame()
        }
        if scaleChanged {
            contentView.iconPixelSize = iconPixelSize
            contentView.refreshIcons()
        }
    }

    public func apply(_ snapshot: DockSnapshot) {
        requested = snapshot
        let fitted = fitted(snapshot)
        self.snapshot = fitted
        contentView.iconPixelSize = iconPixelSize
        updatePanelFrame()
        contentView.apply(fitted)
    }

    private func fitted(_ snapshot: DockSnapshot) -> DockSnapshot {
        guard !screenFrame.isEmpty else { return snapshot }
        let appearance = snapshot.appearance
        let available = appearance.orientation.isVertical ? screenFrame.height : screenFrame.width
        let tileSize = DockGeometry.fittedTileSize(
            tiles: snapshot.tiles,
            appearance: appearance,
            metrics: contentView.metrics,
            available: available
        )
        guard tileSize != appearance.tileSize else { return snapshot }
        return snapshot.withAppearance(appearance.withTileSize(tileSize))
    }

    public func refreshIcons() {
        contentView.refreshIcons()
    }

    public func setCoveredByFullScreen(_ covered: Bool) {
        reveal.setCoveredByFullScreen(covered)
    }

    public func setLaunching(_ identifiers: Set<DockTileID>) {
        contentView.setLaunching(identifiers)
    }

    public func setAccessibilityAppearance(_ value: DockAccessibilityAppearance) {
        contentView.accessibilityAppearance = value
    }

    public func show() {
        guard !isVisible else { return }
        isVisible = true
        panel.orderFrontRegardless()
        reveal.setVisible(true)
    }

    public func hide() {
        guard isVisible else { return }
        isVisible = false
        reveal.setVisible(false)
        contentView.stopMagnifying()
        contentView.dismissTileLabel()
        panel.orderOut(nil)
    }

    public func tearDown() {
        reveal.tearDown()
        for task in iconTasks.values {
            task.cancel()
        }
        iconTasks.removeAll()
        contentView.stopMagnifying()
        contentView.dismissTileLabel()
        contentView.delegate = nil
        panel.orderOut(nil)
        panel.contentView = nil
        isVisible = false
    }

    public func dockContentView(_ view: DockContentView, needs extent: DockPanelExtent) {
        guard self.extent != extent else { return }
        self.extent = extent
        updatePanelFrame()
    }

    public func dockContentView(_ view: DockContentView, didActivate tile: DockTile) {
        switch tile.kind {
        case .application:
            activator.activateOrLaunch(tile)
        case .folder:
            guard let url = tile.url else { return }
            activator.openFolder(url)
        case .url:
            guard let url = tile.url else { return }
            activator.open(url)
        case .trash:
            activator.openTrash()
        case .minimizedWindow:
            minimizedWindowStore?.restore(tile.id)
        case .separator, .spacer:
            break
        }
    }

    public func dockContentView(
        _ view: DockContentView,
        menuItemsFor tile: DockTile,
        availableHeight: CGFloat
    ) -> [DockMenuItem] {
        DockTileMenuBuilder.items(
            for: tile,
            appMenu: appMenuStore?.snapshot(for: tile),
            availableHeight: availableHeight
        )
    }

    public func dockContentView(
        _ view: DockContentView,
        didSelect command: DockTileMenuCommand,
        on tile: DockTile
    ) {
        switch command {
        case .activate:
            activate(tile)
        case .showInFinder:
            guard let url = tile.url else { return }
            activator.reveal(url)
        case .hide:
            activator.hide(tile)
        case .unhide:
            activator.unhide(tile)
        case .quit:
            activator.quit(tile)
        case .forceQuit:
            activator.forceQuit(tile)
        case .open:
            guard let url = tile.url else { return }
            activator.open(url)
        case .dockSettings:
            activator.openDockSettings()
        case .appMenu(let command):
            appMenuStore?.perform(command, on: tile)
        case .window(let window):
            appMenuStore?.activate(window, on: tile)
        }
    }

    private func activate(_ tile: DockTile) {
        if case .minimizedWindow = tile.kind {
            minimizedWindowStore?.restore(tile.id)
        } else {
            activator.activateOrLaunch(tile)
        }
    }

    public func dockContentView(_ view: DockContentView, didDrop urls: [URL], on tile: DockTile) {
        switch tile.kind {
        case .application:
            guard let applicationURL = tile.url else { return }
            activator.open(urls: urls, withApplicationAt: applicationURL)
        case .trash:
            guard activator.moveToTrash(urls) else { return }
            onTrashChanged?()
        default:
            break
        }
    }

    public func dockContentViewPointerDidLeave(_ view: DockContentView) {
        contentView.dismissTileLabel()
        reveal.pointerDidLeave()
    }

    public func dockContentView(_ view: DockContentView, needsIconFor tile: DockTile, pixelSize: Int) {
        iconTasks[tile.id]?.cancel()
        let request = IconRequest(tile: tile, pixelSize: pixelSize)
        let provider = iconProvider
        let identifier = tile.id
        iconTasks[tile.id] = Task { @MainActor [weak self] in
            let image = await provider.image(for: request)
            guard !Task.isCancelled, let self else { return }
            self.contentView.setIcon(image, for: identifier)
            self.iconTasks[identifier] = nil
        }
    }

    private var iconPixelSize: Int {
        let size = snapshot.appearance.effectiveLargeSize * maximumBackingScale
        return Int(max(size.rounded(.up), 32))
    }

    private func updatePanelFrame() {
        guard !screenFrame.isEmpty else { return }
        reveal.update(
            appearance: snapshot.appearance,
            screenFrame: screenFrame,
            revealedFrame: DockGeometry.panelFrame(
                screenFrame: screenFrame,
                tiles: snapshot.tiles,
                appearance: snapshot.appearance,
                metrics: contentView.metrics,
                measuredEdgeMargin: contentView.measuredEdgeMargin,
                extent: extent
            )
        )
    }

    private func seat(_ frame: CGRect) {
        guard frame != panel.frame else { return }
        panel.setFrame(frame, display: false)
        contentView.frame = CGRect(origin: .zero, size: frame.size)
        contentView.relayout()
    }
}
