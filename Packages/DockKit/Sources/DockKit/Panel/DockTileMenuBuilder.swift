import DockCore
import Foundation

public enum DockTileMenuCommand: Sendable, Equatable {
    case activate
    case open
    case showInFinder
    case hide
    case unhide
    case quit
    case forceQuit
    case dockSettings
    case appMenu(AppMenuCommand)
    case window(AppWindowEntry)
}

public enum DockTileMenuBuilder {
    public static let maximumTitleLength = 44

    struct Section {
        let items: [DockMenuItem]
        let trimPriority: Int?

        init(_ items: [DockMenuItem], trimPriority: Int? = nil) {
            self.items = items
            self.trimPriority = trimPriority
        }
    }

    public static func items(
        for tile: DockTile,
        appMenu: AppMenuSnapshot? = nil,
        availableHeight: CGFloat = .infinity,
        metrics: DockMenuMetrics = .current
    ) -> [DockMenuItem] {
        switch tile.kind {
        case .application:
            return joined(
                trimmed(
                    applicationSections(for: tile, appMenu: appMenu),
                    availableHeight: availableHeight,
                    metrics: metrics
                )
            )
        case .folder:
            return [
                .command(.open, title: DockMenuStrings.open),
                .command(.showInFinder, title: DockMenuStrings.showInFinder),
            ]
        case .url, .trash:
            return [.command(.open, title: DockMenuStrings.open)]
        case .minimizedWindow:
            return [.command(.activate, title: DockMenuStrings.show)]
        case .separator:
            return [.command(.dockSettings, title: DockMenuStrings.dockSettings)]
        case .spacer:
            return []
        }
    }

    public static func windowItems(
        for tile: DockTile,
        appMenu: AppMenuSnapshot?,
        availableHeight: CGFloat = .infinity,
        metrics: DockMenuMetrics = .current
    ) -> [DockMenuItem] {
        guard case .application = tile.kind, tile.isRunning else { return [] }
        guard let windows = appMenu?.windows, !windows.isEmpty else { return [] }
        let section = Section(
            windows.map { DockMenuItem.command(.window($0), title: truncated($0.title)) },
            trimPriority: 0
        )
        return joined(trimmed([section], availableHeight: availableHeight, metrics: metrics))
    }

    static func truncated(_ title: String) -> String {
        guard title.count > maximumTitleLength else { return title }
        let budget = maximumTitleLength - 1
        let head = budget - budget / 3
        let tail = budget - head
        return "\(title.prefix(head))…\(title.suffix(tail))"
    }

    private static func applicationSections(
        for tile: DockTile,
        appMenu: AppMenuSnapshot?
    ) -> [Section] {
        var sections: [Section] = []

        if tile.isRunning, let appMenu {
            sections.append(
                Section(
                    appMenu.commands.map { DockMenuItem.command(.appMenu($0), title: $0.title) },
                    trimPriority: 0
                )
            )
            sections.append(
                Section(
                    appMenu.recents.map { DockMenuItem.command(.appMenu($0), title: truncated($0.title)) },
                    trimPriority: 2
                )
            )
            sections.append(
                Section(
                    appMenu.windows.map { DockMenuItem.command(.window($0), title: truncated($0.title)) },
                    trimPriority: 1
                )
            )
        }

        if tile.isRunning {
            sections.append(
                Section([
                    .command(.activate, title: DockMenuStrings.show),
                    .command(
                        tile.isHidden ? .unhide : .hide,
                        title: tile.isHidden ? DockMenuStrings.showAllWindows : DockMenuStrings.hide
                    ),
                ])
            )
        } else {
            sections.append(Section([.command(.activate, title: DockMenuStrings.open)]))
        }

        if tile.url != nil {
            sections.append(Section([.command(.showInFinder, title: DockMenuStrings.showInFinder)]))
        }

        if tile.isRunning {
            sections.append(
                Section([
                    .command(.quit, title: DockMenuStrings.quit),
                    .command(.forceQuit, title: DockMenuStrings.forceQuit),
                ])
            )
        }

        return sections
    }

    static func trimmed(
        _ sections: [Section],
        availableHeight: CGFloat,
        metrics: DockMenuMetrics
    ) -> [Section] {
        var sections = sections.filter { !$0.items.isEmpty }
        while height(of: sections, metrics: metrics) > availableHeight {
            let trimmable = sections.indices.filter {
                sections[$0].trimPriority != nil && !sections[$0].items.isEmpty
            }
            guard
                let index = trimmable.max(by: {
                    (sections[$0].trimPriority ?? 0) < (sections[$1].trimPriority ?? 0)
                })
            else { break }
            sections[index] = Section(
                sections[index].items.dropLast(),
                trimPriority: sections[index].trimPriority
            )
            sections = sections.filter { !$0.items.isEmpty }
        }
        return sections
    }

    static func height(of sections: [Section], metrics: DockMenuMetrics) -> CGFloat {
        let rows = sections.reduce(0) { $0 + $1.items.count }
        let separators = max(sections.filter { !$0.items.isEmpty }.count - 1, 0)
        return 2 * metrics.verticalPadding
            + CGFloat(rows) * metrics.rowHeight
            + CGFloat(separators) * metrics.separatorHeight
            + metrics.tailLength
    }

    private static func joined(_ sections: [Section]) -> [DockMenuItem] {
        var items: [DockMenuItem] = []
        for section in sections where !section.items.isEmpty {
            if !items.isEmpty {
                items.append(.separator)
            }
            items.append(contentsOf: section.items)
        }
        return items
    }
}
