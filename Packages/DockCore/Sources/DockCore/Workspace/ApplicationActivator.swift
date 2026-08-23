import AppKit
import Foundation

@MainActor
public struct ApplicationActivator {
    public init() {}

    public func activateOrLaunch(_ tile: DockTile) {
        if let bundleIdentifier = tile.bundleIdentifier, activateRunning(bundleIdentifier: bundleIdentifier) {
            return
        }
        if let url = tile.url, activateRunning(bundleURL: url) {
            return
        }
        guard let url = tile.url else {
            DockLog.workspace.error("Tile has no launchable URL")
            return
        }
        launch(url)
    }

    public func reveal(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    public func open(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    public func openFolder(_ url: URL) {
        NSWorkspace.shared.open(url)
    }

    public func openTrash() {
        guard let trash = TileEnvironment.trashDirectory else { return }
        NSWorkspace.shared.open(trash)
    }

    public func open(urls: [URL], withApplicationAt applicationURL: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(urls, withApplicationAt: applicationURL, configuration: configuration) { _, error in
            if let error {
                DockLog.workspace.error("Failed to open files: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    public func quit(_ tile: DockTile) {
        for application in runningApplications(for: tile) {
            application.terminate()
        }
    }

    public func forceQuit(_ tile: DockTile) {
        for application in runningApplications(for: tile) {
            application.forceTerminate()
        }
    }

    public func hide(_ tile: DockTile) {
        for application in runningApplications(for: tile) {
            application.hide()
        }
    }

    public func unhide(_ tile: DockTile) {
        for application in runningApplications(for: tile) {
            application.unhide()
        }
    }

    public func runningApplications(for tile: DockTile) -> [NSRunningApplication] {
        if let bundleIdentifier = tile.bundleIdentifier {
            let matches = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
            if !matches.isEmpty { return matches }
        }
        guard let path = tile.url?.standardizedFileURL.resolvingSymlinksInPath().path else { return [] }
        return NSWorkspace.shared.runningApplications.filter {
            $0.bundleURL?.standardizedFileURL.resolvingSymlinksInPath().path == path
        }
    }

    private func activateRunning(bundleIdentifier: String) -> Bool {
        let matches = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier)
        guard let application = matches.first else { return false }
        return activate(application)
    }

    private func activateRunning(bundleURL: URL) -> Bool {
        let path = bundleURL.standardizedFileURL.resolvingSymlinksInPath().path
        let match = NSWorkspace.shared.runningApplications.first {
            $0.bundleURL?.standardizedFileURL.resolvingSymlinksInPath().path == path
        }
        guard let application = match else { return false }
        return activate(application)
    }

    private func activate(_ application: NSRunningApplication) -> Bool {
        if application.isHidden {
            application.unhide()
        }
        return application.activate(options: [.activateAllWindows])
    }

    private func launch(_ url: URL) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            if let error {
                DockLog.workspace.error("Failed to launch application: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
