import Foundation

public enum TileOrdering {
    public static func tiles(
        preferences: ResolvedDockPreferences,
        running: [RunningApplicationState],
        minimizedWindows: [MinimizedWindow] = [],
        trashIsEmpty: Bool
    ) -> [DockTile] {
        var builder = Builder(running: running)

        if let finder = preferences.finder {
            builder.appendPinned(finder)
        }

        for entry in preferences.pinnedApps {
            builder.appendPinned(entry)
        }

        for application in builder.unmatchedRunningApplications() {
            builder.appendRunningOnly(application)
        }

        if preferences.appearance.showRecents {
            for entry in preferences.recents {
                builder.appendRecent(entry)
            }
        }

        builder.appendSeparator()

        if !preferences.appearance.minimizeToApplication {
            for window in minimizedWindows {
                builder.appendMinimizedWindow(window)
            }
        }

        for entry in preferences.others {
            builder.appendOther(entry)
        }

        builder.appendTrash(isEmpty: trashIsEmpty)

        return builder.tiles
    }

    private struct Builder {
        private(set) var tiles: [DockTile] = []
        private var usedIdentifiers: Set<DockTileID> = []
        private var spacerCount = 0
        private var matchedProcesses: Set<pid_t> = []
        private let running: [RunningApplicationState]
        private let runningByBundleIdentifier: [String: [RunningApplicationState]]
        private let runningByPath: [String: [RunningApplicationState]]

        init(running: [RunningApplicationState]) {
            self.running = running.sorted { $0.launchSequence < $1.launchSequence }
            runningByBundleIdentifier = Dictionary(
                grouping: running.filter { $0.bundleIdentifier != nil },
                by: { $0.bundleIdentifier ?? "" }
            )
            runningByPath = Dictionary(
                grouping: running.filter { $0.canonicalPath != nil },
                by: { $0.canonicalPath ?? "" }
            )
        }

        mutating func appendPinned(_ entry: DockEntry) {
            switch entry.kind {
            case .spacer(let width):
                appendSpacer(width)
            case .application:
                appendApplication(entry, isPinned: true)
            case .folder, .url:
                appendNonApplication(entry, isPinned: true)
            }
        }

        mutating func appendRecent(_ entry: DockEntry) {
            switch entry.kind {
            case .application:
                appendApplication(entry, isPinned: false)
            case .spacer, .folder, .url:
                break
            }
        }

        mutating func appendOther(_ entry: DockEntry) {
            switch entry.kind {
            case .spacer(let width):
                appendSpacer(width)
            case .application:
                appendApplication(entry, isPinned: true)
            case .folder, .url:
                appendNonApplication(entry, isPinned: true)
            }
        }

        mutating func appendRunningOnly(_ application: RunningApplicationState) {
            guard
                let identifier = identifier(
                    bundleIdentifier: application.bundleIdentifier,
                    path: application.canonicalPath
                )
            else { return }
            guard usedIdentifiers.insert(identifier).inserted else { return }

            tiles.append(
                DockTile(
                    id: identifier,
                    kind: .application,
                    label: application.localizedName,
                    url: application.bundleURL,
                    bundleIdentifier: application.bundleIdentifier,
                    isRunning: true,
                    isActive: application.isActive,
                    isHidden: application.isHidden,
                    isPinned: false
                )
            )
        }

        mutating func appendMinimizedWindow(_ window: MinimizedWindow) {
            let identifier = DockTileID.window(window.token)
            guard usedIdentifiers.insert(identifier).inserted else { return }
            tiles.append(window.tile)
        }

        mutating func appendSeparator() {
            let identifier = DockTileID.builtin(.separator)
            guard usedIdentifiers.insert(identifier).inserted else { return }
            tiles.append(DockTile(id: identifier, kind: .separator, label: ""))
        }

        mutating func appendTrash(isEmpty: Bool) {
            let identifier = DockTileID.builtin(.trash)
            guard usedIdentifiers.insert(identifier).inserted else { return }
            tiles.append(
                DockTile(
                    id: identifier,
                    kind: .trash(isEmpty: isEmpty),
                    label: "Trash",
                    url: TileEnvironment.trashDirectory
                )
            )
        }

        func unmatchedRunningApplications() -> [RunningApplicationState] {
            running.filter { !matchedProcesses.contains($0.processIdentifier) }
        }

        private mutating func appendSpacer(_ width: SpacerWidth) {
            let identifier = DockTileID.builtin(.spacer(index: spacerCount))
            spacerCount += 1
            usedIdentifiers.insert(identifier)
            tiles.append(DockTile(id: identifier, kind: .spacer(width: width), label: ""))
        }

        private mutating func appendApplication(_ entry: DockEntry, isPinned: Bool) {
            guard
                let identifier = identifier(
                    bundleIdentifier: entry.bundleIdentifier,
                    path: entry.canonicalPath
                )
            else { return }
            guard usedIdentifiers.insert(identifier).inserted else { return }

            let instances = matches(for: entry)
            for instance in instances {
                matchedProcesses.insert(instance.processIdentifier)
            }

            tiles.append(
                DockTile(
                    id: identifier,
                    kind: .application,
                    label: entry.label,
                    url: entry.url,
                    bundleIdentifier: entry.bundleIdentifier,
                    isRunning: !instances.isEmpty,
                    isActive: instances.contains { $0.isActive },
                    isHidden: !instances.isEmpty && instances.allSatisfy { $0.isHidden },
                    isPinned: isPinned
                )
            )
        }

        private mutating func appendNonApplication(_ entry: DockEntry, isPinned: Bool) {
            guard let url = entry.url else { return }
            let identifier = DockTileID.path(url.absoluteString)
            guard usedIdentifiers.insert(identifier).inserted else { return }

            let kind: DockTile.Kind
            switch entry.kind {
            case .folder(let presentation):
                kind = .folder(presentation)
            case .url:
                kind = .url
            case .application, .spacer:
                return
            }

            tiles.append(
                DockTile(
                    id: identifier,
                    kind: kind,
                    label: entry.label,
                    url: url,
                    bundleIdentifier: nil,
                    isPinned: isPinned
                )
            )
        }

        private func matches(for entry: DockEntry) -> [RunningApplicationState] {
            if let identifier = entry.bundleIdentifier, let instances = runningByBundleIdentifier[identifier] {
                return instances
            }
            if let path = entry.canonicalPath, let instances = runningByPath[path] {
                return instances
            }
            return []
        }

        private func identifier(bundleIdentifier: String?, path: String?) -> DockTileID? {
            DockTileID.application(bundleIdentifier: bundleIdentifier, path: path)
        }
    }
}
