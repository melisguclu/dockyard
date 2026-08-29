import AppKit
import Foundation

@MainActor
public final class DockItemStore {
    public static let bundleIdentifier = "com.apple.dock"
    public static let coalescingDelay: Duration = .milliseconds(120)

    public private(set) var items: DockItemList = .empty
    public var onChange: (@MainActor () -> Void)?

    public var isAuthorized: Bool {
        authorization()
    }

    private let inspector: any DockItemInspecting
    private let authorization: @MainActor () -> Bool
    private let resolvedProcessIdentifier: @MainActor () -> pid_t?
    private let observer = ApplicationWindowObserver(
        notifications: ApplicationWindowObserver.dockItemNotifications
    )

    private var processIdentifier: pid_t?
    private var readTask: Task<Void, Never>?
    private var coalesceTask: Task<Void, Never>?
    private var pending = false
    private var reportedAuthorization: Bool?

    public init(
        inspector: any DockItemInspecting = DockItemInspector(),
        authorization: @escaping @MainActor () -> Bool = { AccessibilityAuthorization.isTrusted },
        processIdentifier: @escaping @MainActor () -> pid_t? = liveDockProcessIdentifier
    ) {
        self.inspector = inspector
        self.authorization = authorization
        resolvedProcessIdentifier = processIdentifier
    }

    deinit {
        readTask?.cancel()
        coalesceTask?.cancel()
    }

    public func start() {
        observer.start { [weak self] _ in
            self?.scheduleRefresh()
        }
        refresh()
    }

    public func stop() {
        observer.stop()
        readTask?.cancel()
        readTask = nil
        coalesceTask?.cancel()
        coalesceTask = nil
        pending = false
        forget()
    }

    public func refresh() {
        reportAuthorization()
        guard isAuthorized else {
            forget()
            return
        }
        guard let processIdentifier = resolveProcessIdentifier() else { return }
        guard readTask == nil else {
            pending = true
            return
        }
        let inspector = inspector
        readTask = Task { @MainActor [weak self] in
            let list = await inspector.read(processIdentifier: processIdentifier)
            guard let self, !Task.isCancelled else { return }
            self.readTask = nil
            self.publish(list)
            guard self.pending else { return }
            self.pending = false
            self.refresh()
        }
    }

    public func settle() async {
        while let task = readTask {
            await task.value
        }
    }

    private func scheduleRefresh() {
        coalesceTask?.cancel()
        coalesceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.coalescingDelay)
            guard !Task.isCancelled, let self else { return }
            self.coalesceTask = nil
            self.refresh()
        }
    }

    private func resolveProcessIdentifier() -> pid_t? {
        guard let resolved = resolvedProcessIdentifier() else {
            forget()
            return nil
        }
        processIdentifier = resolved
        observer.update(with: [resolved])
        return resolved
    }

    private func forget() {
        processIdentifier = nil
        observer.update(with: [])
        publish(.empty)
    }

    private func publish(_ list: DockItemList) {
        guard list != items else { return }
        items = list
        DockLog.dockItems.info(
            """
            \(list.items.count, privacy: .public) dock items, \
            \(list.badgeCount, privacy: .public) badged
            """
        )
        onChange?()
    }

    private func reportAuthorization() {
        let authorized = isAuthorized
        guard reportedAuthorization != authorized else { return }
        reportedAuthorization = authorized
        if authorized {
            DockLog.dockItems.info("Accessibility authorized, the Dock's own item list is readable")
        } else {
            DockLog.dockItems.error(
                "Accessibility not authorized, tile order is inferred and badges are unavailable"
            )
        }
    }
}

@MainActor
public func liveDockProcessIdentifier() -> pid_t? {
    NSRunningApplication
        .runningApplications(withBundleIdentifier: DockItemStore.bundleIdentifier)
        .first?
        .processIdentifier
}
