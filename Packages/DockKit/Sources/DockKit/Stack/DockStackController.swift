import AppKit
import DockCore
import Foundation

public struct DockStackRequest {
    public let identifier: DockTileID
    public let url: URL
    public let presentation: FolderPresentation
    public let anchor: CGRect
    public let orientation: DockOrientation
    public let screen: CGRect
    public let appearance: NSAppearance?

    public init(
        identifier: DockTileID,
        url: URL,
        presentation: FolderPresentation,
        anchor: CGRect,
        orientation: DockOrientation,
        screen: CGRect,
        appearance: NSAppearance?
    ) {
        self.identifier = identifier
        self.url = url
        self.presentation = presentation
        self.anchor = anchor
        self.orientation = orientation
        self.screen = screen
        self.appearance = appearance
    }

    func opening(_ folder: URL) -> DockStackRequest {
        DockStackRequest(
            identifier: identifier,
            url: folder,
            presentation: presentation,
            anchor: anchor,
            orientation: orientation,
            screen: screen,
            appearance: appearance
        )
    }
}

@MainActor
public final class DockStackController {
    public private(set) var identifier: DockTileID?
    public var onDismiss: (@MainActor (DockTileID?) -> Void)?

    public var isVisible: Bool { identifier != nil }

    private let iconProvider: IconProvider
    private let reader: any FolderStackReading
    private let metrics: DockStackMetrics
    private let panel: DockMenuPanel
    private let backdrop = DockMenuBackdrop()
    private let activator = ApplicationActivator()

    private var content: DockStackContentView?
    private var monitors: [Any] = []
    private var readTask: Task<Void, Never>?
    private var iconTask: Task<Void, Never>?

    public init(
        iconProvider: IconProvider,
        reader: any FolderStackReading = FolderStackReader(),
        metrics: DockStackMetrics = .current
    ) {
        self.iconProvider = iconProvider
        self.reader = reader
        self.metrics = metrics
        panel = DockMenuPanel.make()
        panel.contentView?.addSubview(backdrop.view)
    }

    deinit {
        readTask?.cancel()
        iconTask?.cancel()
    }

    public func present(_ request: DockStackRequest) {
        identifier = request.identifier
        readTask?.cancel()
        let reader = reader
        let arrangement = request.presentation.arrangement
        readTask = Task { @MainActor [weak self] in
            let contents = await reader.contents(of: request.url, arrangement: arrangement)
            guard !Task.isCancelled, let self, self.identifier == request.identifier else { return }
            self.readTask = nil
            self.show(contents, for: request)
        }
    }

    public func dismiss() {
        guard identifier != nil else { return }
        finish()
    }

    public func tearDown() {
        readTask?.cancel()
        iconTask?.cancel()
        stopMonitoring()
        identifier = nil
        onDismiss = nil
        content?.removeFromSuperview()
        content = nil
        panel.orderOut(nil)
    }

    private func show(_ contents: FolderStackContents, for request: DockStackRequest) {
        let rows = Self.rows(for: contents)
        let layout = DockStackGeometry.layout(
            DockStackLayoutInput(
                textWidths: rows.map {
                    DockStackContentView.textWidth(
                        of: $0.title,
                        mode: .list,
                        metrics: metrics
                    )
                },
                requested: contents.entries.isEmpty ? .list : request.presentation.showAs,
                anchor: request.anchor,
                orientation: request.orientation,
                screen: request.screen,
                truncated: contents.truncated,
                metrics: metrics
            )
        )
        let trimmed = Self.trim(rows, to: layout)

        let view = DockStackContentView(rows: trimmed, layout: layout, metrics: metrics)
        view.frame = layout.balloon.contentFrame
        view.onSelect = { [weak self] index in
            self?.select(index, rows: trimmed, contents: contents, request: request)
        }
        view.onCancel = { [weak self] in
            self?.finish()
        }

        content?.removeFromSuperview()
        content = view

        panel.appearance = request.appearance
        panel.setFrame(layout.balloon.panelFrame, display: false)
        panel.contentView?.frame = CGRect(origin: .zero, size: layout.balloon.panelFrame.size)
        backdrop.apply(
            path: DockMenuLayout.path(for: layout.balloon, metrics: metrics.balloon),
            bounds: CGRect(origin: .zero, size: layout.balloon.panelFrame.size)
        )
        panel.contentView?.addSubview(view, positioned: .above, relativeTo: backdrop.view)

        panel.orderFrontRegardless()
        panel.makeKey()
        panel.makeFirstResponder(view)
        panel.invalidateShadow()
        startMonitoring()
        loadIcons(for: contents, layout: layout, into: view)

        DockLog.rendering.debug(
            """
            Stack \(String(describing: layout.mode), privacy: .public) with \
            \(layout.visibleCount, privacy: .public) of \
            \(contents.entries.count + contents.truncated, privacy: .public) items
            """
        )
    }

