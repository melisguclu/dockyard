import Foundation

@MainActor
public final class AppMenuStore {
    public var isAuthorized: Bool {
        AccessibilityAuthorization.isTrusted
    }

    private let inspector: any AppMenuInspecting
    private let activator = ApplicationActivator()

    private var snapshots: [pid_t: AppMenuSnapshot] = [:]
    private var identifiers: [String: pid_t] = [:]
    private var paths: [String: pid_t] = [:]
    private var refreshTasks: [pid_t: Task<Void, Never>] = [:]
    private var activeProcessIdentifier: pid_t?
    private var reportedAuthorization: Bool?

    public init(inspector: any AppMenuInspecting = AppMenuInspector()) {
        self.inspector = inspector
    }

    deinit {
        for task in refreshTasks.values {
            task.cancel()
        }
    }

    public func update(with applications: [RunningApplicationState]) {
        var live: Set<pid_t> = []
        var identifiers: [String: pid_t] = [:]
        var paths: [String: pid_t] = [:]

        for application in applications {
            live.insert(application.processIdentifier)
            if let identifier = application.bundleIdentifier {
                identifiers[identifier] = application.processIdentifier
            }
            if let path = application.canonicalPath {
                paths[path] = application.processIdentifier
            }
        }

        self.identifiers = identifiers
        self.paths = paths

        for (processIdentifier, task) in refreshTasks where !live.contains(processIdentifier) {
            task.cancel()
        }
        refreshTasks = refreshTasks.filter { live.contains($0.key) }
        snapshots = snapshots.filter { live.contains($0.key) }

        let active = applications.first { $0.isActive }?.processIdentifier
        let activationChanged = active != activeProcessIdentifier
        activeProcessIdentifier = active

        for application in applications {
            guard let cached = snapshots[application.processIdentifier] else {
                refresh(application.processIdentifier, includingCommands: true)
                continue
            }
            guard activationChanged, application.processIdentifier == active else { continue }
            refresh(application.processIdentifier, includingCommands: cached.isEmpty)
        }
    }

    public func settle() async {
        while let task = refreshTasks.values.first {
            await task.value
        }
    }

    public func snapshot(for tile: DockTile) -> AppMenuSnapshot? {
        guard let processIdentifier = processIdentifier(for: tile) else { return nil }
        return snapshots[processIdentifier]
    }

    public func perform(_ command: AppMenuCommand, on tile: DockTile) {
        guard let processIdentifier = processIdentifier(for: tile) else { return }
        if command.activatesApplication {
            activator.activateOrLaunch(tile)
        }
        let inspector = inspector
        Task {
            let performed = await inspector.perform(command, processIdentifier: processIdentifier)
            guard !performed else { return }
            DockLog.appMenus.error(
                """
                A \(String(describing: command.kind), privacy: .public) command under \
                \(command.menuTitle, privacy: .public) could not be performed: \
                \(command.title, privacy: .private)
                """
            )
        }
    }

    public func activate(_ window: AppWindowEntry, on tile: DockTile) {
        guard let processIdentifier = processIdentifier(for: tile) else { return }
        activator.activateOrLaunch(tile)
        let inspector = inspector
        Task {
            _ = await inspector.raise(window, processIdentifier: processIdentifier)
        }
    }

    private func processIdentifier(for tile: DockTile) -> pid_t? {
        if let identifier = tile.bundleIdentifier, let processIdentifier = identifiers[identifier] {
            return processIdentifier
        }
        guard let path = tile.url?.standardizedFileURL.path else { return nil }
        return paths[path]
    }

    private func refresh(_ processIdentifier: pid_t, includingCommands: Bool) {
        reportAuthorization()
        guard isAuthorized else { return }
        guard refreshTasks[processIdentifier] == nil else { return }
        let inspector = inspector
        refreshTasks[processIdentifier] = Task { @MainActor [weak self] in
            let updated: AppMenuSnapshot
            if includingCommands {
                updated = await inspector.snapshot(processIdentifier: processIdentifier)
            } else {
                let windows = await inspector.windows(processIdentifier: processIdentifier)
                let cached = self?.snapshots[processIdentifier]
                updated = AppMenuSnapshot(
                    processIdentifier: processIdentifier,
                    commands: cached?.commands ?? [],
                    recents: cached?.recents ?? [],
                    windows: windows
                )
            }
            guard let self, !Task.isCancelled else { return }
            self.snapshots[processIdentifier] = updated
            self.refreshTasks[processIdentifier] = nil
            DockLog.appMenus.info(
                """
                pid \(processIdentifier, privacy: .public): \(updated.commands.count, privacy: .public) commands, \
                \(updated.recents.count, privacy: .public) recents, \(updated.windows.count, privacy: .public) windows
                """
            )
        }
    }

    private func reportAuthorization() {
        let authorized = isAuthorized
        guard reportedAuthorization != authorized else { return }
        reportedAuthorization = authorized
        if authorized {
            DockLog.appMenus.info("Accessibility authorized, app menus are available")
        } else {
            DockLog.appMenus.error(
                "Accessibility not authorized, tile menus fall back to Dockyard's own commands"
            )
        }
    }
}
