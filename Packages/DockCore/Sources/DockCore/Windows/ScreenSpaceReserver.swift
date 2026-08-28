import AppKit
import Foundation

@MainActor
public final class ScreenSpaceReserver {
    public static let coalescingDelay: Duration = .milliseconds(150)

    public private(set) var isEnabled = false
    public private(set) var reservedAreas: [ReservedArea] = []

    public var isAuthorized: Bool {
        authorization()
    }

    private let inspector: any WindowFrameInspecting
    private let authorization: @MainActor () -> Bool
    private let observer = ApplicationWindowObserver(
        notifications: ApplicationWindowObserver.geometryNotifications
    )

    private var applications: [pid_t: RunningApplicationState] = [:]
    private var pending: Set<pid_t> = []
    private var settleTask: Task<Void, Never>?
    private var resizeTasks: [pid_t: Task<Void, Never>] = [:]

    public init(
        inspector: any WindowFrameInspecting = WindowFrameInspector(),
        authorization: @escaping @MainActor () -> Bool = { AccessibilityAuthorization.isTrusted }
    ) {
        self.inspector = inspector
        self.authorization = authorization
    }

    deinit {
        settleTask?.cancel()
        for task in resizeTasks.values {
            task.cancel()
        }
    }

    public func start() {
        observer.start { [weak self] processIdentifier in
            self?.schedule(processIdentifier)
        }
    }

    public func stop() {
        observer.stop()
        settleTask?.cancel()
        settleTask = nil
        pending.removeAll()
        for task in resizeTasks.values {
            task.cancel()
        }
        resizeTasks.removeAll()
    }

    public func setEnabled(_ enabled: Bool) {
        guard isEnabled != enabled else { return }
        isEnabled = enabled
        DockLog.windows.info("Screen space reservation \(enabled ? "on" : "off", privacy: .public)")
        guard enabled else {
            observer.update(with: [])
            pending.removeAll()
            settleTask?.cancel()
            settleTask = nil
            return
        }
        register()
        scheduleAll()
    }

    public func setReservedAreas(_ areas: [ReservedArea]) {
        guard areas != reservedAreas else { return }
        reservedAreas = areas
        guard isEnabled else { return }
        scheduleAll()
    }

    public func update(with applications: [RunningApplicationState]) {
        let live = Set(applications.map(\.processIdentifier))
        self.applications = Dictionary(
            applications.map { ($0.processIdentifier, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        for (processIdentifier, task) in resizeTasks where !live.contains(processIdentifier) {
            task.cancel()
            resizeTasks.removeValue(forKey: processIdentifier)
        }
        pending = pending.filter { live.contains($0) }
        guard isEnabled else { return }
        register()
        for processIdentifier in live {
            schedule(processIdentifier)
        }
    }

    public func settle() async {
        while let task = settleTask ?? resizeTasks.values.first {
            await task.value
        }
    }

    private func register() {
        guard isEnabled, isAuthorized else {
            observer.update(with: [])
            return
        }
        observer.update(with: Set(applications.keys.filter { $0 != ProcessInfo.processInfo.processIdentifier }))
    }

    private func scheduleAll() {
        for processIdentifier in applications.keys {
            schedule(processIdentifier)
        }
    }

    private func schedule(_ processIdentifier: pid_t) {
        guard isEnabled, isAuthorized, !reservedAreas.isEmpty else { return }
        guard applications[processIdentifier] != nil else { return }
        pending.insert(processIdentifier)
        guard settleTask == nil else { return }
        settleTask = Task { @MainActor [weak self] in
            while true {
                try? await Task.sleep(for: Self.coalescingDelay)
                guard !Task.isCancelled, let self else { return }
                guard NSEvent.pressedMouseButtons == 0 else { continue }
                self.settleTask = nil
                self.flush()
                return
            }
        }
    }

    private func flush() {
        let identifiers = pending
        pending.removeAll()
        for processIdentifier in identifiers {
            evaluate(processIdentifier)
        }
    }

    private func evaluate(_ processIdentifier: pid_t) {
        guard isEnabled, isAuthorized, !reservedAreas.isEmpty else { return }
        guard resizeTasks[processIdentifier] == nil else {
            pending.insert(processIdentifier)
            return
        }
        let inspector = inspector
        let areas = reservedAreas
        resizeTasks[processIdentifier] = Task { @MainActor [weak self] in
            let windows = await inspector.windows(processIdentifier: processIdentifier)
            var resized = 0
            for window in windows {
                guard let frame = ScreenSpaceGeometry.adjusted(window: window.frame, avoiding: areas) else {
                    continue
                }
                guard await inspector.resize(window, to: frame, processIdentifier: processIdentifier) else {
                    continue
                }
                resized += 1
            }
            guard let self, !Task.isCancelled else { return }
            self.resizeTasks[processIdentifier] = nil
            if self.pending.remove(processIdentifier) != nil {
                self.schedule(processIdentifier)
            }
            guard resized > 0 else { return }
            DockLog.windows.debug(
                """
                Kept \(resized, privacy: .public) window(s) of pid \
                \(processIdentifier, privacy: .public) clear of the bar
                """
            )
        }
    }
}
