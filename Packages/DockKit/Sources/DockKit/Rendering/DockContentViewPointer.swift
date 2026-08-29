import AppKit
import DockCore
import Foundation
import QuartzCore

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
