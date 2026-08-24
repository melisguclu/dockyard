import AppKit
import Combine
import DockCore
import DockKit
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let preferences = Preferences()
    private let store = DockStateStore()
    private let displayObserver = DisplayConfigurationObserver()
    private lazy var coordinator = DisplayCoordinator(
        iconProvider: store.iconProvider,
        appMenuStore: store.appMenuStore,
        minimizedWindowStore: store.minimizedWindowStore
    )

    private var accessibilityObserver: NSObjectProtocol?
    private var statusItemController: StatusItemController?
    private var settingsWindowController: SettingsWindowController?
    private var cancellables: Set<AnyCancellable> = []

    func applicationDidFinishLaunching(_ notification: Notification) {
        let state = DockLog.signposts.beginInterval("cold-start")

        coordinator.policy = preferences
        coordinator.onDisplaysChanged = { [weak self] displays in
            self?.updateKnownDisplays(displays)
        }

        preferences.onChange = { [weak self] in
            self?.coordinator.reconcile()
        }

        store.snapshots
            .sink { snapshot in
                MainActor.assumeIsolated { [weak self] in
                    self?.coordinator.apply(snapshot)
                }
            }
            .store(in: &cancellables)

        displayObserver.start(
            onBegin: { [weak self] in
                self?.coordinator.beginReconfiguration()
            },
            onSettled: { [weak self] in
                self?.coordinator.reconcile()
            }
        )

        statusItemController = StatusItemController(
            preferences: preferences,
            onOpenSettings: { [weak self] in self?.openSettings() },
            onRefresh: { [weak self] in self?.refresh() },
            onQuit: { NSApplication.shared.terminate(nil) }
        )

        accessibilityObserver = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.accessibility.api"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.preferences.refreshAppMenuAuthorization()
                self.store.refreshRunningApplications()
            }
        }

        store.start()
        coordinator.reconcile()

        DockLog.signposts.endInterval("cold-start", state)
        DockLog.app.info("Dockyard started")
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let accessibilityObserver {
            DistributedNotificationCenter.default().removeObserver(accessibilityObserver)
        }
        store.stop()
        displayObserver.stop()
        coordinator.tearDown()
    }

    private func refresh() {
        store.reloadPreferences()
        store.refreshRunningApplications()
        coordinator.reconcile()
    }

    private func openSettings() {
        if settingsWindowController == nil {
            settingsWindowController = SettingsWindowController(preferences: preferences)
        }
        preferences.refreshLaunchAtLoginState()
        preferences.refreshAppMenuAuthorization()
        settingsWindowController?.present()
    }

    private func updateKnownDisplays(_ displays: [DisplayInfo]) {
        let appearance = store.snapshot.appearance
        let descriptors = displays.map { display in
            DisplayDescriptor(
                identity: display.identity,
                name: DisplayEnumerator.screen(for: display.displayID)?.localizedName
                    ?? (display.identity.isBuiltIn ? "Built-in Display" : "External Display"),
                isBuiltIn: display.identity.isBuiltIn,
                hostsSystemDock: SystemDockLocator.hostsSystemDock(display, appearance: appearance)
            )
        }
        guard descriptors != preferences.knownDisplays else { return }
        preferences.knownDisplays = descriptors
    }
}

extension Preferences: DisplayPolicyProviding {
    func panelIsEnabled(on identity: DisplayIdentity) -> Bool {
        isEnabled(identity)
    }

    var suppressesPanelOnSystemDockDisplay: Bool {
        suppressOnSystemDockDisplay
    }
}
