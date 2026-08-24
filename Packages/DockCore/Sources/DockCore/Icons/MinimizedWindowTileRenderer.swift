import AppKit
import CoreGraphics
import Foundation

public enum MinimizedWindowTileRenderer {
    public static func card(badge: CGImage?, pixelSize: Int) -> CGImage? {
        let side = max(pixelSize, 1)
        guard side > 16 else { return nil }

        guard
            let context = CGContext(
                data: nil,
                width: side,
                height: side,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue
            )
        else { return nil }

        context.interpolationQuality = .high
        let canvas = CGRect(x: 0, y: 0, width: side, height: side)
        draw(cardIn: canvas, context: context)

        if let badge {
            context.draw(badge, in: badgeRect(in: canvas))
        }

        return context.makeImage()
    }

    public static func badgePixelSize(for pixelSize: Int) -> Int {
        max(Int((CGFloat(pixelSize) * Metrics.badgeSide).rounded()), 1)
    }

    static func cardRect(in canvas: CGRect) -> CGRect {
        let side = min(canvas.width, canvas.height)
        let width = side * Metrics.cardWidth
        let height = width * Metrics.cardAspect
        return CGRect(
            x: canvas.midX - width / 2,
            y: canvas.midY - height / 2 + side * Metrics.cardRise,
            width: width,
            height: height
        )
    }

    static func badgeRect(in canvas: CGRect) -> CGRect {
        let side = min(canvas.width, canvas.height) * Metrics.badgeSide
        return CGRect(x: canvas.maxX - side, y: canvas.minY, width: side, height: side)
    }

    private static func draw(cardIn canvas: CGRect, context: CGContext) {
        let card = cardRect(in: canvas)
        let radius = card.height * Metrics.cornerRadius
        let outline = CGPath(
            roundedRect: card,
            cornerWidth: radius,
            cornerHeight: radius,
            transform: nil
        )

        context.saveGState()
        context.addPath(outline)
        context.clip()
        context.setFillColor(Metrics.bodyColor)
        context.fill(card)

        let bar = CGRect(
            x: card.minX,
            y: card.maxY - card.height * Metrics.titleBarHeight,
            width: card.width,
            height: card.height * Metrics.titleBarHeight
        )
        context.setFillColor(Metrics.titleBarColor)
        context.fill(bar)
        context.setFillColor(Metrics.separatorColor)
        context.fill(CGRect(x: bar.minX, y: bar.minY, width: bar.width, height: max(bar.height * 0.06, 1)))
        draw(lightsIn: bar, context: context)
        context.restoreGState()

        context.saveGState()
        context.addPath(outline)
        context.setStrokeColor(Metrics.borderColor)
        context.setLineWidth(max(card.height * Metrics.borderWidth, 1))
        context.strokePath()
        context.restoreGState()
    }

    private static func draw(lightsIn bar: CGRect, context: CGContext) {
        let radius = bar.height * Metrics.lightRadius
        guard radius > 0.4 else { return }
        var center = CGPoint(x: bar.minX + bar.height * Metrics.lightLeading, y: bar.midY)
        for color in Metrics.lightColors {
            context.setFillColor(color)
            context.fillEllipse(
                in: CGRect(
                    x: center.x - radius,
                    y: center.y - radius,
                    width: radius * 2,
                    height: radius * 2
                )
            )
            center.x += radius * Metrics.lightSpacing
        }
    }

    private enum Metrics {
        static let cardWidth: CGFloat = 0.94
        static let cardAspect: CGFloat = 0.66
        static let cardRise: CGFloat = 0.07
        static let cornerRadius: CGFloat = 0.13
        static let titleBarHeight: CGFloat = 0.24
        static let borderWidth: CGFloat = 0.014
        static let badgeSide: CGFloat = 0.44
        static let lightRadius: CGFloat = 0.17
        static let lightLeading: CGFloat = 0.42
        static let lightSpacing: CGFloat = 2.9

        static let bodyColor = CGColor(red: 0.965, green: 0.965, blue: 0.973, alpha: 1)
        static let titleBarColor = CGColor(red: 0.878, green: 0.878, blue: 0.894, alpha: 1)
        static let separatorColor = CGColor(red: 0.769, green: 0.769, blue: 0.792, alpha: 1)
        static let borderColor = CGColor(red: 0, green: 0, blue: 0, alpha: 0.22)
        static let lightColors = [
            CGColor(red: 1.0, green: 0.373, blue: 0.341, alpha: 1),
            CGColor(red: 0.996, green: 0.737, blue: 0.180, alpha: 1),
            CGColor(red: 0.157, green: 0.784, blue: 0.251, alpha: 1),
        ]
    }
}
