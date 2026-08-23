import AppKit
import Foundation

@MainActor
public final class RunningApplicationsObserver {
    public private(set) var applications: [RunningApplicationState] = []

    private var launchSequences: [pid_t: UInt64] = [:]
    private var nextSequence: UInt64 = 0
    private var observers: [NSObjectProtocol] = []
    private var onChange: (@MainActor () -> Void)?
    private var onLaunch: (@MainActor (String) -> Void)?

    private static let observedNotifications: [Notification.Name] = [
        NSWorkspace.didLaunchApplicationNotification,
        NSWorkspace.didTerminateApplicationNotification,
        NSWorkspace.didActivateApplicationNotification,
        NSWorkspace.didDeactivateApplicationNotification,
        NSWorkspace.didHideApplicationNotification,
        NSWorkspace.didUnhideApplicationNotification,
    ]

    public init() {}

    public func start(
        onChange: @escaping @MainActor () -> Void,
        onLaunch: @escaping @MainActor (String) -> Void = { _ in }
    ) {
        self.onChange = onChange
        self.onLaunch = onLaunch
        refresh()

        let center = NSWorkspace.shared.notificationCenter
        for name in Self.observedNotifications {
            let observer = center.addObserver(
                forName: name,
                object: nil,
                queue: .main
            ) { [weak self] notification in
                let notificationName = notification.name
                let launchedPath =
                    (notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication)?.bundleURL?.standardizedFileURL.path
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.refresh()
                    if notificationName == NSWorkspace.didLaunchApplicationNotification, let launchedPath {
                        self.onLaunch?(launchedPath)
                    }
                    self.onChange?()
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
        onChange = nil
        onLaunch = nil
    }

    public func refresh() {
        let dockable = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular }

        var live: Set<pid_t> = []
        var states: [RunningApplicationState] = []
        states.reserveCapacity(dockable.count)

        for application in dockable {
            let pid = application.processIdentifier
            live.insert(pid)

            let sequence: UInt64
            if let existing = launchSequences[pid] {
                sequence = existing
            } else {
                sequence = nextSequence
                launchSequences[pid] = sequence
                nextSequence += 1
            }

            states.append(
                RunningApplicationState(
                    processIdentifier: pid,
                    bundleIdentifier: application.bundleIdentifier,
                    bundleURL: application.bundleURL?.standardizedFileURL.resolvingSymlinksInPath(),
                    localizedName: application.localizedName ?? application.bundleIdentifier ?? "",
                    isActive: application.isActive,
                    isHidden: application.isHidden,
                    launchSequence: sequence
                )
            )
        }

        launchSequences = launchSequences.filter { live.contains($0.key) }
        applications = states.sorted { $0.launchSequence < $1.launchSequence }
    }
}
