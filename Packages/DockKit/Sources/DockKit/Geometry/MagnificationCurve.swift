import CoreGraphics
import Foundation

public enum MagnificationCurve {
    public static func scale(distanceInTiles distance: CGFloat, window: CGFloat, maximumScale: CGFloat) -> CGFloat {
        guard window > 0, maximumScale > 1 else { return 1 }
        let clamped = min(abs(distance), window)
        let falloff = 0.5 * (1 + cos(.pi * clamped / window))
        return 1 + (maximumScale - 1) * falloff
    }

    public static func maximumScale(tileSize: CGFloat, largeSize: CGFloat) -> CGFloat {
        guard tileSize > 0 else { return 1 }
        return max(largeSize / tileSize, 1)
    }
}
