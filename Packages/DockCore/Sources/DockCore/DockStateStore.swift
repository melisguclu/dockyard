import Combine
import Foundation

@MainActor
public final class DockStateStore {
    public private(set) var snapshot: DockSnapshot = .empty

    public var snapshots: AnyPublisher<DockSnapshot, Never> {
        subject.eraseToAnyPublisher()
    }

    public let iconProvider: IconProvider
    public let appMenuStore: AppMenuStore
    public let minimizedWindowStore: MinimizedWindowStore
    public let screenSpaceReserver: ScreenSpaceReserver
    public let launchActivity: LaunchActivityObserver

    private let subject: CurrentValueSubject<DockSnapshot, Never>
    private let reader: DockPreferencesReader
    private let environment: TileEnvironment
    private let runningObserver: RunningApplicationsObserver
    private let preferencesWatcher: DockPreferencesWatcher

    private var resolved: ResolvedDockPreferences = .empty
    private var generation: UInt64 = 0
    private var resolveTask: Task<Void, Never>?

    public init(
        reader: DockPreferencesReader = .live(),
        environment: TileEnvironment = .live,
        iconProvider: IconProvider = IconProvider(),
        runningObserver: RunningApplicationsObserver = RunningApplicationsObserver(),
        preferencesWatcher: DockPreferencesWatcher = DockPreferencesWatcher()
    ) {
        self.reader = reader
        self.environment = environment
        self.iconProvider = iconProvider
        self.runningObserver = runningObserver
        self.preferencesWatcher = preferencesWatcher
        appMenuStore = AppMenuStore()
        minimizedWindowStore = MinimizedWindowStore()
        screenSpaceReserver = ScreenSpaceReserver()
        launchActivity = LaunchActivityObserver()
        subject = CurrentValueSubject(.empty)
    }

    deinit {
        resolveTask?.cancel()
    }

    public func start() {
        minimizedWindowStore.onChange = { [weak self] in
            self?.rebuild()
        }
        minimizedWindowStore.start()
        screenSpaceReserver.start()
        launchActivity.start()
        runningObserver.start(
            onChange: { [weak self] in
                guard let self else { return }
                self.minimizedWindowStore.update(with: self.runningObserver.applications)
                self.screenSpaceReserver.update(with: self.runningObserver.applications)
                self.rebuild()
            },
            onLaunch: { [weak self] path in
                guard let self else { return }
                let provider = self.iconProvider
                Task { await provider.invalidate(cacheKey: path) }
            }
        )
        preferencesWatcher.start { [weak self] in
            self?.reloadPreferences()
        }
        minimizedWindowStore.update(with: runningObserver.applications)
        screenSpaceReserver.update(with: runningObserver.applications)
        reloadPreferences()
    }

    public func stop() {
        resolveTask?.cancel()
        resolveTask = nil
        preferencesWatcher.stop()
        launchActivity.stop()
        minimizedWindowStore.stop()
        screenSpaceReserver.stop()
    }

    public func reloadPreferences() {
        resolveTask?.cancel()
        resolveTask = Task { @MainActor [weak self] in
            await self?.reloadPreferencesNow()
        }
    }

    public func reloadPreferencesNow() async {
        let raw = reader.read()
        let previousLargeSize = resolved.appearance.largeSize
        let environment = environment

        let resolved = await Task.detached(priority: .utility) {
            ResolvedDockPreferences.resolve(raw, environment: environment)
        }.value
        guard !Task.isCancelled else { return }

        self.resolved = resolved
        if resolved.appearance.largeSize != previousLargeSize {
            await iconProvider.invalidateAll()
        }
        rebuild()
    }

    public func refreshRunningApplications() {
        runningObserver.refresh()
        minimizedWindowStore.update(with: runningObserver.applications)
        screenSpaceReserver.update(with: runningObserver.applications)
        rebuild()
    }

    public func rebuild() {
        let state = DockLog.signposts.beginInterval("snapshot-build")
        defer { DockLog.signposts.endInterval("snapshot-build", state) }

        appMenuStore.update(with: runningObserver.applications)

        let tiles = TileOrdering.tiles(
            preferences: resolved,
            running: runningObserver.applications,
            minimizedWindows: minimizedWindowStore.windows,
            trashIsEmpty: environment.trashIsEmpty()
        )

        guard tiles != snapshot.tiles || resolved.appearance != snapshot.appearance else { return }

        generation += 1
        snapshot = DockSnapshot(
            tiles: tiles,
            appearance: resolved.appearance,
            generation: generation
        )
        subject.send(snapshot)
    }
}
