import AppKit
import DockCore
import Foundation

public enum DockDropPolicy {
    public static func operation(for tile: DockTile, allowed: NSDragOperation) -> NSDragOperation {
        switch tile.kind {
        case .application:
            return .copy
        case .trash:
            return allowed.contains(.move) ? .move : []
        case .folder, .url, .minimizedWindow, .separator, .spacer:
            return []
        }
    }
}
