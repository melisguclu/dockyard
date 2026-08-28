import DockCore
import Foundation
import Testing

private actor FrameRecordingInspector: WindowFrameInspecting {
    private(set) var reads: [pid_t] = []
    private(set) var writes: [CGRect] = []
    private var canned: [pid_t: [ManagedWindow]] = [:]

    func stub(_ windows: [ManagedWindow], for processIdentifier: pid_t) {
        canned[processIdentifier] = windows
    }

    func readCount() -> Int { reads.count }

    func written() -> [CGRect] { writes }

    func windows(processIdentifier: pid_t) async -> [ManagedWindow] {
        reads.append(processIdentifier)
        return canned[processIdentifier] ?? []
    }

    func resize(_ window: ManagedWindow, to frame: CGRect, processIdentifier: pid_t) async -> Bool {
        writes.append(frame)
        canned[processIdentifier] = (canned[processIdentifier] ?? []).map {
            $0.index == window.index ? ManagedWindow(index: $0.index, frame: frame) : $0
        }
        return true
    }
}

@MainActor
@Suite("Windows are kept clear of the bar only when the setting is on")
struct ScreenSpaceReserverTests {
    private let display = CGRect(x: 0, y: 0, width: 1512, height: 982)

    private func application(_ pid: pid_t) -> RunningApplicationState {
        RunningApplicationState(
            processIdentifier: pid,
            bundleIdentifier: "com.example.app\(pid)",
            bundleURL: URL(fileURLWithPath: "/Applications/App\(pid).app"),
            localizedName: "App \(pid)",
            isActive: false,
            isHidden: false,
            launchSequence: UInt64(pid)
        )
    }

    private var overlapping: ManagedWindow {
        ManagedWindow(index: 0, frame: CGRect(x: 0, y: 25, width: 1512, height: 957))
    }

    private var area: ReservedArea {
        ReservedArea(display: display, thickness: 70, edge: .bottom)
    }

    @Test("Off by default, so nothing is read and nothing is resized")
    func offByDefault() async {
        let inspector = FrameRecordingInspector()
        await inspector.stub([overlapping], for: 10)
        let reserver = ScreenSpaceReserver(inspector: inspector, authorization: { true })

        reserver.setReservedAreas([area])
        reserver.update(with: [application(10)])
        await reserver.settle()

        #expect(!reserver.isEnabled)
        #expect(await inspector.readCount() == 0)
        #expect(await inspector.written().isEmpty)
    }

    @Test("Without an Accessibility grant the setting does nothing at all")
    func withoutAuthorization() async {
        let inspector = FrameRecordingInspector()
        await inspector.stub([overlapping], for: 10)
        let reserver = ScreenSpaceReserver(inspector: inspector, authorization: { false })

        reserver.setEnabled(true)
        reserver.setReservedAreas([area])
        reserver.update(with: [application(10)])
        await reserver.settle()

        #expect(await inspector.readCount() == 0)
    }

    @Test("A window over the bar is resized once, and the settled state is left alone")
    func resizesOnce() async {
        let inspector = FrameRecordingInspector()
        await inspector.stub([overlapping], for: 10)
        let reserver = ScreenSpaceReserver(inspector: inspector, authorization: { true })

        reserver.setEnabled(true)
        reserver.setReservedAreas([area])
        reserver.update(with: [application(10)])
        await reserver.settle()

        #expect(await inspector.written() == [CGRect(x: 0, y: 25, width: 1512, height: 887)])

        reserver.update(with: [application(10)])
        await reserver.settle()

        #expect(await inspector.written().count == 1)
    }

    @Test("With no bar to keep clear of, nothing is read")
    func noReservedAreas() async {
        let inspector = FrameRecordingInspector()
        await inspector.stub([overlapping], for: 10)
        let reserver = ScreenSpaceReserver(inspector: inspector, authorization: { true })

        reserver.setEnabled(true)
        reserver.update(with: [application(10)])
        await reserver.settle()

        #expect(await inspector.readCount() == 0)
    }

    @Test("Turning it off stops the work and leaves the windows where they are")
    func turningItOff() async {
        let inspector = FrameRecordingInspector()
        await inspector.stub([overlapping], for: 10)
        let reserver = ScreenSpaceReserver(inspector: inspector, authorization: { true })

        reserver.setEnabled(true)
        reserver.setReservedAreas([area])
        reserver.setEnabled(false)
        reserver.update(with: [application(10)])
        await reserver.settle()

        #expect(await inspector.written().isEmpty)
    }
}
