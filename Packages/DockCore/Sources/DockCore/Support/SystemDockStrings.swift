import Foundation

public enum SystemDockStrings {
    public enum Table: String, Sendable {
        case menus = "DockMenus"
        case localizable = "Localizable"
        case accessibility = "Accessibility"
    }

    public struct Entry: Sendable, Hashable {
        public let table: Table
        public let name: String

        public init(table: Table, name: String) {
            self.table = table
            self.name = name
        }
    }

    public static let bundlePath = "/System/Library/CoreServices/Dock.app"

    public static let mapping: [String: Entry] = [
        "tile.finder": Entry(table: .localizable, name: "FinderName"),
        "tile.trash": Entry(table: .localizable, name: "TrashName"),
        "menu.open": Entry(table: .menus, name: "OPEN"),
        "menu.showInFinder": Entry(table: .menus, name: "SHOW_IN_FINDER"),
        "menu.show": Entry(table: .menus, name: "SHOW"),
        "menu.showAllWindows": Entry(table: .menus, name: "SHOW_ALL_WINDOWS"),
        "menu.hide": Entry(table: .menus, name: "HIDE"),
        "menu.quit": Entry(table: .menus, name: "QUIT"),
        "menu.forceQuit": Entry(table: .menus, name: "FORCE_QUIT"),
        "menu.dockSettings": Entry(table: .menus, name: "DOCK_SETTINGS"),
        "stack.empty": Entry(table: .localizable, name: "NO_ITEMS"),
        "accessibility.application": Entry(table: .accessibility, name: "AXApplicationDockItem"),
        "accessibility.folder": Entry(table: .accessibility, name: "AXFolderDockItem"),
        "accessibility.webLocation": Entry(table: .accessibility, name: "AXURLDockItem"),
        "accessibility.trash": Entry(table: .accessibility, name: "AXTrashDockItem"),
        "accessibility.minimizedWindow": Entry(table: .accessibility, name: "AXMinimizedWindowDockItem"),
        "accessibility.separator": Entry(table: .accessibility, name: "AXSeparatorDockItem"),
        "accessibility.spacer": Entry(table: .accessibility, name: "AXSpacerDockItem"),
    ]

    public static func string(for key: String, fallback: String) -> String {
        guard let entry = mapping[key], let bundle = Bundle(path: bundlePath) else { return fallback }
        return NSLocalizedString(
            entry.name,
            tableName: entry.table.rawValue,
            bundle: bundle,
            value: fallback,
            comment: ""
        )
    }
}
