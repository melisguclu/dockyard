import Foundation
import os

public enum DockLog {
    public static let subsystem = "com.dockyard.app"

    public static let preferences = Logger(subsystem: subsystem, category: "preferences")
    public static let workspace = Logger(subsystem: subsystem, category: "workspace")
    public static let icons = Logger(subsystem: subsystem, category: "icons")
    public static let store = Logger(subsystem: subsystem, category: "store")
    public static let displays = Logger(subsystem: subsystem, category: "displays")
    public static let rendering = Logger(subsystem: subsystem, category: "rendering")
    public static let app = Logger(subsystem: subsystem, category: "app")
    public static let appMenus = Logger(subsystem: subsystem, category: "app-menus")

    public static let signposts = OSSignposter(subsystem: subsystem, category: "performance")
}
