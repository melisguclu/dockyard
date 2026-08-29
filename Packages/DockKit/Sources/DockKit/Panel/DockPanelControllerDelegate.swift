import AppKit
import DockCore
import Foundation

extension DockPanelController: DockContentViewDelegate {
    public func dockContentView(_ view: DockContentView, needs extent: DockPanelExtent) {
        guard self.extent != extent else { return }
        self.extent = extent
        updatePanelFrame()
    }

    public func dockContentView(_ view: DockContentView, didActivate tile: DockTile) {
        switch tile.kind {
        case .application:
            activator.activateOrLaunch(tile)
        case .folder(let presentation):
            presentStack(for: tile, presentation: presentation)
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
        windowItemsFor tile: DockTile,
        availableHeight: CGFloat
    ) -> [DockMenuItem] {
        DockTileMenuBuilder.windowItems(
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

    public func dockContentView(_ view: DockContentView, springLoaded tile: DockTile) {
        switch tile.kind {
        case .application:
            activator.activateOrLaunch(tile)
        case .folder(let presentation):
            presentStack(for: tile, presentation: presentation)
        default:
            break
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

    public func dockContentViewAllowsReordering(_ view: DockContentView) -> Bool {
        allowsReordering
    }

    public func dockContentView(_ view: DockContentView, didReorder tiles: [DockTile]) {
        onReorder?(tiles)
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

    var iconPixelSize: Int {
        let size = snapshot.appearance.effectiveLargeSize * maximumBackingScale
        return Int(max(size.rounded(.up), 32))
    }
}