    private func select(
        _ index: Int,
        rows: [DockStackRow],
        contents: FolderStackContents,
        request: DockStackRequest
    ) {
        guard index < rows.count else { return }
        let row = rows[index]
        guard row.isSelectable else { return }
        if row.isOverflow {
            finish()
            activator.openFolder(contents.url)
            return
        }
        guard index < contents.entries.count else { return }
        let entry = contents.entries[index]
        guard entry.isDirectory else {
            finish()
            activator.open(entry.url)
            return
        }
        present(request.opening(entry.url))
    }

    private func loadIcons(
        for contents: FolderStackContents,
        layout: DockStackLayout,
        into view: DockStackContentView
    ) {
        iconTask?.cancel()
        let entries = Array(contents.entries.prefix(layout.visibleCount))
        guard !entries.isEmpty else { return }
        let pixelSize = Int(
            (metrics.iconSize(for: layout.mode) * (panel.backingScaleFactor)).rounded(.up)
        )
        let provider = iconProvider
        iconTask = Task { @MainActor [weak view] in
            for entry in entries {
                let image = await provider.image(for: IconRequest(entry: entry, pixelSize: max(pixelSize, 16)))
                guard !Task.isCancelled, let view else { return }
                view.setIcon(image, forKey: entry.url.path)
            }
        }
    }

    private static func rows(for contents: FolderStackContents) -> [DockStackRow] {
        guard contents.isReadable else {
            return [.message(DockStackStrings.unreadable)]
        }
        guard !contents.isEmpty else {
            return [.message(DockStackStrings.empty)]
        }
        return contents.entries.map(DockStackRow.entry)
    }

    private static func trim(_ rows: [DockStackRow], to layout: DockStackLayout) -> [DockStackRow] {
        var trimmed = Array(rows.prefix(layout.visibleCount))
        if layout.hasOverflowRow {
            trimmed.append(.overflow(DockStackStrings.overflow(layout.overflowCount)))
        }
        return trimmed
    }

    private func finish() {
        readTask?.cancel()
        readTask = nil
        iconTask?.cancel()
        iconTask = nil
        stopMonitoring()
        let dismissed = identifier
        identifier = nil
        panel.orderOut(nil)
        content?.removeFromSuperview()
        content = nil
        onDismiss?(dismissed)
    }

    private func startMonitoring() {
        guard monitors.isEmpty else { return }
        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .otherMouseDown]

        let outside: (NSEvent) -> Void = { [weak self] _ in
            MainActor.assumeIsolated { self?.dismiss() }
        }
        let inside: (NSEvent) -> NSEvent? = { [weak self] event in
            MainActor.assumeIsolated {
                guard let self, event.window !== self.panel else { return }
                self.dismiss()
            }
            return event
        }

        if let global = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: outside) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: mask, handler: inside) {
            monitors.append(local)
        }
    }

    private func stopMonitoring() {
        for monitor in monitors {
            NSEvent.removeMonitor(monitor)
        }
        monitors.removeAll()
    }
}
