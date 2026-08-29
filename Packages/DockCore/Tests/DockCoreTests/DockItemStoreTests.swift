import DockCore
import Foundation
import Testing

private actor RecordingDockItemInspector: DockItemInspecting {
    private(set) var reads = 0
    private var canned = DockItemList.empty

    init(_ list: DockItemList = .empty) {
        canned = list
    }

    func stub(_ list: DockItemList) {
        canned = list
    }

    func readCount() -> Int { reads }

    func read(processIdentifier: pid_t) async -> DockItemList {
        reads += 1
        return canned
    }
}

@MainActor
@Suite("The Dock's item list is read on events, never on a clock")
struct DockItemStoreTests {
    private func list(_ badge: String?) -> DockItemList {
        DockItemList(items: [
            DockItem(index: 0, kind: .application, title: "Mail", badge: badge, locator: "/Applications/Mail.app")
        ])
    }

    @Test("Without Accessibility the store holds nothing and reads nothing")
    func unauthorizedStoreIsInert() async {
        let inspector = RecordingDockItemInspector(list("1"))
        let store = DockItemStore(inspector: inspector, authorization: { false })

        store.refresh()
        await store.settle()

        #expect(store.items.isEmpty)
        #expect(await inspector.readCount() == 0)
    }

    @Test("A read that changes nothing publishes nothing")
    func repeatedReadsPublishOnce() async {
        let inspector = RecordingDockItemInspector(list("1"))
        let store = DockItemStore(inspector: inspector, authorization: { true })
        var changes = 0
        store.onChange = { changes += 1 }

        for _ in 0..<5 {
            store.refresh()
            await store.settle()
        }

        #expect(changes == 1)
        #expect(store.items.items.first?.badge == "1")
    }

    @Test("A badge that changes publishes once more")
    func badgeChangePublishes() async {
        let inspector = RecordingDockItemInspector(list("1"))
        let store = DockItemStore(inspector: inspector, authorization: { true })
        var changes = 0
        store.onChange = { changes += 1 }

        store.refresh()
        await store.settle()
        await inspector.stub(list("2"))
        store.refresh()
        await store.settle()

        #expect(changes == 2)
        #expect(store.items.items.first?.badge == "2")
    }

    @Test("Overlapping refreshes collapse into one further read")
    func overlappingRefreshesCollapse() async {
        let inspector = RecordingDockItemInspector(list(nil))
        let store = DockItemStore(inspector: inspector, authorization: { true })

        store.refresh()
        store.refresh()
        store.refresh()
        await store.settle()

        #expect(await inspector.readCount() <= 2)
    }
}
