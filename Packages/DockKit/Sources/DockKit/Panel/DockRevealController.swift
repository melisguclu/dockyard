import AppKit
import DockCore
import Foundation

@MainActor
final class DockRevealController {
    var applyFrame: (@MainActor (CGRect) -> Void)?
    var didReveal: (@MainActor () -> Void)?
    var didHide: (@MainActor () -> Void)?

    private(set) var state: DockRevealState = .disabled

    private let panel: NSPanel
    private let trigger = DockRevealTrigger()
    private var appearance: DockAppearance = .default
    private var screenFrame: CGRect = .zero
    private var revealedFrame: CGRect = .zero
    private var isVisible = false
    private var isCoveredByFullScreen = false
    private var revealTask: Task<Void, Never>?
    private var slideToken = 0

    init(panel: NSPanel) {
        self.panel = panel
        trigger.onEnter = { [weak self] in self?.scheduleReveal() }
        trigger.onExit = { [weak self] in self?.cancelScheduledReveal() }
    }

    deinit {
        revealTask?.cancel()
    }

    func update(appearance: DockAppearance, screenFrame: CGRect, revealedFrame: CGRect) {
        self.appearance = appearance
        self.screenFrame = screenFrame
        self.revealedFrame = revealedFrame
        if !state.isSliding {
            seat()
        }
        updateMode()
        updateTrigger()
    }

    func setCoveredByFullScreen(_ covered: Bool) {
        guard isCoveredByFullScreen != covered else { return }
        isCoveredByFullScreen = covered
        updateMode()
        updateTrigger()
    }

    func setVisible(_ visible: Bool) {
        guard isVisible != visible else { return }
        isVisible = visible
        guard visible else {
            retreat()
            return
        }
        updateTrigger()
    }

    func pointerDidLeave() {
        beginHide()
    }

    func tearDown() {
        cancelScheduledReveal()
        slideToken += 1
        trigger.tearDown()
        applyFrame = nil
        didReveal = nil
        didHide = nil
    }

    private var hiddenFrame: CGRect {
        DockAutoHide.hiddenFrame(
            revealed: revealedFrame,
            screenFrame: screenFrame,
            orientation: appearance.orientation
        )
    }

    private func seat() {
        applyFrame?(state.showsTrigger ? hiddenFrame : revealedFrame)
    }

    private var hidesItself: Bool {
        appearance.autoHide || isCoveredByFullScreen
    }

    private func updateMode() {
        let enabled = hidesItself
        guard enabled != (state != .disabled) else { return }
        cancelScheduledReveal()
        guard enabled else {
            let slidesIn = isVisible && state != .revealed && !revealedFrame.isEmpty
            state = .disabled
            trigger.hide()
            guard slidesIn else {
                slideToken += 1
                seat()
                return
            }
            slide(to: revealedFrame) { [weak self] in
                guard let self, self.state == .disabled else { return }
                self.seat()
            }
            return
        }
        guard isVisible, !revealedFrame.isEmpty else {
            slideToken += 1
            state = .hidden
            seat()
            return
        }
        state = .revealed
        beginHide()
    }

    private func updateTrigger() {
        guard isVisible, state.showsTrigger else {
            trigger.hide()
            return
        }
        trigger.place(screenFrame: screenFrame, orientation: appearance.orientation)
        trigger.show()
    }

    private func scheduleReveal() {
        guard isVisible, state == .hidden else { return }
        cancelScheduledReveal()
        let delay = DockAutoHide.revealDelay(appearance)
        revealTask = Task { @MainActor [weak self] in
            if delay > 0 {
                try? await Task.sleep(for: .seconds(delay))
            }
            guard !Task.isCancelled, let self else { return }
            self.revealTask = nil
            self.beginReveal()
        }
    }

    private func cancelScheduledReveal() {
        revealTask?.cancel()
        revealTask = nil
    }

    private func beginReveal() {
        guard isVisible, state == .hidden, !revealedFrame.isEmpty else { return }
        state = .revealing
        trigger.hide()
        applyFrame?(hiddenFrame)
        slide(to: revealedFrame) { [weak self] in
            guard let self, self.state == .revealing else { return }
            self.state = .revealed
            self.seat()
            self.didReveal?()
        }
    }

    private func beginHide() {
        guard state == .revealed else { return }
        cancelScheduledReveal()
        state = .hiding
        slide(to: hiddenFrame) { [weak self] in
            guard let self, self.state == .hiding else { return }
            self.state = .hidden
            self.didHide?()
            self.seat()
            self.updateTrigger()
        }
    }

    private func retreat() {
        cancelScheduledReveal()
        slideToken += 1
        trigger.hide()
        guard state != .disabled else { return }
        state = .hidden
        seat()
    }

    private func slide(to frame: CGRect, completion: @escaping @MainActor () -> Void) {
        slideToken += 1
        let token = slideToken
        NSAnimationContext.runAnimationGroup { context in
            context.duration = DockAutoHide.slideDuration(appearance)
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            panel.animator().setFrame(frame, display: false)
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.slideToken == token else { return }
                completion()
            }
        }
    }
}
