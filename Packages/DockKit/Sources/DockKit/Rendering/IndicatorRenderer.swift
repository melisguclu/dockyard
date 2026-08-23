import AppKit
import CoreGraphics
import Foundation

@MainActor
public final class IndicatorRenderer {
    public static let shared = IndicatorRenderer()

    private var cache: [String: CGImage] = [:]

    public init() {}

    public func indicator(diameter: CGFloat, scale: CGFloat, isDark: Bool) -> CGImage? {
        let pixels = Int((diameter * scale).rounded())
        let key = "\(pixels)|\(isDark)"
        if let cached = cache[key] { return cached }

        guard pixels > 0,
            let context = CGContext(
                data: nil,
                width: pixels,
                height: pixels,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue
            )
        else { return nil }

        let color =
            isDark
            ? NSColor.white.withAlphaComponent(0.85)
            : NSColor.black.withAlphaComponent(0.65)
        context.setFillColor(color.cgColor)
        context.fillEllipse(in: CGRect(x: 0, y: 0, width: pixels, height: pixels))

        let image = context.makeImage()
        if let image {
            cache[key] = image
        }
        return image
    }

    public func invalidate() {
        cache.removeAll()
    }
}
