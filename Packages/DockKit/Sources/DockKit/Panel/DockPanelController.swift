import AppKit
import DockCore
import Foundation

@MainActor
public final class DockPanelController: NSObject, DockContentViewDelegate {
    public let identity: DisplayIdentity
    public private(set) var displayID: CGDirectDisplayID
    public private(set) var isVisible = false

    private let panel: DockPanel
    private let contentView: DockContentView
    private let iconProvider: IconProvider
    private let activator = ApplicationActivator()

    private var screenFrame: CGRect = .zero
    private var maximumBackingScale: CGFloat = 2
    private var snapshot: DockSnapshot = .empty
    private var iconTasks: [DockTileID: Task<Void, Never>] = [:]

    public init(
        identity: DisplayIdentity,
        displayID: CGDirectDisplayID,
        iconProvider: IconProvider,
        metrics: DockMetrics = .current
    ) {
        self.identity = identity
        self.displayID = displayID
        self.iconProvider = iconProvider
        panel = DockPanel.make()
        contentView = DockContentView(frame: .zero)
        contentView.metrics = metrics
        super.init()
        contentView.delegate = self
        panel.contentView = contentView
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
        reservedStrip: CGFloat?
    ) {
        self.displayID = displayID
        let scaleChanged = maximumBackingScale != self.maximumBackingScale
        self.maximumBackingScale = maximumBackingScale
        screenFrame = screen.frame
        contentView.reservedStrip = reservedStrip
        updatePanelFrame()
        if scaleChanged {
            contentView.iconPixelSize = iconPixelSize
            contentView.refreshIcons()
        }
    }

    public func apply(_ snapshot: DockSnapshot) {
        let appearanceChanged = snapshot.appearance != self.snapshot.appearance
        self.snapshot = snapshot
        contentView.iconPixelSize = iconPixelSize
        if appearanceChanged {
            updatePanelFrame()
        }
        contentView.apply(snapshot)
    }

    public func refreshIcons() {
        contentView.refreshIcons()
    }

    public func show() {
        guard !isVisible else { return }
        isVisible = true
        panel.orderFrontRegardless()
    }

    public func hide() {
        guard isVisible else { return }
        isVisible = false
        panel.orderOut(nil)
    }

    public func tearDown() {
        for task in iconTasks.values {
            task.cancel()
        }
        iconTasks.removeAll()
        contentView.delegate = nil
        panel.orderOut(nil)
        panel.contentView = nil
        isVisible = false
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
        case .separator, .spacer:
            break
        }
    }

    public func dockContentView(_ view: DockContentView, menuFor tile: DockTile) -> NSMenu? {
        DockTileMenuBuilder.menu(for: tile, target: self, action: #selector(performMenuCommand(_:)))
    }

    public func dockContentView(_ view: DockContentView, didDrop urls: [URL], on tile: DockTile) {
        guard case .application = tile.kind, let applicationURL = tile.url else { return }
        activator.open(urls: urls, withApplicationAt: applicationURL)
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

    @objc private func performMenuCommand(_ sender: NSMenuItem) {
        guard let box = sender.representedObject as? DockTileMenuCommandBox else { return }
        switch box.command {
        case .activate:
            activator.activateOrLaunch(box.tile)
        case .showInFinder:
            guard let url = box.tile.url else { return }
            activator.reveal(url)
        case .hide:
            activator.hide(box.tile)
        case .unhide:
            activator.unhide(box.tile)
        case .quit:
            activator.quit(box.tile)
        case .forceQuit:
            activator.forceQuit(box.tile)
        case .open:
            guard let url = box.tile.url else { return }
            activator.open(url)
        }
    }

    private var iconPixelSize: Int {
        let size = snapshot.appearance.effectiveLargeSize * maximumBackingScale
        return Int(max(size.rounded(.up), 32))
    }

    private func updatePanelFrame() {
        guard !screenFrame.isEmpty else { return }
        let frame = DockGeometry.panelFrame(
            screenFrame: screenFrame,
            appearance: snapshot.appearance,
            metrics: contentView.metrics,
            reservedStrip: contentView.reservedStrip
        )
        panel.setFrame(frame, display: false)
        contentView.frame = CGRect(origin: .zero, size: frame.size)
        contentView.relayout(animated: false)
    }
}
