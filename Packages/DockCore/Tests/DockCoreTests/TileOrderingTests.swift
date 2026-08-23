import DockCore
import Foundation
import Testing

@Suite("Tile ordering reproduces the system Dock's arrangement")
struct TileOrderingTests {
    private func tiles(
        _ fixture: Fixture,
        running: [RunningApplicationState] = [],
        trashIsEmpty: Bool = true,
        environment: TileEnvironment = TestEnvironment.standard
    ) -> [DockTile] {
        TileOrdering.tiles(
            preferences: fixture.resolved(environment: environment),
            running: running,
            trashIsEmpty: trashIsEmpty
        )
    }

    @Test("An empty Dock still renders Finder, a separator, and the Trash")
    func emptyDock() {
        let result = tiles(.minimal)

        #expect(result.count == 3)
        #expect(result[0].bundleIdentifier == "com.apple.finder")
        #expect(result[1].isSeparator)
        #expect(result[2].isTrash)
    }

    @Test("Finder is always the first tile and is never duplicated")
    func finderIsPermanent() {
        for fixture in Fixture.allCases {
            let result = tiles(fixture, running: [
                TestApplications.running(
                    bundleIdentifier: "com.apple.finder",
                    path: "/System/Library/CoreServices/Finder.app",
                    pid: 50,
                    sequence: 0,
                    name: "Finder"
                )
            ])
            #expect(result.first?.bundleIdentifier == "com.apple.finder", "in \(fixture.rawValue)")
            #expect(result.first?.isRunning == true)
            #expect(result.filter { $0.bundleIdentifier == "com.apple.finder" }.count == 1)
        }
    }

    @Test("A machine where Finder cannot be resolved still renders the rest")
    func finderMissing() {
        let result = tiles(.typical, environment: TestEnvironment.withoutFinder)

        #expect(result.contains { $0.bundleIdentifier == "com.apple.finder" } == false)
        #expect(result.first?.bundleIdentifier == "com.apple.Safari")
        #expect(result.last?.isTrash == true)
    }

