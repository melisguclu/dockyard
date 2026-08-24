import ApplicationServices
import Foundation

@MainActor
final class MinimizedWindowObserver {
    static let messagingTimeout: Float = 2

    static let notifications = [
        kAXWindowMiniaturizedNotification,
        kAXWindowDeminiaturizedNotification,
    ]

    private struct Registration {
        let observer: AXObserver
        let element: AXUIElement
    }

    private var registrations: [pid_t: Registration] = [:]
    private var onChange: (@MainActor (pid_t) -> Void)?

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
        guard AXObserverCreate(processIdentifier, minimizedWindowObserverCallback, &created) == .success,
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
        for notification in Self.notifications {
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
        for notification in Self.notifications {
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

private let minimizedWindowObserverCallback: AXObserverCallback = { _, element, _, context in
    guard let context else { return }
    var processIdentifier: pid_t = 0
    guard AXUIElementGetPid(element, &processIdentifier) == .success else { return }
    let address = UInt(bitPattern: context)
    MainActor.assumeIsolated {
        guard let owner = UnsafeMutableRawPointer(bitPattern: address) else { return }
        Unmanaged<MinimizedWindowObserver>.fromOpaque(owner)
            .takeUnretainedValue()
            .report(processIdentifier)
    }
}
