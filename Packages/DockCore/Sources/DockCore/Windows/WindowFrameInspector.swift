import ApplicationServices
import CoreGraphics
import Foundation

public struct ManagedWindow: Sendable, Equatable {
    public let index: Int
    public let frame: CGRect

    public init(index: Int, frame: CGRect) {
        self.index = index
        self.frame = frame
    }
}

public protocol WindowFrameInspecting: Sendable {
    func windows(processIdentifier: pid_t) async -> [ManagedWindow]
    func resize(_ window: ManagedWindow, to frame: CGRect, processIdentifier: pid_t) async -> Bool
}

public actor WindowFrameInspector: WindowFrameInspecting {
    public static let messagingTimeout: Float = 0.5
    public static let windowLimit = 24
    private static let fullScreenAttribute = "AXFullScreen"

    public init() {}

    public func windows(processIdentifier: pid_t) -> [ManagedWindow] {
        guard AccessibilityAuthorization.isTrusted else { return [] }
        let application = AXElement.application(processIdentifier, messagingTimeout: Self.messagingTimeout)
        return application.children(kAXWindowsAttribute)
            .prefix(Self.windowLimit)
            .enumerated()
            .compactMap { entry in
                guard let frame = Self.frame(of: entry.element) else { return nil }
                return ManagedWindow(index: entry.offset, frame: frame)
            }
    }

    public func resize(_ window: ManagedWindow, to frame: CGRect, processIdentifier: pid_t) -> Bool {
        guard AccessibilityAuthorization.isTrusted else { return false }
        let application = AXElement.application(processIdentifier, messagingTimeout: Self.messagingTimeout)
        let windows = application.children(kAXWindowsAttribute)
        guard window.index < windows.count else { return false }
        let element = windows[window.index]
        guard Self.frame(of: element) == window.frame else { return false }

        var changed = false
        if frame.origin != window.frame.origin {
            changed = element.set(kAXPositionAttribute, point: frame.origin)
        }
        if frame.size != window.frame.size {
            changed = element.set(kAXSizeAttribute, size: frame.size) || changed
        }
        return changed
    }

    private static func frame(of element: AXElement) -> CGRect? {
        guard element.string(kAXRoleAttribute) == kAXWindowRole else { return nil }
        guard element.string(kAXSubroleAttribute) == kAXStandardWindowSubrole else { return nil }
        guard element.flag(kAXMinimizedAttribute) != true else { return nil }
        guard element.flag(fullScreenAttribute) != true else { return nil }
        guard let origin = element.point(kAXPositionAttribute),
            let size = element.size(kAXSizeAttribute),
            size.width > 0,
            size.height > 0
        else { return nil }
        return CGRect(origin: origin, size: size)
    }
}
