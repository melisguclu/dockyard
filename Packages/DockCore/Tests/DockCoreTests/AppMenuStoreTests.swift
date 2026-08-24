import DockCore
import Foundation
import Testing

private actor RecordingInspector: AppMenuInspecting {
    private(set) var fullReads: [pid_t] = []
    private(set) var windowReads: [pid_t] = []
    private var canned: [pid_t: AppMenuSnapshot] = [:]

    func stub(_ snapshot: AppMenuSnapshot) {
        canned[snapshot.processIdentifier] = snapshot
    }

    func snapshot(processIdentifier: pid_t) async -> AppMenuSnapshot {
        fullReads.append(processIdentifier)
        return canned[processIdentifier]
            ?? AppMenuSnapshot(processIdentifier: processIdentifier, commands: [], windows: [])
    }

    func windows(processIdentifier: pid_t) async -> [AppWindowEntry] {
        windowReads.append(processIdentifier)
        return canned[processIdentifier]?.windows ?? []
    }

    func perform(_ command: AppMenuCommand, processIdentifier: pid_t) async -> Bool { true }

    func raise(_ window: AppWindowEntry, processIdentifier: pid_t) async -> Bool { true }
}

@MainActor
@Suite("The app menu store reads only when the state it depends on changes")
struct AppMenuStoreTests {
    private func application(_ pid: pid_t, bundle: String, isActive: Bool = false) -> RunningApplicationState {
        RunningApplicationState(
            processIdentifier: pid,
            bundleIdentifier: bundle,
            bundleURL: URL(fileURLWithPath: "/Applications/\(bundle).app"),
            localizedName: bundle,
            isActive: isActive,
            isHidden: false,
            launchSequence: UInt64(pid)
        )
    }

    private func tile(_ bundle: String) -> DockTile {
        DockTile(
            id: .bundle(bundle),
            kind: .application,
            label: bundle,
            url: URL(fileURLWithPath: "/Applications/\(bundle).app"),
            bundleIdentifier: bundle,
            isRunning: true
        )
    }

    private func populated(_ pid: pid_t) -> AppMenuSnapshot {
        AppMenuSnapshot(
            processIdentifier: pid,
            commands: [AppMenuCommand(kind: .creation, menuTitle: "File", title: "New Window", shortcut: nil)],
            windows: [AppWindowEntry(index: 0, title: "Window", isMinimized: false)]
        )
    }

    @Test("An unseen application is read once, and repeated snapshots do not read it again")
    func readsEachApplicationOnce() async {
        let inspector = RecordingInspector()
        await inspector.stub(populated(10))
        let store = AppMenuStore(inspector: inspector)
        let applications = [application(10, bundle: "com.a", isActive: true)]

        store.update(with: applications)
        await store.settle()
        store.update(with: applications)
        store.update(with: applications)
        await store.settle()

        #expect(await inspector.fullReads == [10])
        #expect(await inspector.windowReads.isEmpty)
    }

    @Test("A rebuild that changes nothing costs no Accessibility traffic at all")
    func idleRebuildsAreFree() async {
        let inspector = RecordingInspector()
        await inspector.stub(populated(10))
        await inspector.stub(populated(11))
        let store = AppMenuStore(inspector: inspector)
        let applications = [
            application(10, bundle: "com.a", isActive: true),
            application(11, bundle: "com.b"),
        ]

        store.update(with: applications)
        await store.settle()
        for _ in 0..<20 {
            store.update(with: applications)
        }
        await store.settle()

        #expect(await inspector.fullReads.count == 2)
        #expect(await inspector.windowReads.isEmpty)
    }

    @Test("Bringing another application forward re-reads only that application's windows")
    func activationRefreshesWindows() async {
        let inspector = RecordingInspector()
        await inspector.stub(populated(10))
        await inspector.stub(populated(11))
        let store = AppMenuStore(inspector: inspector)

        store.update(with: [application(10, bundle: "com.a", isActive: true), application(11, bundle: "com.b")])
        await store.settle()
        store.update(with: [application(10, bundle: "com.a"), application(11, bundle: "com.b", isActive: true)])
        await store.settle()

        #expect(await inspector.windowReads == [11])
        #expect(await inspector.fullReads.count == 2)
    }

    @Test("An application that yielded nothing is retried in full when it next comes forward")
    func emptySnapshotIsRetried() async {
        let inspector = RecordingInspector()
        let store = AppMenuStore(inspector: inspector)

        store.update(with: [application(10, bundle: "com.a"), application(11, bundle: "com.b", isActive: true)])
        await store.settle()
        store.update(with: [application(10, bundle: "com.a", isActive: true), application(11, bundle: "com.b")])
        await store.settle()

        #expect(await inspector.fullReads == [10, 11, 10])
        #expect(await inspector.windowReads.isEmpty)
    }

    @Test("A tile resolves to its application's snapshot, and loses it when the app exits")
    func snapshotLifetime() async {
        let inspector = RecordingInspector()
        await inspector.stub(populated(10))
        let store = AppMenuStore(inspector: inspector)

        store.update(with: [application(10, bundle: "com.a", isActive: true)])
        await store.settle()
        #expect(store.snapshot(for: tile("com.a"))?.commands.count == 1)

        store.update(with: [])
        #expect(store.snapshot(for: tile("com.a")) == nil)
    }
}
