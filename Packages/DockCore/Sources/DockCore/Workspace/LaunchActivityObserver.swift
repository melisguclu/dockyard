import AppKit
import Foundation

public enum LaunchActivityEvent: Sendable, Equatable {
    case willLaunch(processIdentifier: pid_t, identifier: DockTileID, isFinishedLaunching: Bool)
    case didLaunch(processIdentifier: pid_t)
    case didTerminate(processIdentifier: pid_t)
    case isUp(processIdentifier: pid_t)
}

@MainActor
public final class LaunchActivityObserver {
    public static let maximumBounce: Duration = .seconds(30)

    public private(set) var launching: Set<DockTileID> = []
    public var onChange: (@MainActor (Set<DockTileID>) -> Void)?

    private var observers: [NSObjectProtocol] = []
    private var pending: [pid_t: Pending] = [:]

    private struct Pending {
        let identifier: DockTileID
        let expiry: Task<Void, Never>
    }

    private static let observedNotifications: [Notification.Name] = [
        NSWorkspace.willLaunchApplicationNotification,
        NSWorkspace.didLaunchApplicationNotification,
        NSWorkspace.didTerminateApplicationNotification,
        NSWorkspace.didActivateApplicationNotification,
        NSWorkspace.didUnhideApplicationNotification,
    ]

    public init() {}

    public func start() {
        let center = NSWorkspace.shared.notificationCenter
        for name in Self.observedNotifications {
            let observer = center.addObserver(forName: name, object: nil, queue: .main) { notification in
                let application =
                    notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                let event = Self.event(for: notification.name, application: application)
                MainActor.assumeIsolated { [weak self] in
                    guard let self, let event else { return }
                    self.handle(event)
                }
            }
            observers.append(observer)
        }
    }

    public func stop() {
        let center = NSWorkspace.shared.notificationCenter
        for observer in observers {
            center.removeObserver(observer)
        }
        observers.removeAll()
        for entry in pending.values {
            entry.expiry.cancel()
        }
        pending.removeAll()
        publish()
        onChange = nil
    }

    public func handle(_ event: LaunchActivityEvent) {
        switch event {
        case .willLaunch(let processIdentifier, let identifier, let isFinishedLaunching):
            guard !isFinishedLaunching else {
                DockLog.workspace.debug("A launch of an application that is already up does not bounce")
                return
            }
            begin(processIdentifier, identifier: identifier)
        case .didLaunch(let processIdentifier),
            .didTerminate(let processIdentifier),
            .isUp(let processIdentifier):
            end(processIdentifier)
        }
    }

    nonisolated private static func event(
        for name: Notification.Name,
        application: NSRunningApplication?
    ) -> LaunchActivityEvent? {
        guard let application else { return nil }
        let processIdentifier = application.processIdentifier
        switch name {
        case NSWorkspace.willLaunchApplicationNotification:
            guard
                let identifier = DockTileID.application(
                    bundleIdentifier: application.bundleIdentifier,
                    path: application.bundleURL?.standardizedFileURL.resolvingSymlinksInPath().path
                )
            else { return nil }
            return .willLaunch(
                processIdentifier: processIdentifier,
                identifier: identifier,
                isFinishedLaunching: application.isFinishedLaunching
            )
        case NSWorkspace.didLaunchApplicationNotification:
            return .didLaunch(processIdentifier: processIdentifier)
        case NSWorkspace.didTerminateApplicationNotification:
            return .didTerminate(processIdentifier: processIdentifier)
        default:
            guard application.isFinishedLaunching else { return nil }
            return .isUp(processIdentifier: processIdentifier)
        }
    }

    private func begin(_ processIdentifier: pid_t, identifier: DockTileID) {
        pending[processIdentifier]?.expiry.cancel()
        let expiry = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.maximumBounce)
            guard !Task.isCancelled, let self else { return }
            self.end(processIdentifier)
        }
        pending[processIdentifier] = Pending(identifier: identifier, expiry: expiry)
        DockLog.workspace.debug("Launch began, \(self.pending.count, privacy: .public) in flight")
        publish()
    }

    private func end(_ processIdentifier: pid_t) {
        guard let entry = pending.removeValue(forKey: processIdentifier) else { return }
        entry.expiry.cancel()
        publish()
    }

    private func publish() {
        let identifiers = Set(pending.values.map(\.identifier))
        guard identifiers != launching else { return }
        launching = identifiers
        onChange?(identifiers)
    }
}
