import AppKit
import CoreGraphics
import DockCore
import Foundation

@MainActor
public enum SystemDockLocator {
    public static func hostDisplayID(appearance: DockAppearance) -> CGDirectDisplayID? {
        if let identifier = displayWithReservedEdge(appearance: appearance) {
            return identifier
        }
        return displayFromWindowBounds()
    }

    public static func hostsSystemDock(_ display: DisplayInfo, appearance: DockAppearance) -> Bool {
        reservedStrip(of: display, appearance: appearance) != nil
    }

    public static func reservedStrip(
        of display: DisplayInfo,
        appearance: DockAppearance
    ) -> CGFloat? {
        let inset: CGFloat
        switch appearance.orientation {
        case .bottom:
            inset = display.visibleFrame.minY - display.frame.minY
        case .left:
            inset = display.visibleFrame.minX - display.frame.minX
        case .right:
            inset = display.frame.maxX - display.visibleFrame.maxX
        }
        return inset > 1 ? inset : nil
    }

    public static func edgeMargin(
        snapshot: DockSnapshot,
        metrics: DockMetrics
    ) -> CGFloat? {
        let appearance = snapshot.appearance
        guard !appearance.autoHide else { return nil }
        for display in DisplayEnumerator.current() {
            guard let strip = reservedStrip(of: display, appearance: appearance) else { continue }
            let available = appearance.orientation.isVertical ? display.frame.height : display.frame.width
            let hosted = appearance.withTileSize(
                DockGeometry.fittedTileSize(
                    tiles: snapshot.tiles,
                    appearance: appearance,
                    metrics: metrics,
                    available: available
                )
            )
            return strip - DockGeometry.barThickness(hosted, metrics)
        }
        return nil
    }

    private static func displayWithReservedEdge(appearance: DockAppearance) -> CGDirectDisplayID? {
        DisplayEnumerator.current()
            .first { hostsSystemDock($0, appearance: appearance) }?
            .displayID
    }

    private static func displayFromWindowBounds() -> CGDirectDisplayID? {
        guard let windows = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        let dockLayer = Int(CGWindowLevelForKey(.dockWindow))
        let candidates = windows.filter { window in
            guard let owner = window[kCGWindowOwnerName as String] as? String, owner == "Dock" else {
                return false
            }
            guard let layer = window[kCGWindowLayer as String] as? Int, layer == dockLayer else {
                return false
            }
            return true
        }

        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0

        var best: (area: CGFloat, displayID: CGDirectDisplayID)?
        for window in candidates {
            guard let boundsDictionary = window[kCGWindowBounds as String] as? [String: Any],
                let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary)
            else { continue }

            let cocoaBounds = CoordinateSpace.cgToCocoa(bounds, primaryHeight: primaryHeight)
            for display in DisplayEnumerator.current() {
                let intersection = display.frame.intersection(cocoaBounds)
                guard !intersection.isNull else { continue }
                let area = intersection.width * intersection.height
                if area > (best?.area ?? 0) {
                    best = (area, display.displayID)
                }
            }
        }

        return best?.displayID
    }
}
