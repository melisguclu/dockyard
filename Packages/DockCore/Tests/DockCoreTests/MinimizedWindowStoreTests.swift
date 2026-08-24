import DockCore
import Foundation
import Testing

private actor WindowRecordingInspector: AppMenuInspecting {
    private(set) var windowReads: [pid_t] = []
    private var canned: [pid_t: [AppWindowEntry]] = [:]

    func stub(_ entries: [AppWindowEntry], for processIdentifier: pid_t) {
        canned[processIdentifier] = entries
    }

    func reads() -> [pid_t] { windowReads }

    func snapshot(processIdentifier: pid_t) async -> AppMenuSnapshot {
        AppMenuSnapshot(processIdentifier: processIdentifier, commands: [], windows: [])
    }

    func windows(processIdentifier: pid_t) async -> [AppWindowEntry] {
        windowReads.append(processIdentifier)
        return canned[processIdentifier] ?? []
    }

    func perform(_ command: AppMenuCommand, processIdentifier: pid_t) async -> Bool { true }

    func raise(_ window: AppWindowEntry, processIdentifier: pid_t) async -> Bool { true }
}

@MainActor
@Suite("The minimized window store reads only when the state it depends on changes")
struct MinimizedWindowStoreTests {
    private func application(_ pid: pid_t, isActive: Bool = false) -> RunningApplicationState {
        RunningApplicationState(
            processIdentifier: pid,
            bundleIdentifier: "com.example.app\(pid)",
            bundleURL: URL(fileURLWithPath: "/Applications/App\(pid).app"),
            localizedName: "App \(pid)",
            isActive: isActive,
            isHidden: false,
            launchSequence: UInt64(pid)
        )
    }

    private func minimized(_ title: String, index: Int = 0) -> AppWindowEntry {
        AppWindowEntry(index: index, title: title, isMinimized: true)
    }

    @Test("An unchanged running set costs no Accessibility traffic at all")
    func repeatedUpdatesAreFree() async {
        let inspector = WindowRecordingInspector()
        await inspector.stub([minimized("One")], for: 10)
        let store = MinimizedWindowStore(inspector: inspector, authorization: { true })
        let applications = [application(10, isActive: true), application(11)]

        store.update(with: applications)
        await store.settle()
        let first = await inspector.reads().count

        for _ in 0..<20 {
            store.update(with: applications)
            await store.settle()
        }

        #expect(await inspector.reads().count == first)
        #expect(store.windows.map(\.title) == ["One"])
    }

    @Test("A launching application is read once and a terminating one is dropped")
    func readsEachApplicationOnce() async {
        let inspector = WindowRecordingInspector()
        await inspector.stub([minimized("One")], for: 10)
        await inspector.stub([minimized("Two")], for: 11)
        let store = MinimizedWindowStore(inspector: inspector, authorization: { true })

        store.update(with: [application(10, isActive: true)])
        await store.settle()
        store.update(with: [application(10, isActive: true), application(11)])
        await store.settle()

        #expect(await inspector.reads() == [10, 11])
        #expect(store.windows.map(\.title) == ["One", "Two"])

        store.update(with: [application(10, isActive: true)])
        await store.settle()
        #expect(store.windows.map(\.title) == ["One"])
    }

    @Test("Bringing another application forward re-reads only that application")
    func activationRereadsOneApplication() async {
        let inspector = WindowRecordingInspector()
        await inspector.stub([minimized("One")], for: 10)
        await inspector.stub([minimized("Two")], for: 11)
        let store = MinimizedWindowStore(inspector: inspector, authorization: { true })

        store.update(with: [application(10, isActive: true), application(11)])
        await store.settle()
        store.update(with: [application(10), application(11, isActive: true)])
        await store.settle()

        #expect(await inspector.reads() == [10, 11, 11])
    }

    @Test("A window keeps its tile identity across a re-read, and a new one lands last")
    func tokensAreStable() async {
        let inspector = WindowRecordingInspector()
        await inspector.stub([minimized("One"), minimized("Two", index: 1)], for: 10)
        let store = MinimizedWindowStore(inspector: inspector, authorization: { true })

        store.update(with: [application(10, isActive: true)])
        await store.settle()
        let tokens = store.windows.map(\.token)

        await inspector.stub(
            [minimized("One"), minimized("Two", index: 1), minimized("Three", index: 2)],
            for: 10
        )
        store.update(with: [application(10), application(11, isActive: true)])
        await store.settle()
        store.update(with: [application(10, isActive: true), application(11)])
        await store.settle()

        #expect(Array(store.windows.map(\.token).prefix(2)) == tokens)
        #expect(store.windows.map(\.title) == ["One", "Two", "Three"])
    }
}

@MainActor
@Suite("Without an Accessibility grant the store is inert")
struct UnauthorizedMinimizedWindowStoreTests {
    @Test("Nothing is read and nothing is published")
    func inert() async {
        let inspector = WindowRecordingInspector()
        await inspector.stub([AppWindowEntry(index: 0, title: "One", isMinimized: true)], for: 10)
        let store = MinimizedWindowStore(inspector: inspector, authorization: { false })

        store.update(
            with: [
                RunningApplicationState(
                    processIdentifier: 10,
                    bundleIdentifier: "com.example.app",
                    bundleURL: URL(fileURLWithPath: "/Applications/App.app"),
                    localizedName: "App",
                    isActive: true,
                    isHidden: false,
                    launchSequence: 0
                )
            ]
        )
        await store.settle()

        #expect(await inspector.reads().isEmpty)
        #expect(store.windows.isEmpty)
    }
}
