import Combine
import DockCore
import Foundation
import Testing

@Suite("Snapshots only change when the rendered state changes")
struct SnapshotDiffTests {
    private func snapshot(
        _ fixture: Fixture,
        running: [RunningApplicationState] = [],
        generation: UInt64 = 1
    ) -> DockSnapshot {
        DockSnapshot(
            tiles: TileOrdering.tiles(
                preferences: fixture.resolved(),
                running: running,
                trashIsEmpty: true
            ),
            appearance: fixture.raw.appearance,
            generation: generation
        )
    }

    @Test("Identical inputs produce equal tile arrays")
    func equalInputsAreEqual() {
        #expect(snapshot(.typical).tiles == snapshot(.typical).tiles)
    }

    @Test("An unrelated activation does not change the tiles")
    func unrelatedActivationIsInvisible() {
        let before = snapshot(.typical, running: [
            TestApplications.running(
                bundleIdentifier: "com.apple.Safari",
                path: "/Applications/Safari.app",
                pid: 1,
                sequence: 0,
                isActive: true
            )
        ])
        let afterUnrelatedFocusChange = snapshot(.typical, running: [
            TestApplications.running(
                bundleIdentifier: "com.apple.Safari",
                path: "/Applications/Safari.app",
                pid: 1,
                sequence: 0,
                isActive: true
            )
        ])
        #expect(before.tiles == afterUnrelatedFocusChange.tiles)
    }

    @Test("A launch changes only the affected tile's flags")
    func launchChangesOneTile() {
        let idle = snapshot(.typical)
        let launched = snapshot(.typical, running: [
            TestApplications.running(
                bundleIdentifier: "com.apple.mail",
                path: "/System/Applications/Mail.app",
                pid: 5,
                sequence: 0
            )
        ])

        #expect(idle.tiles != launched.tiles)
        #expect(idle.tiles.map(\.id) == launched.tiles.map(\.id))

        let changed = zip(idle.tiles, launched.tiles).filter { $0 != $1 }
        #expect(changed.count == 1)
        #expect(changed.first?.1.bundleIdentifier == "com.apple.mail")
    }

    @Test("Identity survives reordering so the renderer can move layers")
    func reorderPreservesIdentity() {
        let original = snapshot(.typical).tiles
        let reordered = Array(original.reversed())

        #expect(Set(original.map(\.id)) == Set(reordered.map(\.id)))
        #expect(original != reordered)
    }

    @Test("Appearance changes alone are enough to publish")
    func appearanceIsPartOfEquality() {
        let base = snapshot(.typical)
        let resized = DockSnapshot(
            tiles: base.tiles,
            appearance: DockAppearance(tileSize: 64),
            generation: base.generation
        )
        #expect(base != resized)
        #expect(base.tiles == resized.tiles)
    }

    @Test("Generation is not part of rendered equality")
    func generationIsMetadata() {
        let first = snapshot(.typical, generation: 1)
        let second = snapshot(.typical, generation: 99)

        #expect(first.tiles == second.tiles)
        #expect(first.appearance == second.appearance)
        #expect(first != second)
    }

    @MainActor
    @Test("The store publishes once per genuine change and never for a repeat")
    func storePublishesOnlyOnChange() async {
        let store = DockStateStore(
            reader: Fixture.typical.reader,
            environment: TestEnvironment.standard
        )
        let counter = PublishCounter()
        let cancellable = store.snapshots
            .dropFirst()
            .sink { _ in
                MainActor.assumeIsolated { counter.value += 1 }
            }

        await store.reloadPreferencesNow()
        #expect(counter.value == 1)
        #expect(store.snapshot.generation == 1)

        await store.reloadPreferencesNow()
        #expect(counter.value == 1)
        #expect(store.snapshot.generation == 1)

        cancellable.cancel()
    }
}

@MainActor
private final class PublishCounter {
    var value = 0
}
