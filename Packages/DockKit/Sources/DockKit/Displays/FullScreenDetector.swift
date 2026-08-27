import AppKit
import CoreGraphics
import DockCore
import Foundation

public struct OnScreenWindow: Sendable, Equatable {
    public let layer: Int
    public let bounds: CGRect

    public init(layer: Int, bounds: CGRect) {
        self.layer = layer
        self.bounds = bounds
    }
}

public enum FullScreenDetector {
    public static let coverageTolerance: CGFloat = 1
    public static let normalWindowLayer = 0

    public static func covers(_ window: OnScreenWindow, _ display: DisplayInfo) -> Bool {
        guard window.layer == normalWindowLayer else { return false }
        let frame = display.frame
        let bounds = window.bounds
        return abs(bounds.minX - frame.minX) <= coverageTolerance
            && abs(bounds.minY - frame.minY) <= coverageTolerance
            && abs(bounds.maxX - frame.maxX) <= coverageTolerance
            && abs(bounds.maxY - frame.maxY) <= coverageTolerance
    }

    public static func coveredDisplays(
        windows: [OnScreenWindow],
        displays: [DisplayInfo]
    ) -> Set<CGDirectDisplayID> {
        var covered: Set<CGDirectDisplayID> = []
        for display in displays where windows.contains(where: { covers($0, display) }) {
            covered.insert(display.displayID)
        }
        return covered
    }

    @MainActor
    public static func onScreenWindows() -> [OnScreenWindow] {
        guard
            let windows = CGWindowListCopyWindowInfo(.optionOnScreenOnly, kCGNullWindowID)
                as? [[String: Any]]
        else { return [] }

        let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
        return windows.compactMap { window in
            guard let layer = window[kCGWindowLayer as String] as? Int,
                layer == normalWindowLayer,
                let boundsDictionary = window[kCGWindowBounds as String] as? [String: Any],
                let bounds = CGRect(dictionaryRepresentation: boundsDictionary as CFDictionary)
            else { return nil }
            return OnScreenWindow(
                layer: layer,
                bounds: CoordinateSpace.cgToCocoa(bounds, primaryHeight: primaryHeight)
            )
        }
    }

    @MainActor
    public static func currentlyCoveredDisplays(_ displays: [DisplayInfo]) -> Set<CGDirectDisplayID> {
        coveredDisplays(windows: onScreenWindows(), displays: displays)
    }
}
