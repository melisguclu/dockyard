import AppKit
import DockCore
import Foundation

@MainActor
public protocol DisplayPolicyProviding: AnyObject {
    func panelIsEnabled(on identity: DisplayIdentity) -> Bool
    var suppressesPanelOnSystemDockDisplay: Bool { get }
}

@MainActor
public final class DisplayCoordinator {
    public static let poolGracePeriod: Duration = .seconds(120)

    public weak var policy: (any DisplayPolicyProviding)?
    public var onDisplaysChanged: (@MainActor ([DisplayInfo]) -> Void)?
    public private(set) var activeIdentities: [DisplayIdentity] = []

    private let iconProvider: IconProvider
    private let metrics: DockMetrics
    private var controllers: [DisplayIdentity: DockPanelController] = [:]
    private var pooled: [DisplayIdentity: DockPanelController] = [:]
    private var evictionTasks: [DisplayIdentity: Task<Void, Never>] = [:]
    private var snapshot: DockSnapshot = .empty
    private var isReconfiguring = false
    private var dayChangeObserver: NSObjectProtocol?

    public init(iconProvider: IconProvider, metrics: DockMetrics = .current) {
        self.iconProvider = iconProvider
        self.metrics = metrics
        dayChangeObserver = NotificationCenter.default.addObserver(
            forName: .NSCalendarDayChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshDynamicIcons()
            }
        }
    }

    public func refreshDynamicIcons() {
        DockLog.displays.debug("Refreshing dynamic icons")
        for controller in controllers.values {
            controller.refreshIcons()
        }
    }

    public func apply(_ snapshot: DockSnapshot) {
        self.snapshot = snapshot
        for controller in controllers.values {
            controller.apply(snapshot)
        }
        reconcile()
    }

    public func beginReconfiguration() {
        isReconfiguring = true
        for controller in controllers.values {
            controller.hide()
        }
    }

    public func reconcile() {
        isReconfiguring = false

        let displays = DisplayEnumerator.current().filter { !$0.isMirrorSecondary }
        let dockHost =
            policy?.suppressesPanelOnSystemDockDisplay == true
            ? SystemDockLocator.hostDisplayID(appearance: snapshot.appearance)
            : nil
        let maximumScale = DisplayEnumerator.maximumBackingScaleFactor()
        let reservedStrip = SystemDockLocator.reservedStrip(appearance: snapshot.appearance)

        var wanted: [DisplayIdentity] = []

        for display in displays {
            guard policy?.panelIsEnabled(on: display.identity) ?? true else { continue }
            guard display.displayID != dockHost else { continue }
            guard let screen = DisplayEnumerator.screen(for: display.displayID) else { continue }

            wanted.append(display.identity)
            let controller = controller(for: display)
            controller.bind(
                to: screen,
                displayID: display.displayID,
                maximumBackingScale: maximumScale,
                reservedStrip: reservedStrip
            )
            controller.apply(snapshot)
            controller.show()
        }

        for (identity, controller) in controllers where !wanted.contains(identity) {
            controller.hide()
            controllers.removeValue(forKey: identity)
            pool(controller, identity: identity)
        }

        activeIdentities = wanted
        onDisplaysChanged?(displays)
        DockLog.displays.debug("Reconciled \(wanted.count, privacy: .public) dock panels")
    }

    public func tearDown() {
        if let dayChangeObserver {
            NotificationCenter.default.removeObserver(dayChangeObserver)
            self.dayChangeObserver = nil
        }
        for task in evictionTasks.values {
            task.cancel()
        }
        evictionTasks.removeAll()
        for controller in controllers.values {
            controller.tearDown()
        }
        controllers.removeAll()
        for controller in pooled.values {
            controller.tearDown()
        }
        pooled.removeAll()
    }

    private func controller(for display: DisplayInfo) -> DockPanelController {
        if let existing = controllers[display.identity] {
            return existing
        }
        if let reused = pooled.removeValue(forKey: display.identity) {
            evictionTasks.removeValue(forKey: display.identity)?.cancel()
            controllers[display.identity] = reused
            return reused
        }
        let created = DockPanelController(
            identity: display.identity,
            displayID: display.displayID,
            iconProvider: iconProvider,
            metrics: metrics
        )
        controllers[display.identity] = created
        return created
    }

    private func pool(_ controller: DockPanelController, identity: DisplayIdentity) {
        pooled[identity] = controller
        evictionTasks[identity]?.cancel()
        evictionTasks[identity] = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.poolGracePeriod)
            guard !Task.isCancelled, let self else { return }
            self.evictionTasks.removeValue(forKey: identity)
            guard let pooledController = self.pooled.removeValue(forKey: identity) else { return }
            pooledController.tearDown()
        }
    }
}
