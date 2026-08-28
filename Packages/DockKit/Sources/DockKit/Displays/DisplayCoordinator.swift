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
    public static let spaceSettleDelay: Duration = .milliseconds(350)

    public weak var policy: (any DisplayPolicyProviding)?
    public var onDisplaysChanged: (@MainActor ([DisplayInfo]) -> Void)?
    public var onTrashChanged: (@MainActor () -> Void)?
    public var onReservedAreasChanged: (@MainActor ([ReservedArea]) -> Void)?
    public private(set) var activeIdentities: [DisplayIdentity] = []

    private let iconProvider: IconProvider
    private let appMenuStore: AppMenuStore?
    private let minimizedWindowStore: MinimizedWindowStore?
    private let metrics: DockMetrics
    private var controllers: [DisplayIdentity: DockPanelController] = [:]
    private var pooled: [DisplayIdentity: DockPanelController] = [:]
    private var evictionTasks: [DisplayIdentity: Task<Void, Never>] = [:]
    private var snapshot: DockSnapshot = .empty
    private var isReconfiguring = false
    private var dayChangeObserver: NSObjectProtocol?
    private var spaceObserver: NSObjectProtocol?
    private var accessibilityObserver: NSObjectProtocol?
    private var spaceSettleTask: Task<Void, Never>?
    private var coveredDisplays: Set<CGDirectDisplayID> = []
    private var launching: Set<DockTileID> = []
    private var reservationCandidates: [(displayID: CGDirectDisplayID, display: CGRect)] = []
    private var reservationThickness: CGFloat = 0
    private var reservationEdge: DockOrientation = .bottom
    private var publishedAreas: [ReservedArea] = []

    public init(
        iconProvider: IconProvider,
        appMenuStore: AppMenuStore? = nil,
        minimizedWindowStore: MinimizedWindowStore? = nil,
        metrics: DockMetrics = .current
    ) {
        self.iconProvider = iconProvider
        self.appMenuStore = appMenuStore
        self.minimizedWindowStore = minimizedWindowStore
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
        spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.spaceDidChange()
            }
        }
        accessibilityObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshAccessibilityAppearance()
            }
        }
    }

    public func setLaunching(_ identifiers: Set<DockTileID>) {
        guard launching != identifiers else { return }
        launching = identifiers
        for controller in controllers.values {
            controller.setLaunching(identifiers)
        }
    }

    public func focusPanelForKeyboard() {
        let pointer = NSEvent.mouseLocation
        let underPointer = controllers.values.first { controller in
            DisplayEnumerator.screen(for: controller.displayID)?.frame.contains(pointer) ?? false
        }
        guard let target = underPointer ?? controllers.values.first else { return }
        target.focusForKeyboard()
    }

    public func refreshAccessibilityAppearance() {
        let value = DockAccessibilityAppearance.current
        DockLog.displays.debug(
            "Accessibility appearance: reduceTransparency \(value.reduceTransparency, privacy: .public)"
        )
        for controller in controllers.values {
            controller.setAccessibilityAppearance(value)
        }
        for controller in pooled.values {
            controller.setAccessibilityAppearance(value)
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
        let edgeMargin = SystemDockLocator.edgeMargin(snapshot: snapshot, metrics: metrics)
        coveredDisplays = FullScreenDetector.currentlyCoveredDisplays(displays)

        var wanted: [DisplayIdentity] = []
        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        reservationCandidates = []
        reservationEdge = snapshot.appearance.orientation
        reservationThickness =
            DockGeometry.screenEdgeMargin(snapshot.appearance, metrics, measuredEdgeMargin: edgeMargin)
            + DockGeometry.barThickness(snapshot.appearance, metrics)

        for display in displays {
            guard policy?.panelIsEnabled(on: display.identity) ?? true else { continue }
            guard display.displayID != dockHost else { continue }
            guard let screen = DisplayEnumerator.screen(for: display.displayID) else { continue }

            wanted.append(display.identity)
            reservationCandidates.append(
                (
                    displayID: display.displayID,
                    display: CoordinateSpace.cocoaToCG(screen.frame, primaryHeight: primaryHeight)
                )
            )
            let controller = controller(for: display)
            controller.bind(
                to: screen,
                displayID: display.displayID,
                maximumBackingScale: maximumScale,
                measuredEdgeMargin: edgeMargin
            )
            controller.apply(snapshot)
            controller.setCoveredByFullScreen(coveredDisplays.contains(display.displayID))
            controller.setLaunching(launching)
            controller.show()
        }

        for (identity, controller) in controllers where !wanted.contains(identity) {
            controller.hide()
            controllers.removeValue(forKey: identity)
            pool(controller, identity: identity)
        }

        activeIdentities = wanted
        publishReservedAreas()
        onDisplaysChanged?(displays)
        DockLog.displays.debug("Reconciled \(wanted.count, privacy: .public) dock panels")
    }

    public func tearDown() {
        if let dayChangeObserver {
            NotificationCenter.default.removeObserver(dayChangeObserver)
            self.dayChangeObserver = nil
        }
        if let spaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(spaceObserver)
            self.spaceObserver = nil
        }
        if let accessibilityObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(accessibilityObserver)
            self.accessibilityObserver = nil
        }
        spaceSettleTask?.cancel()
        spaceSettleTask = nil
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

    private func spaceDidChange() {
        refreshFullScreenCoverage()
        spaceSettleTask?.cancel()
        spaceSettleTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: Self.spaceSettleDelay)
            guard !Task.isCancelled, let self else { return }
            self.spaceSettleTask = nil
            self.refreshFullScreenCoverage()
        }
    }

    public func refreshFullScreenCoverage() {
        guard !isReconfiguring else { return }
        let covered = FullScreenDetector.currentlyCoveredDisplays(DisplayEnumerator.current())
        guard covered != coveredDisplays else { return }
        coveredDisplays = covered
        DockLog.displays.debug("Full-screen displays: \(covered.count, privacy: .public)")
        for controller in controllers.values {
            controller.setCoveredByFullScreen(covered.contains(controller.displayID))
        }
        publishReservedAreas()
    }

    private func publishReservedAreas() {
        guard let handler = onReservedAreasChanged else { return }
        let areas =
            snapshot.appearance.autoHide
            ? []
            : reservationCandidates
                .filter { !coveredDisplays.contains($0.displayID) }
                .map {
                    ReservedArea(
                        display: $0.display,
                        thickness: reservationThickness,
                        edge: reservationEdge
                    )
                }
        guard areas != publishedAreas else { return }
        publishedAreas = areas
        DockLog.displays.debug("Reserving space on \(areas.count, privacy: .public) displays")
        handler(areas)
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
            appMenuStore: appMenuStore,
            minimizedWindowStore: minimizedWindowStore,
            metrics: metrics
        )
        created.onTrashChanged = { [weak self] in self?.onTrashChanged?() }
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
