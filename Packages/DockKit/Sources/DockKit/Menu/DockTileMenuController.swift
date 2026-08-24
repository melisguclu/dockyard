import AppKit
import DockCore
import Foundation

public struct DockMenuRequest {
    public let items: [DockMenuItem]
    public let anchor: CGRect
    public let orientation: DockOrientation
    public let screen: CGRect
    public let appearance: NSAppearance?

    public init(
        items: [DockMenuItem],
        anchor: CGRect,
        orientation: DockOrientation,
        screen: CGRect,
        appearance: NSAppearance?
    ) {
        self.items = items
        self.anchor = anchor
        self.orientation = orientation
        self.screen = screen
        self.appearance = appearance
    }
}

@MainActor
public final class DockTileMenuController {
    public private(set) var isVisible = false

    let metrics: DockMenuMetrics
    private let panel: DockMenuPanel
    private let backdrop = DockMenuBackdrop()
    private var content: DockMenuContentView?
    private var monitors: [Any] = []
    private var onDismiss: (() -> Void)?

    public init(metrics: DockMenuMetrics = .current) {
        self.metrics = metrics
        panel = DockMenuPanel.make()
        panel.contentView?.addSubview(backdrop.view)
    }

    public func present(
        _ request: DockMenuRequest,
        onSelect: @escaping (DockMenuItem) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        guard !request.items.isEmpty else {
            onDismiss()
            return
        }
        dismiss()

        let contentSize = DockMenuContentView.contentSize(for: request.items, metrics: metrics)
        let balloon = DockMenuLayout.balloon(
            contentSize: contentSize,
            anchor: request.anchor,
            orientation: request.orientation,
            screen: request.screen,
            metrics: metrics
        )

        let view = DockMenuContentView(items: request.items, metrics: metrics)
        view.frame = balloon.contentFrame
        view.onSelect = { [weak self] item in
            self?.finish()
            onSelect(item)
        }
        view.onCancel = { [weak self] in
            self?.finish()
        }

        content.map { $0.removeFromSuperview() }
        content = view
        self.onDismiss = onDismiss

        panel.appearance = request.appearance
        panel.setFrame(balloon.panelFrame, display: false)
        panel.contentView?.frame = CGRect(origin: .zero, size: balloon.panelFrame.size)
        backdrop.apply(balloon: balloon, metrics: metrics)
        panel.contentView?.addSubview(view, positioned: .above, relativeTo: backdrop.view)

        panel.orderFrontRegardless()
        panel.makeKey()
        panel.makeFirstResponder(view)
        isVisible = true
        startMonitoring()
    }

    public func dismiss() {
        guard isVisible else { return }
        finish()
    }

    private func finish() {
        stopMonitoring()
        isVisible = false
        panel.orderOut(nil)
        content?.removeFromSuperview()
        content = nil
        let callback = onDismiss
        onDismiss = nil
        callback?()
    }

    private func startMonitoring() {
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]

        let outside: (NSEvent) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss() }
        }
        let inside: (NSEvent) -> NSEvent? = { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, event.window !== self.panel else { return }
                self.dismiss()
            }
            return event
        }

        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: outside) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: inside) {
            monitors.append(local)
        }
    }

    private func stopMonitoring() {
        for monitor in monitors {
            NSEvent.removeMonitor(monitor)
        }
        monitors.removeAll()
    }
}

final class DockMenuPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    static func make() -> DockMenuPanel {
        let panel = DockMenuPanel(
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
        panel.acceptsMouseMovedEvents = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.tabbingMode = .disallowed
        panel.worksWhenModal = true
        panel.contentView = NSView()
        panel.contentView?.wantsLayer = true
        return panel
    }
}
