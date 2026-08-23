import Foundation

@MainActor
public final class DockPreferencesWatcher {
    public static let distributedNotificationName = Notification.Name("com.apple.dock.prefchanged")

    private var observer: NSObjectProtocol?
    private var directoryWatcher: DirectoryWatcher?
    private var onChange: (@MainActor () -> Void)?

    public init() {}

    public func start(onChange: @escaping @MainActor () -> Void) {
        self.onChange = onChange
        startDistributedNotificationObserver()
        startDirectoryWatcher()
    }

    public func stop() {
        if let observer {
            DistributedNotificationCenter.default().removeObserver(observer)
            self.observer = nil
        }
        directoryWatcher?.stop()
        directoryWatcher = nil
    }

    private func startDistributedNotificationObserver() {
        observer = DistributedNotificationCenter.default().addObserver(
            forName: Self.distributedNotificationName,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                DockLog.preferences.debug("Dock preference change notification")
                self?.onChange?()
            }
        }
    }

    private func startDirectoryWatcher() {
        let preferences = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Preferences", isDirectory: true)

        let watcher = DirectoryWatcher(url: preferences) { [weak self] in
            DockLog.preferences.debug("Preferences directory changed")
            self?.onChange?()
        }
        watcher.start()
        directoryWatcher = watcher
    }
}
