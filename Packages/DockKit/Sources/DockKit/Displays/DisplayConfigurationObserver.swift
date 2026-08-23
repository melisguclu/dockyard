import AppKit
import CoreGraphics
import DockCore
import Foundation

@MainActor
public final class DisplayConfigurationObserver {
    public static let settleDelay: Duration = .milliseconds(350)

    private var settleTask: Task<Void, Never>?
    private var screenParameterObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var isRegistered = false
    private var onBegin: (@MainActor () -> Void)?
    private var onSettled: (@MainActor () -> Void)?

    public init() {}

    public func start(
        onBegin: @escaping @MainActor () -> Void,
        onSettled: @escaping @MainActor () -> Void
    ) {
        self.onBegin = onBegin
        self.onSettled = onSettled

        if !isRegistered {
            CGDisplayRegisterReconfigurationCallback(
                Self.reconfigurationCallback,
                Unmanaged.passUnretained(self).toOpaque()
            )
            isRegistered = true
        }

        screenParameterObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.scheduleSettle()
            }
        }

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.scheduleSettle()
            }
        }
    }

    public func stop() {
        settleTask?.cancel()
        settleTask = nil

        if isRegistered {
            CGDisplayRemoveReconfigurationCallback(
                Self.reconfigurationCallback,
                Unmanaged.passUnretained(self).toOpaque()
            )
            isRegistered = false
        }
        if let screenParameterObserver {
            NotificationCenter.default.removeObserver(screenParameterObserver)
            self.screenParameterObserver = nil
        }
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
            self.wakeObserver = nil
        }
    }

    public func scheduleSettle() {
        settleTask?.cancel()
        settleTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.settleDelay)
            guard !Task.isCancelled, let self else { return }
            self.settleTask = nil
            self.onSettled?()
        }
    }

    private func beginConfiguration() {
        settleTask?.cancel()
        settleTask = nil
        onBegin?()
    }

    nonisolated private static let reconfigurationCallback: CGDisplayReconfigurationCallBack = { _, flags, userInfo in
        guard let userInfo else { return }
        let observer = Unmanaged<DisplayConfigurationObserver>
            .fromOpaque(userInfo)
            .takeUnretainedValue()
        let isBeginning = flags.contains(.beginConfigurationFlag)
        Task { @MainActor in
            if isBeginning {
                observer.beginConfiguration()
            } else {
                observer.scheduleSettle()
            }
        }
    }
}
