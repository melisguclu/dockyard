import CoreGraphics
import DockCore
import Foundation

public enum DockRevealState: Sendable, Equatable {
    case disabled
    case hidden
    case revealing
    case revealed
    case hiding

    public var isSliding: Bool { self == .revealing || self == .hiding }
    public var showsTrigger: Bool { self == .hidden }
    public var acceptsPointer: Bool { self == .disabled || self == .revealed }
}

public enum DockAutoHide {
    public static let triggerThickness: CGFloat = 1
    public static let baseSlideDuration: TimeInterval = 0.32
    public static let minimumSlideDuration: TimeInterval = 0.01

    public static func revealDelay(_ appearance: DockAppearance) -> TimeInterval {
        max(appearance.autoHideDelay, 0)
    }

    public static func slideDuration(_ appearance: DockAppearance) -> TimeInterval {
        max(baseSlideDuration * appearance.autoHideTimeModifier, minimumSlideDuration)
    }

    public static func hiddenFrame(
        revealed: CGRect,
        screenFrame: CGRect,
        orientation: DockOrientation
    ) -> CGRect {
        switch orientation {
        case .bottom:
            return revealed.offsetBy(dx: 0, dy: screenFrame.minY - revealed.maxY)
        case .left:
            return revealed.offsetBy(dx: screenFrame.minX - revealed.maxX, dy: 0)
        case .right:
            return revealed.offsetBy(dx: screenFrame.maxX - revealed.minX, dy: 0)
        }
    }

    public static func triggerFrame(
        screenFrame: CGRect,
        orientation: DockOrientation
    ) -> CGRect {
        switch orientation {
        case .bottom:
            return CGRect(
                x: screenFrame.minX,
                y: screenFrame.minY,
                width: screenFrame.width,
                height: min(triggerThickness, screenFrame.height)
            )
        case .left:
            return CGRect(
                x: screenFrame.minX,
                y: screenFrame.minY,
                width: min(triggerThickness, screenFrame.width),
                height: screenFrame.height
            )
        case .right:
            let thickness = min(triggerThickness, screenFrame.width)
            return CGRect(
                x: screenFrame.maxX - thickness,
                y: screenFrame.minY,
                width: thickness,
                height: screenFrame.height
            )
        }
    }
}
