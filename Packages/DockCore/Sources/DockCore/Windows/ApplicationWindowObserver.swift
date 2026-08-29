import ApplicationServices
import Foundation

@MainActor
final class ApplicationWindowObserver {
    static let messagingTimeout: Float = 2

    static let minimizeNotifications = [
        kAXWindowMiniaturizedNotification,
        kAXWindowDeminiaturizedNotification,
    ]

    static let dockItemNotifications = [
        kAXCreatedNotification,
        kAXUIElementDestroyedNotification,
    ]

    static let geometryNotifications = [
        kAXWindowMovedNotification,
        kAXWindowResizedNotification,
        kAXWindowCreatedNotification,
    ]

    private struct Registration {
        let observer: AXObserver
        let element: AXUIElement
    }

    private let notifications: [String]
    private var registrations: [pid_t: Registration] = [:]
    private var onChange: (@MainActor (pid_t) -> Void)?

    init(notifications: [String]) {
        self.notifications = notifications
    }

    func start(onChange: @escaping @MainActor (pid_t) -> Void) {
        self.onChange = onChange
    }

    func update(with processIdentifiers: Set<pid_t>) {
        for (processIdentifier, registration) in registrations
        where !processIdentifiers.contains(processIdentifier) {
            deregister(registration)
            registrations.removeValue(forKey: processIdentifier)
        }
        for processIdentifier in processIdentifiers where registrations[processIdentifier] == nil {
            guard let registration = register(processIdentifier) else { continue }
            registrations[processIdentifier] = registration
        }
    }

    func stop() {
        for registration in registrations.values {
            deregister(registration)
        }
        registrations.removeAll()
        onChange = nil
    }

    fileprivate func report(_ processIdentifier: pid_t) {
        onChange?(processIdentifier)
    }

    private func register(_ processIdentifier: pid_t) -> Registration? {
        var created: AXObserver?
        guard AXObserverCreate(processIdentifier, applicationWindowObserverCallback, &created) == .success,
            let observer = created
        else {
            DockLog.windows.error(
                "No accessibility observer for pid \(processIdentifier, privacy: .public)"
            )
            return nil
        }

        let element = AXUIElementCreateApplication(processIdentifier)
        AXUIElementSetMessagingTimeout(element, Self.messagingTimeout)
        let context = Unmanaged.passUnretained(self).toOpaque()

        var registered = false
        for notification in notifications {
            let status = AXObserverAddNotification(observer, element, notification as CFString, context)
            registered = registered || status == .success
        }
        guard registered else { return nil }

        CFRunLoopAddSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(observer),
            CFRunLoopMode.commonModes
        )
        return Registration(observer: observer, element: element)
    }

    private func deregister(_ registration: Registration) {
        for notification in notifications {
            AXObserverRemoveNotification(
                registration.observer,
                registration.element,
                notification as CFString
            )
        }
        CFRunLoopRemoveSource(
            CFRunLoopGetMain(),
            AXObserverGetRunLoopSource(registration.observer),
            CFRunLoopMode.commonModes
        )
    }
}

private let applicationWindowObserverCallback: AXObserverCallback = { _, element, _, context in
    guard let context else { return }
    var processIdentifier: pid_t = 0
    guard AXUIElementGetPid(element, &processIdentifier) == .success else { return }
    let address = UInt(bitPattern: context)
    MainActor.assumeIsolated {
        guard let owner = UnsafeMutableRawPointer(bitPattern: address) else { return }
        Unmanaged<ApplicationWindowObserver>.fromOpaque(owner)
            .takeUnretainedValue()
            .report(processIdentifier)
    }
}
