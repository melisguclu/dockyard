import AppKit
import DockCore

@main
@MainActor
enum DockyardMain {
    static func main() {
        guard !isAlreadyRunning else {
            DockLog.app.error("Another Dockyard instance is already running")
            return
        }

        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        application.run()
    }

    private static var isAlreadyRunning: Bool {
        guard let identifier = Bundle.main.bundleIdentifier else { return false }
        let instances = NSRunningApplication.runningApplications(withBundleIdentifier: identifier)
        return instances.count > 1
    }
}
