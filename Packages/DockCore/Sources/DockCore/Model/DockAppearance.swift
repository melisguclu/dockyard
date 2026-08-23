import CoreGraphics
import Foundation

public enum DockOrientation: String, Sendable, Equatable, Codable, CaseIterable {
    case bottom
    case left
    case right

    public var isVertical: Bool { self != .bottom }
}

public struct DockAppearance: Sendable, Equatable {
    public let tileSize: CGFloat
    public let largeSize: CGFloat
    public let magnificationEnabled: Bool
    public let orientation: DockOrientation
    public let autoHide: Bool
    public let autoHideDelay: TimeInterval
    public let autoHideTimeModifier: Double
    public let showProcessIndicators: Bool
    public let showRecents: Bool
    public let minimizeToApplication: Bool

    public init(
        tileSize: CGFloat = DockAppearance.defaultTileSize,
        largeSize: CGFloat = DockAppearance.defaultLargeSize,
        magnificationEnabled: Bool = false,
        orientation: DockOrientation = .bottom,
        autoHide: Bool = false,
        autoHideDelay: TimeInterval = 0.5,
        autoHideTimeModifier: Double = 1.0,
        showProcessIndicators: Bool = true,
        showRecents: Bool = true,
        minimizeToApplication: Bool = false
    ) {
        self.tileSize = tileSize
        self.largeSize = largeSize
        self.magnificationEnabled = magnificationEnabled
        self.orientation = orientation
        self.autoHide = autoHide
        self.autoHideDelay = autoHideDelay
        self.autoHideTimeModifier = autoHideTimeModifier
        self.showProcessIndicators = showProcessIndicators
        self.showRecents = showRecents
        self.minimizeToApplication = minimizeToApplication
    }

    public static let defaultTileSize: CGFloat = 48
    public static let defaultLargeSize: CGFloat = 128

    public static let tileSizeRange: ClosedRange<CGFloat> = 16...128
    public static let largeSizeRange: ClosedRange<CGFloat> = 16...256
    public static let autoHideDelayRange: ClosedRange<TimeInterval> = 0...5
    public static let autoHideTimeModifierRange: ClosedRange<Double> = 0.05...5

    public static let `default` = DockAppearance()

    public var effectiveLargeSize: CGFloat {
        magnificationEnabled ? max(largeSize, tileSize) : tileSize
    }
}
