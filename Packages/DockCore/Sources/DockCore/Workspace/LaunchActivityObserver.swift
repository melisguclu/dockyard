import AppKit
import Foundation

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
    ]

    public init() {}

    public func start() {
        let center = NSWorkspace.shared.notificationCenter
        for name in Self.observedNotifications {
            let observer = center.addObserver(forName: name, object: nil, queue: .main) { notification in
                let notificationName = notification.name
                let application =
                    notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
                let processIdentifier = application?.processIdentifier
                let identifier = DockTileID.application(
                    bundleIdentifier: application?.bundleIdentifier,
                    path: application?.bundleURL?.standardizedFileURL.resolvingSymlinksInPath().path
                )
                MainActor.assumeIsolated { [weak self] in
                    guard let self, let processIdentifier else { return }
                    if notificationName == NSWorkspace.willLaunchApplicationNotification {
                        guard let identifier else { return }
                        self.begin(processIdentifier, identifier: identifier)
                    } else {
                        self.end(processIdentifier)
                    }
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
