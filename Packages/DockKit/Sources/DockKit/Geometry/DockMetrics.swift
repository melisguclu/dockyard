import CoreGraphics
import Foundation

public struct DockMetrics: Sendable, Equatable {
    public let interTileSpacingRatio: CGFloat
    public let barPaddingRatio: CGFloat
    public let screenEdgeMarginRatio: CGFloat
    public let cornerRadiusRatio: CGFloat
    public let indicatorDiameterRatio: CGFloat
    public let separatorLengthRatio: CGFloat
    public let smallSpacerLengthRatio: CGFloat
    public let magnificationWindowTiles: CGFloat
    public let borderWidth: CGFloat

    public init(
        interTileSpacingRatio: CGFloat,
        barPaddingRatio: CGFloat,
        screenEdgeMarginRatio: CGFloat,
        cornerRadiusRatio: CGFloat,
        indicatorDiameterRatio: CGFloat,
        separatorLengthRatio: CGFloat,
        smallSpacerLengthRatio: CGFloat,
        magnificationWindowTiles: CGFloat,
        borderWidth: CGFloat
    ) {
        self.interTileSpacingRatio = interTileSpacingRatio
        self.barPaddingRatio = barPaddingRatio
        self.screenEdgeMarginRatio = screenEdgeMarginRatio
        self.cornerRadiusRatio = cornerRadiusRatio
        self.indicatorDiameterRatio = indicatorDiameterRatio
        self.separatorLengthRatio = separatorLengthRatio
        self.smallSpacerLengthRatio = smallSpacerLengthRatio
        self.magnificationWindowTiles = magnificationWindowTiles
        self.borderWidth = borderWidth
    }

    public static let sonoma = DockMetrics(
        interTileSpacingRatio: 0.0833,
        barPaddingRatio: 0.1042,
        screenEdgeMarginRatio: 0.0833,
        cornerRadiusRatio: 0.2800,
        indicatorDiameterRatio: 0.0833,
        separatorLengthRatio: 0.2500,
        smallSpacerLengthRatio: 0.5000,
        magnificationWindowTiles: 3.0,
        borderWidth: 1.0
    )

    public static let tahoe = DockMetrics(
        interTileSpacingRatio: 0.1100,
        barPaddingRatio: 0.2222,
        screenEdgeMarginRatio: 0.2963,
        cornerRadiusRatio: 0.5000,
        indicatorDiameterRatio: 0.0833,
        separatorLengthRatio: 0.2500,
        smallSpacerLengthRatio: 0.5000,
        magnificationWindowTiles: 3.0,
        borderWidth: 1.0
    )

    public static var current: DockMetrics {
        if ProcessInfo.processInfo.isOperatingSystemAtLeast(
            OperatingSystemVersion(majorVersion: 26, minorVersion: 0, patchVersion: 0)
        ) {
            return .tahoe
        }
        return .sonoma
    }
}
