import DockCore
import Foundation
import Testing

@MainActor
@Suite("A bounce lasts exactly as long as the launch it belongs to")
struct LaunchActivityObserverTests {
    private let safari = DockTileID.bundle("com.apple.Safari")
    private let mail = DockTileID.bundle("com.apple.mail")

    @Test("A launch bounces from the first notification until the application reports it is up")
    func launchAndFinish() {
        let observer = LaunchActivityObserver()

        observer.handle(.willLaunch(processIdentifier: 10, identifier: safari, isFinishedLaunching: false))
        #expect(observer.launching == [safari])

        observer.handle(.didLaunch(processIdentifier: 10))
        #expect(observer.launching.isEmpty)
    }

    @Test("An application that is already up does not bounce when something opens it again")
    func alreadyRunning() {
        let observer = LaunchActivityObserver()

        observer.handle(.willLaunch(processIdentifier: 10, identifier: safari, isFinishedLaunching: true))

        #expect(observer.launching.isEmpty)
    }

    @Test("An application that comes up without a launch notification still ends its bounce")
    func upWithoutDidLaunch() {
        let observer = LaunchActivityObserver()

        observer.handle(.willLaunch(processIdentifier: 10, identifier: safari, isFinishedLaunching: false))
        #expect(observer.launching == [safari])

        observer.handle(.isUp(processIdentifier: 10))
        #expect(observer.launching.isEmpty)
    }

    @Test("A process that dies on the way up ends its own bounce")
    func terminationEndsIt() {
        let observer = LaunchActivityObserver()

        observer.handle(.willLaunch(processIdentifier: 10, identifier: safari, isFinishedLaunching: false))
        observer.handle(.didTerminate(processIdentifier: 10))

        #expect(observer.launching.isEmpty)
    }

    @Test("Another application coming forward does not end a launch of its own")
    func unrelatedApplication() {
        let observer = LaunchActivityObserver()

        observer.handle(.willLaunch(processIdentifier: 10, identifier: safari, isFinishedLaunching: false))
        observer.handle(.isUp(processIdentifier: 11))

        #expect(observer.launching == [safari])
    }

    @Test("Two launches at once are two bounces, each ending on its own")
    func twoLaunches() {
        let observer = LaunchActivityObserver()

        observer.handle(.willLaunch(processIdentifier: 10, identifier: safari, isFinishedLaunching: false))
        observer.handle(.willLaunch(processIdentifier: 11, identifier: mail, isFinishedLaunching: false))
        #expect(observer.launching == [safari, mail])

        observer.handle(.didLaunch(processIdentifier: 11))
        #expect(observer.launching == [safari])
    }

    @Test("Every change is published once, and a repeat publishes nothing")
    func publishesOncePerChange() {
        let observer = LaunchActivityObserver()
        var published: [Set<DockTileID>] = []
        observer.onChange = { published.append($0) }

        observer.handle(.willLaunch(processIdentifier: 10, identifier: safari, isFinishedLaunching: false))
        observer.handle(.willLaunch(processIdentifier: 10, identifier: safari, isFinishedLaunching: false))
        observer.handle(.didLaunch(processIdentifier: 10))
        observer.handle(.didLaunch(processIdentifier: 10))

        #expect(published == [[safari], []])
    }
}
