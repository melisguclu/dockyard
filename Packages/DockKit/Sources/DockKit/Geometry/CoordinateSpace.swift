import CoreGraphics

public enum CoordinateSpace {
    public static func cgToCocoa(_ point: CGPoint, primaryHeight: CGFloat) -> CGPoint {
        CGPoint(x: point.x, y: primaryHeight - point.y)
    }

    public static func cgToCocoa(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        CGRect(
            x: rect.origin.x,
            y: primaryHeight - rect.origin.y - rect.height,
            width: rect.width,
            height: rect.height
        )
    }

    public static func cocoaToCG(_ rect: CGRect, primaryHeight: CGFloat) -> CGRect {
        cgToCocoa(rect, primaryHeight: primaryHeight)
    }

    public static func cocoaToCG(_ point: CGPoint, primaryHeight: CGFloat) -> CGPoint {
        cgToCocoa(point, primaryHeight: primaryHeight)
    }
}
