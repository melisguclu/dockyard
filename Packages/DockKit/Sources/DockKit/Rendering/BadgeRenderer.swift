import AppKit
import CoreGraphics
import CoreText
import DockCore
import Foundation

@MainActor
public final class BadgeRenderer {
    public static let shared = BadgeRenderer()
    public static let cacheLimit = 64
    public static let capHeightRatio: CGFloat = 0.38
    public static let sidePaddingRatio: CGFloat = 0.145
    public static let referenceFontSize: CGFloat = 100

    private var cache: [String: CGImage] = [:]

    public init() {}

    public func badge(text: String, pixelDiameter: Int) -> CGImage? {
        let trimmed = text.clampedLength(to: BadgeGeometry.maximumCharacters)
        guard !trimmed.isEmpty, pixelDiameter > 0 else { return nil }

        let key = "\(trimmed)|\(pixelDiameter)"
        if let cached = cache[key] { return cached }

        let height = CGFloat(pixelDiameter)
        let line = self.line(trimmed, height: height)
        let glyphs = CTLineGetBoundsWithOptions(line, .useGlyphPathBounds)
        let width = max(height, glyphs.width + 2 * height * Self.sidePaddingRatio).rounded()

        guard
            let context = CGContext(
                data: nil,
                width: Int(width),
                height: Int(height.rounded()),
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue
            )
        else { return nil }

        draw(line, glyphs: glyphs, in: context, width: width, height: height)

        guard let image = context.makeImage() else { return nil }
        if cache.count >= Self.cacheLimit {
            cache.removeAll()
        }
        cache[key] = image
        return image
    }

    public func invalidate() {
        cache.removeAll()
    }

    private func line(_ text: String, height: CGFloat) -> CTLine {
        let reference = NSAttributedString(
            string: text,
            attributes: [.font: NSFont.systemFont(ofSize: Self.referenceFontSize, weight: Self.fontWeight)]
        )
        let measured = CTLineGetBoundsWithOptions(
            CTLineCreateWithAttributedString(reference),
            .useGlyphPathBounds
        )
        let target = height * Self.capHeightRatio
        let size = measured.height > 0 ? Self.referenceFontSize * target / measured.height : target
        let string = NSAttributedString(
            string: text,
            attributes: [
                .font: NSFont.systemFont(ofSize: size, weight: Self.fontWeight),
                .foregroundColor: NSColor.white,
            ]
        )
        return CTLineCreateWithAttributedString(string)
    }

    private func draw(
        _ line: CTLine,
        glyphs: CGRect,
        in context: CGContext,
        width: CGFloat,
        height: CGFloat
    ) {
        let capsule = CGRect(x: 0, y: 0, width: width, height: height)
        context.setFillColor(Self.fillColor.cgColor)
        context.addPath(
            CGPath(
                roundedRect: capsule,
                cornerWidth: height / 2,
                cornerHeight: height / 2,
                transform: nil
            )
        )
        context.fillPath()

        context.textPosition = CGPoint(
            x: (width - glyphs.width) / 2 - glyphs.minX,
            y: (height - glyphs.height) / 2 - glyphs.minY
        )
        CTLineDraw(line, context)
    }

    private static let fontWeight = NSFont.Weight.regular
    private static let fillColor = NSColor(srgbRed: 0.961, green: 0.263, blue: 0.216, alpha: 1)
}
