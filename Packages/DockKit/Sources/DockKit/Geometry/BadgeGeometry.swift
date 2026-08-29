import CoreGraphics
import Foundation

public enum BadgeGeometry {
    public static let diameterRatio: CGFloat = 0.387
    public static let minimumDiameter: CGFloat = 11
    public static let centreInsetXRatio: CGFloat = 0.216
    public static let centreInsetYRatio: CGFloat = 0.184
    public static let maximumCharacters = 6

    public static func diameter(iconLength: CGFloat) -> CGFloat {
        max(iconLength * diameterRatio, minimumDiameter)
    }

    public static func frame(in bounds: CGRect, aspect: CGFloat = 1) -> CGRect {
        let length = min(bounds.width, bounds.height)
        let height = diameter(iconLength: length)
        let width = height * max(aspect, 1)
        let centre = CGPoint(
            x: bounds.maxX - length * centreInsetXRatio,
            y: bounds.maxY - length * centreInsetYRatio
        )
        return CGRect(
            x: centre.x - width / 2,
            y: centre.y - height / 2,
            width: width,
            height: height
        )
    }
}
