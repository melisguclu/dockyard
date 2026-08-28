import AppKit
import DockCore
import Foundation

extension DockContentView {
    public static let typeSelectWindow: Duration = .seconds(1)

    public var isKeyboardFocused: Bool { keyboardIdentifier != nil }

    override public var acceptsFirstResponder: Bool { wantsKeyboardFocus }

    public func beginKeyboardFocus() {
        let candidates = keyboardCandidates
        guard let first = candidates.first else { return }
        wantsKeyboardFocus = true
        window?.makeFirstResponder(self)
        let target = keyboardIdentifier.flatMap { candidates.contains($0) ? $0 : nil } ?? first
        focusKeyboard(on: target)
    }

    public func endKeyboardFocus() {
        guard wantsKeyboardFocus || keyboardIdentifier != nil else { return }
        cancelTypeSelect()
        setKeyboardHighlight(nil)
        keyboardIdentifier = nil
        wantsKeyboardFocus = false
        dismissTileLabel()
        if window?.firstResponder === self {
            window?.makeFirstResponder(nil)
        }
        onKeyboardFocusEnded?()
    }

    override public func resignFirstResponder() -> Bool {
        defer { endKeyboardFocus() }
        return super.resignFirstResponder()
    }

    override public func keyDown(with event: NSEvent) {
        switch Int(event.keyCode) {
        case 123, 126:
            moveKeyboardFocus(by: -1)
        case 124, 125:
            moveKeyboardFocus(by: 1)
        case 36, 76, 49:
            activateKeyboardFocus()
        case 53, 48:
            endKeyboardFocus()
        case 47:
            showKeyboardMenu()
        default:
            typeSelect(event.charactersIgnoringModifiers ?? "")
        }
    }

    var keyboardCandidates: [DockTileID] {
        snapshot.tiles.filter(\.isInteractive).map(\.id)
    }

    private func focusKeyboard(on identifier: DockTileID) {
        keyboardIdentifier = identifier
        setKeyboardHighlight(identifier)
        presentKeyboardLabel(for: identifier)
        announceAccessibilityFocus(identifier)
    }

    private func moveKeyboardFocus(by step: Int) {
        let candidates = keyboardCandidates
        guard !candidates.isEmpty else { return }
        cancelTypeSelect()
        guard let current = keyboardIdentifier, let position = candidates.firstIndex(of: current) else {
            focusKeyboard(on: step > 0 ? candidates[0] : candidates[candidates.count - 1])
            return
        }
        let next = ((position + step) % candidates.count + candidates.count) % candidates.count
        focusKeyboard(on: candidates[next])
    }

    private func activateKeyboardFocus() {
        guard let keyboardIdentifier, let tile = snapshot.tile(with: keyboardIdentifier) else { return }
        endKeyboardFocus()
        delegate?.dockContentView(self, didActivate: tile)
    }

    private func showKeyboardMenu() {
        guard let keyboardIdentifier, let tile = snapshot.tile(with: keyboardIdentifier) else { return }
        presentTileMenu(for: tile)
    }

    private func typeSelect(_ characters: String) {
        let trimmed = characters.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed.count == 1 else { return }
        typeSelect += trimmed
        scheduleTypeSelectReset()
        let prefix = typeSelect
        let match = snapshot.tiles.first {
            $0.isInteractive
                && $0.label.range(of: prefix, options: [.caseInsensitive, .diacriticInsensitive, .anchored]) != nil
        }
        guard let match else { return }
        focusKeyboard(on: match.id)
    }

    private func scheduleTypeSelectReset() {
        typeSelectTask?.cancel()
        typeSelectTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.typeSelectWindow)
            guard !Task.isCancelled, let self else { return }
            self.typeSelectTask = nil
            self.typeSelect = ""
        }
    }

    private func cancelTypeSelect() {
        typeSelectTask?.cancel()
        typeSelectTask = nil
        typeSelect = ""
    }

    private func setKeyboardHighlight(_ identifier: DockTileID?) {
        for (existing, layer) in tileLayers where existing != identifier {
            guard existing != dropTargetIdentifier else { continue }
            layer.setHighlighted(false)
        }
        guard let identifier else { return }
        tileLayers[identifier]?.setHighlighted(true)
    }

    private func presentKeyboardLabel(for identifier: DockTileID) {
        guard let window,
            let index = snapshot.tiles.firstIndex(where: { $0.id == identifier }),
            index < currentLayout.tileFrames.count
        else { return }
        let tile = snapshot.tiles[index]
        guard !tile.label.isEmpty else {
            dismissTileLabel()
            return
        }
        labelIdentifier = tile.id
        tileLabel.present(
            DockTileLabelRequest(
                identifier: tile.id,
                text: tile.label,
                anchor: window.convertToScreen(convert(currentLayout.tileFrames[index], to: nil)),
                orientation: snapshot.appearance.orientation,
                screen: window.screen?.visibleFrame ?? window.frame,
                appearance: effectiveAppearance
            )
        )
    }
}
