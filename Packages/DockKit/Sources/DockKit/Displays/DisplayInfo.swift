import AppKit
import CoreGraphics
import DockCore
import Foundation

public struct DisplayInfo: Sendable, Equatable, Identifiable {
    public let identity: DisplayIdentity
    public let displayID: CGDirectDisplayID
    public let frame: CGRect
    public let visibleFrame: CGRect
    public let backingScaleFactor: CGFloat
    public let isMirrorSecondary: Bool

    public var id: CGDirectDisplayID { displayID }

    public init(
        identity: DisplayIdentity,
        displayID: CGDirectDisplayID,
        frame: CGRect,
        visibleFrame: CGRect,
        backingScaleFactor: CGFloat,
        isMirrorSecondary: Bool
    ) {
        self.identity = identity
        self.displayID = displayID
        self.frame = frame
        self.visibleFrame = visibleFrame
        self.backingScaleFactor = backingScaleFactor
        self.isMirrorSecondary = isMirrorSecondary
    }
}

@MainActor
public enum DisplayEnumerator {
    public static func displayID(of screen: NSScreen) -> CGDirectDisplayID? {
        screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
    }

    public static func identity(for displayID: CGDirectDisplayID, ordinalFallback: Int) -> DisplayIdentity {
        DisplayIdentity(
            vendorNumber: CGDisplayVendorNumber(displayID),
            modelNumber: CGDisplayModelNumber(displayID),
            serialNumber: CGDisplaySerialNumber(displayID),
            isBuiltIn: CGDisplayIsBuiltin(displayID) != 0,
            ordinalFallback: ordinalFallback
        )
    }

    public static func current() -> [DisplayInfo] {
        var seenTriples: [String: Int] = [:]
        var displays: [DisplayInfo] = []

        for screen in NSScreen.screens {
            guard let displayID = displayID(of: screen) else { continue }

            let triple = "\(CGDisplayVendorNumber(displayID))-\(CGDisplayModelNumber(displayID))-\(CGDisplaySerialNumber(displayID))"
            let ordinal = seenTriples[triple] ?? 0
            seenTriples[triple] = ordinal + 1

            let mirrorSource = CGDisplayMirrorsDisplay(displayID)
            displays.append(
                DisplayInfo(
                    identity: identity(for: displayID, ordinalFallback: ordinal),
                    displayID: displayID,
                    frame: screen.frame,
                    visibleFrame: screen.visibleFrame,
                    backingScaleFactor: screen.backingScaleFactor,
                    isMirrorSecondary: mirrorSource != kCGNullDirectDisplay
                )
            )
        }

        return displays
    }

    public static func screen(for displayID: CGDirectDisplayID) -> NSScreen? {
        NSScreen.screens.first { self.displayID(of: $0) == displayID }
    }

    public static func maximumBackingScaleFactor() -> CGFloat {
        NSScreen.screens.map(\.backingScaleFactor).max() ?? 2
    }
}