    @Test("Pinned applications keep their domain order")
    func pinnedOrder() {
        let result = tiles(.typical).filter(\.isApplication)

        #expect(result.map(\.bundleIdentifier).prefix(4) == [
            "com.apple.finder",
            "com.apple.Safari",
            "com.apple.mail",
            "com.apple.dt.Xcode"
        ])
        #expect(result.dropFirst().allSatisfy { $0.isRunning == false })
    }

    @Test("A running pinned app gains an indicator instead of a second tile")
    func runningPinnedCoalesces() {
        let result = tiles(.typical, running: [
            TestApplications.running(
                bundleIdentifier: "com.apple.Safari",
                path: "/Applications/Safari.app",
                pid: 100,
                sequence: 0,
                isActive: true
            )
        ])

        let safari = result.filter { $0.bundleIdentifier == "com.apple.Safari" }
        #expect(safari.count == 1)
        #expect(safari[0].isRunning)
        #expect(safari[0].isActive)
        #expect(safari[0].isPinned)
    }

    @Test("Running applications that are not pinned follow the pinned section in launch order")
    func runningOnlyOrder() {
        let result = tiles(.typical, running: [
            TestApplications.running(
                bundleIdentifier: "com.figma.Desktop",
                path: "/Applications/Figma.app",
                pid: 300,
                sequence: 7,
                name: "Figma"
            ),
            TestApplications.running(
                bundleIdentifier: "com.tinyspeck.slackmacgap",
                path: "/Applications/Slack.app",
                pid: 200,
                sequence: 3,
                name: "Slack"
            )
        ])

        let identifiers = result.compactMap(\.bundleIdentifier)
        let slack = identifiers.firstIndex(of: "com.tinyspeck.slackmacgap")
        let figma = identifiers.firstIndex(of: "com.figma.Desktop")
        let xcode = identifiers.firstIndex(of: "com.apple.dt.Xcode")

        #expect(slack != nil)
        #expect(figma != nil)
        #expect(xcode != nil)
        if let slack, let figma, let xcode {
            #expect(xcode < slack)
            #expect(slack < figma)
        }
        #expect(result.first { $0.bundleIdentifier == "com.tinyspeck.slackmacgap" }?.isPinned == false)
    }

    @Test("A running app without a bundle identifier coalesces into the pinned tile by path")
    func pathMatching() {
        let result = tiles(.typical, running: [
            TestApplications.running(
                bundleIdentifier: nil,
                path: "/Applications/Xcode.app",
                pid: 400,
                sequence: 1
            )
        ])

        let xcode = result.first { $0.bundleIdentifier == "com.apple.dt.Xcode" }
        #expect(xcode?.isRunning == true)
        #expect(result.contains { $0.id == .path("/Applications/Xcode.app") } == false)
    }

    @Test("Recent applications appear only when the Dock shows them")
    func recentsHonourPreference() {
        let withRecents = tiles(.typical)
        #expect(withRecents.contains { $0.bundleIdentifier == "com.apple.Notes" })

        let withoutRecents = tiles(.withFolders)
        #expect(withoutRecents.contains { $0.bundleIdentifier == "com.apple.Notes" } == false)
    }

    @Test("A separator precedes the persistent-others section")
    func separatorPlacement() {
        let result = tiles(.withFolders)
        guard let separator = result.firstIndex(where: \.isSeparator) else {
            Issue.record("expected a separator")
            return
        }

        #expect(result[..<separator].allSatisfy { !$0.isSeparator })
        #expect(result[(separator + 1)...].contains { $0.label == "Downloads" })
        #expect(result.last?.isTrash == true)
    }

    @Test("The separator is always present and always immediately precedes the Trash region")
    func separatorAlwaysPresent() {
        for fixture in Fixture.allCases {
            let result = tiles(fixture)
            let separators = result.filter(\.isSeparator)
            #expect(separators.count == 1, "in \(fixture.rawValue)")

            guard let index = result.firstIndex(where: \.isSeparator) else { continue }
            #expect(index < result.count - 1)
            #expect(result[(index + 1)...].contains { $0.isTrash })
            #expect(result[..<index].contains { $0.isTrash } == false)
        }
    }

    @Test("Spacers keep their position and width")
    func spacerPlacement() {
        let result = tiles(.withSpacers)

        #expect(result.compactMap(\.spacerWidth) == [.full, .small, .flexible])
        #expect(result[0].bundleIdentifier == "com.apple.finder")
        #expect(result[1].bundleIdentifier == "com.apple.Safari")
        #expect(result[2].spacerWidth == .full)
        #expect(result[3].bundleIdentifier == "com.apple.dt.Xcode")
    }

    @Test("Every tile identity in a snapshot is unique")
    func identitiesAreUnique() {
        for fixture in Fixture.allCases {
            let result = tiles(fixture, running: [
                TestApplications.running(
                    bundleIdentifier: "com.apple.Safari",
                    path: "/Applications/Safari.app",
                    pid: 1,
                    sequence: 0
                ),
                TestApplications.running(
                    bundleIdentifier: "com.apple.Safari",
                    path: "/Applications/Safari.app",
                    pid: 2,
                    sequence: 1
                )
            ])
            #expect(Set(result.map(\.id)).count == result.count, "duplicate ids in \(fixture.rawValue)")
        }
    }

    @Test("Hidden state is only set when every instance is hidden")
    func hiddenState() {
        let partiallyHidden = tiles(.typical, running: [
            TestApplications.running(
                bundleIdentifier: "com.apple.Safari",
                path: "/Applications/Safari.app",
                pid: 1,
                sequence: 0,
                isHidden: true
            ),
            TestApplications.running(
                bundleIdentifier: "com.apple.Safari",
                path: "/Applications/Safari.app",
                pid: 2,
                sequence: 1,
                isHidden: false
            )
        ])
        #expect(partiallyHidden.first { $0.bundleIdentifier == "com.apple.Safari" }?.isHidden == false)

        let fullyHidden = tiles(.typical, running: [
            TestApplications.running(
                bundleIdentifier: "com.apple.Safari",
                path: "/Applications/Safari.app",
                pid: 1,
                sequence: 0,
                isHidden: true
            )
        ])
        #expect(fullyHidden.first { $0.bundleIdentifier == "com.apple.Safari" }?.isHidden == true)
    }

    @Test("The Trash reflects its contents")
    func trashState() {
        #expect(tiles(.minimal, trashIsEmpty: true).last?.kind == .trash(isEmpty: true))
        #expect(tiles(.minimal, trashIsEmpty: false).last?.kind == .trash(isEmpty: false))
    }

    @Test("Ordering is deterministic for identical inputs")
    func deterministicOutput() {
        let running = [
            TestApplications.running(
                bundleIdentifier: "com.apple.mail",
                path: "/System/Applications/Mail.app",
                pid: 9,
                sequence: 2
            )
        ]
        #expect(tiles(.typical, running: running) == tiles(.typical, running: running))
    }
}
