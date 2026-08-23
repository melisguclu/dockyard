#!/usr/bin/env swift

import AppKit
import CoreGraphics
import Foundation

let domain = "com.apple.dock" as CFString

func number(_ key: String, fallback: Double) -> Double {
    CFPreferencesAppSynchronize(domain)
    guard let value = CFPreferencesCopyAppValue(key as CFString, domain) as? NSNumber else {
        return fallback
    }
    return value.doubleValue
}

func boolean(_ key: String, fallback: Bool) -> Bool {
    guard let value = CFPreferencesCopyAppValue(key as CFString, domain) as? NSNumber else {
        return fallback
    }
    return value.boolValue
}

func text(_ key: String, fallback: String) -> String {
    guard let value = CFPreferencesCopyAppValue(key as CFString, domain) as? String else {
        return fallback
    }
    return value
}

func entries(_ key: String) -> [[String: Any]] {
    (CFPreferencesCopyAppValue(key as CFString, domain) as? [[String: Any]]) ?? []
}

let tileSize = number("tilesize", fallback: 48)
let largeSize = number("largesize", fallback: 128)
let orientation = text("orientation", fallback: "bottom")
let magnification = boolean("magnification", fallback: false)
let autohide = boolean("autohide", fallback: false)
let pinned = entries("persistent-apps")
let others = entries("persistent-others")

print("Dockyard calibration")
print("====================")
print("macOS                \(ProcessInfo.processInfo.operatingSystemVersionString)")
print("orientation          \(orientation)")
print("tilesize             \(tileSize)")
print("largesize            \(largeSize)")
print("magnification        \(magnification)")
print("autohide             \(autohide)")
print("persistent-apps      \(pinned.count)")
print("persistent-others    \(others.count)")
print("")

print("Displays")
print("--------")
var reservedStrip: Double?
for screen in NSScreen.screens {
    let frame = screen.frame
    let visible = screen.visibleFrame
    let bottom = Double(visible.minY - frame.minY)
    let left = Double(visible.minX - frame.minX)
    let right = Double(frame.maxX - visible.maxX)
    let top = Double(frame.maxY - visible.maxY)
    print("\(screen.localizedName)")
    print("  frame            \(frame)")
    print("  visibleFrame     \(visible)")
    print("  insets           bottom \(bottom)  left \(left)  right \(right)  top \(top)")
    print("  scale            \(screen.backingScaleFactor)")

    let candidate: Double
    switch orientation {
    case "left": candidate = left
    case "right": candidate = right
    default: candidate = bottom
    }
    if candidate > 1, reservedStrip == nil {
        reservedStrip = candidate
        print("  hosts the system Dock")
    }
}
print("")

print("Dock windows at dock level")
print("-------------------------")
let dockLevel = Int(CGWindowLevelForKey(.dockWindow))
let windows = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] ?? []
let dockWindows = windows.filter {
    ($0[kCGWindowOwnerName as String] as? String) == "Dock"
        && ($0[kCGWindowLayer as String] as? Int) == dockLevel
}
if dockWindows.isEmpty {
    print("none found; the Dock may be hidden or on another Space")
}
for window in dockWindows {
    let raw = window[kCGWindowBounds as String] as? [String: Any] ?? [:]
    if let bounds = CGRect(dictionaryRepresentation: raw as CFDictionary) {
        print("  bounds \(bounds)")
        let coversWholeDisplay = NSScreen.screens.contains { $0.frame.size == bounds.size }
        print("  covers a whole display: \(coversWholeDisplay)")
    }
}
print("")

print("Derived ratios")
print("--------------")
if autohide {
    print("Auto-hide is on: the reserved strip is unavailable. Switch it off and rerun.")
} else if let reservedStrip {
    print("reservedStrip                \(reservedStrip)")
    print("reservedStrip / tilesize     \(reservedStrip / tileSize)")
    print("")
    print("Dockyard uses reservedStrip directly at runtime, so its bar sits at the same")
    print("distance from the screen edge as the real Dock. The ratio above is the fallback")
    print("used when the Dock is hidden or on no display: it should equal")
    print("(tilesize + 2 * barPadding + screenEdgeMargin) / tilesize.")
} else {
    print("No display reserves an edge, so the Dock is hidden or auto-hidden.")
}
print("")
print("Inter-tile spacing and bar padding cannot be derived from window bounds on macOS 26:")
print("the Dock's dock-level window spans its entire display. Measure them from a screenshot")
print("of the Dock at a known tilesize and update DockMetrics in Packages/DockKit.")
