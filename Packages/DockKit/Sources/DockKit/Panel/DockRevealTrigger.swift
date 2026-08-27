import AppKit
import DockCore
import Foundation

final class DockRevealTriggerView: NSView {
    var onEnter: (@MainActor () -> Void)?
    var onExit: (@MainActor () -> Void)?

    private var trackingRegion: NSTrackingArea?

    override var isOpaque: Bool { false }

    override func updateTrackingAreas() {
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
            options: [.mouseEnteredAndExited, .activeAlways],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(area)
        trackingRegion = area
    }

    override func mouseEntered(with event: NSEvent) {
        onEnter?()
    }

    override func mouseExited(with event: NSEvent) {
        onExit?()
    }
}

final class DockRevealTriggerPanel: NSPanel {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
    override var acceptsFirstResponder: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }

    static func make() -> DockRevealTriggerPanel {
        let panel = DockRevealTriggerPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)))
        panel.collectionBehavior = [
            .canJoinAllSpaces,
            .stationary,
            .ignoresCycle,
            .fullScreenAuxiliary,
        ]
        panel.isOpaque = false
        panel.backgroundColor = NSColor(white: 0, alpha: 0.01)
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.isMovable = false
        panel.isMovableByWindowBackground = false
        panel.acceptsMouseMovedEvents = true
        panel.isReleasedWhenClosed = false
        panel.animationBehavior = .none
        panel.tabbingMode = .disallowed
        panel.worksWhenModal = true
        return panel
    }
}

@MainActor
final class DockRevealTrigger {
    var onEnter: (@MainActor () -> Void)?
    var onExit: (@MainActor () -> Void)?

    private let panel = DockRevealTriggerPanel.make()
    private let view = DockRevealTriggerView(frame: .zero)
    private var placement: CGRect = .zero
    private var isShown = false

    init() {
        view.onEnter = { [weak self] in self?.onEnter?() }
        view.onExit = { [weak self] in self?.onExit?() }
        panel.contentView = view
    }

    func place(screenFrame: CGRect, orientation: DockOrientation) {
        guard !screenFrame.isEmpty else { return }
        let frame = DockAutoHide.triggerFrame(screenFrame: screenFrame, orientation: orientation)
        guard frame != placement else { return }
        placement = frame
        panel.setFrame(frame, display: false)
        view.frame = CGRect(origin: .zero, size: frame.size)
    }

    func show() {
        guard !isShown, !placement.isEmpty else { return }
        isShown = true
        panel.orderFrontRegardless()
    }

    func hide() {
        guard isShown else { return }
        isShown = false
        panel.orderOut(nil)
    }

    func tearDown() {
        hide()
        view.onEnter = nil
        view.onExit = nil
        onEnter = nil
        onExit = nil
        panel.contentView = nil
    }
}
