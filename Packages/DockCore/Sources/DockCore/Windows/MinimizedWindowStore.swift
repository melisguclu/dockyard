import AppKit
import Foundation

@MainActor
public final class MinimizedWindowStore {
    public private(set) var windows: [MinimizedWindow] = []
    public var onChange: (@MainActor () -> Void)?

    public var isAuthorized: Bool {
        AccessibilityAuthorization.isTrusted
    }

    private struct WindowKey: Hashable {
        let title: String
        let ordinal: Int
    }

    private let inspector: any AppMenuInspecting
    private let observer = MinimizedWindowObserver()

    private var applications: [pid_t: RunningApplicationState] = [:]
    private var windowsByProcess: [pid_t: [MinimizedWindow]] = [:]
    private var tokensByProcess: [pid_t: [WindowKey: UInt64]] = [:]
    private var refreshTasks: [pid_t: Task<Void, Never>] = [:]
    private var pending: Set<pid_t> = []
    private var nextToken: UInt64 = 0

    public init(inspector: any AppMenuInspecting = AppMenuInspector()) {
        self.inspector = inspector
    }

    deinit {
        for task in refreshTasks.values {
            task.cancel()
        }
    }

    public func start() {
        observer.start { [weak self] processIdentifier in
            self?.refresh(processIdentifier)
        }
    }

    public func stop() {
        observer.stop()
        for task in refreshTasks.values {
            task.cancel()
        }
        refreshTasks.removeAll()
        pending.removeAll()
    }

    public func update(with applications: [RunningApplicationState]) {
        let live = Set(applications.map(\.processIdentifier))
        self.applications = Dictionary(
            applications.map { ($0.processIdentifier, $0) },
            uniquingKeysWith: { first, _ in first }
        )

        for (processIdentifier, task) in refreshTasks where !live.contains(processIdentifier) {
            task.cancel()
        }
        refreshTasks = refreshTasks.filter { live.contains($0.key) }
        windowsByProcess = windowsByProcess.filter { live.contains($0.key) }
        tokensByProcess = tokensByProcess.filter { live.contains($0.key) }
        pending = pending.filter { live.contains($0) }

        guard isAuthorized else {
            observer.update(with: [])
            windowsByProcess.removeAll()
            tokensByProcess.removeAll()
            publish()
            return
        }

        observer.update(with: live)
        for processIdentifier in live {
            refresh(processIdentifier)
        }
        publish()
    }

    public func window(with identifier: DockTileID) -> MinimizedWindow? {
        guard case .window(let token) = identifier else { return nil }
        return windows.first { $0.token == token }
    }

    public func restore(_ identifier: DockTileID) {
        guard let window = window(with: identifier) else { return }
        let inspector = inspector
        let entry = window.entry
        let processIdentifier = window.processIdentifier
        Task { @MainActor in
            let raised = await inspector.raise(entry, processIdentifier: processIdentifier)
            guard raised else {
                DockLog.windows.error(
                    "A minimized window of pid \(processIdentifier, privacy: .public) could not be restored"
                )
                return
            }
            guard let application = NSRunningApplication(processIdentifier: processIdentifier) else { return }
            if application.isHidden {
                application.unhide()
            }
            _ = application.activate()
        }
    }

    public func settle() async {
        while let task = refreshTasks.values.first {
            await task.value
        }
    }

    private func refresh(_ processIdentifier: pid_t) {
        guard isAuthorized, applications[processIdentifier] != nil else { return }
        guard refreshTasks[processIdentifier] == nil else {
            pending.insert(processIdentifier)
            return
        }
        let inspector = inspector
        refreshTasks[processIdentifier] = Task { @MainActor [weak self] in
            let entries = await inspector.windows(processIdentifier: processIdentifier)
            guard let self, !Task.isCancelled else { return }
            self.refreshTasks[processIdentifier] = nil
            self.apply(entries.filter(\.isMinimized), for: processIdentifier)
            guard self.pending.remove(processIdentifier) != nil else { return }
            self.refresh(processIdentifier)
        }
    }

    private func apply(_ entries: [AppWindowEntry], for processIdentifier: pid_t) {
        guard let application = applications[processIdentifier] else { return }

        var ordinals: [String: Int] = [:]
        var tokens: [WindowKey: UInt64] = [:]
        var resolved: [MinimizedWindow] = []
        let previous = tokensByProcess[processIdentifier] ?? [:]

        for entry in entries {
            let ordinal = ordinals[entry.title, default: 0]
            ordinals[entry.title] = ordinal + 1
            let key = WindowKey(title: entry.title, ordinal: ordinal)

            let token: UInt64
            if let existing = previous[key] {
                token = existing
            } else {
                token = nextToken
                nextToken += 1
            }
            tokens[key] = token

            resolved.append(
                MinimizedWindow(
                    token: token,
                    processIdentifier: processIdentifier,
                    index: entry.index,
                    title: entry.title,
                    applicationName: application.localizedName,
                    bundleIdentifier: application.bundleIdentifier,
                    applicationURL: application.bundleURL
                )
            )
        }

        tokensByProcess[processIdentifier] = tokens
        windowsByProcess[processIdentifier] = resolved
        publish()
    }

    private func publish() {
        let updated = windowsByProcess.values.flatMap { $0 }.sorted { $0.token < $1.token }
        guard updated != windows else { return }
        windows = updated
        DockLog.windows.info("\(updated.count, privacy: .public) minimized windows")
        onChange?()
    }
}
