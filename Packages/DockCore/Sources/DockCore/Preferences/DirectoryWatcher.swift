import Foundation

@MainActor
public final class DirectoryWatcher {
    private let url: URL
    private let debounce: Duration
    private var source: DispatchSourceFileSystemObject?
    private var descriptor: CInt = -1
    private var settleTask: Task<Void, Never>?
    private let handler: @MainActor () -> Void

    public init(url: URL, debounce: Duration = .milliseconds(50), handler: @escaping @MainActor () -> Void) {
        self.url = url
        self.debounce = debounce
        self.handler = handler
    }

    public func start() {
        guard source == nil else { return }

        descriptor = open(url.path, O_EVTONLY)
        guard descriptor >= 0 else {
            DockLog.preferences.error("Unable to watch directory")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .rename, .delete],
            queue: .main
        )
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.scheduleSettle()
            }
        }
        source.setCancelHandler { [descriptor] in
            close(descriptor)
        }
        source.activate()
        self.source = source
    }

    public func stop() {
        settleTask?.cancel()
        settleTask = nil
        source?.cancel()
        source = nil
        descriptor = -1
    }

    private func scheduleSettle() {
        settleTask?.cancel()
        let debounce = debounce
        let handler = handler
        settleTask = Task { @MainActor in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled else { return }
            handler()
        }
    }
}
