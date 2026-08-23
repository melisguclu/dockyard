import AppKit
import CoreGraphics
import CoreText
import Foundation

public enum CalendarTileRenderer {
    public struct Today: Sendable, Equatable {
        public let weekday: String
        public let day: String
    }

    public static func today(_ date: Date = Date(), locale: Locale = .current) -> Today {
        var calendar = Calendar.current
        calendar.locale = locale

        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.setLocalizedDateFormatFromTemplate("EEE")

        return Today(
            weekday: formatter.string(from: date),
            day: String(calendar.component(.day, from: date))
        )
    }

    public static func overlayForTesting(weekday: String, day: String, on base: CGImage) -> CGImage? {
        overlay(weekday: weekday, day: day, on: base)
    }

    static func overlay(weekday: String, day: String, on base: CGImage) -> CGImage? {
        let width = base.width
        let height = base.height
        guard width > 16, height > 16 else { return nil }

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        let canvas = CGRect(x: 0, y: 0, width: width, height: height)
        context.draw(base, in: canvas)

        let side = CGFloat(min(width, height))
        let card = CGRect(
            x: canvas.midX - side * Metrics.cardSide / 2,
            y: canvas.midY - side * Metrics.cardSide / 2,
            width: side * Metrics.cardSide,
            height: side * Metrics.cardSide
        )

        let bandTop = card.maxY - card.height * Metrics.bandTopInset
        let bandBottom = card.maxY - card.height * (Metrics.bandTopInset + Metrics.bandHeight)
        let band = CGRect(x: card.minX, y: bandBottom, width: card.width, height: bandTop - bandBottom)
        let body = CGRect(x: card.minX, y: card.minY, width: card.width, height: bandBottom - card.minY)

        context.saveGState()
        context.addPath(
            CGPath(
                roundedRect: card,
                cornerWidth: card.width * Metrics.cornerRadius,
                cornerHeight: card.width * Metrics.cornerRadius,
                transform: nil
            )
        )
        context.clip()
        context.setFillColor(Metrics.bodyColor)
        context.fill(body)
        context.restoreGState()

        draw(
            day,
            in: body.insetBy(dx: 0, dy: body.height * Metrics.dayVerticalInset),
            font: NSFont.systemFont(ofSize: body.height * Metrics.dayFontScale, weight: .light),
            color: Metrics.dayColor,
            context: context
        )
        draw(
            weekday,
            in: band,
            font: NSFont.systemFont(ofSize: band.height * Metrics.weekdayFontScale, weight: .semibold),
            color: Metrics.weekdayColor,
            context: context
        )

        return context.makeImage()
    }

    private static func draw(
        _ text: String,
        in rect: CGRect,
        font: NSFont,
        color: CGColor,
        context: CGContext
    ) {
        guard !text.isEmpty, rect.width > 0, rect.height > 0 else { return }

        let attributes: [NSAttributedString.Key: Any] = [
            .font: font,
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): color
        ]
        let line = CTLineCreateWithAttributedString(
            NSAttributedString(string: text, attributes: attributes)
        )
        let bounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
        guard bounds.width > 0 else { return }

        context.saveGState()
        context.setAllowsAntialiasing(true)
        context.textPosition = CGPoint(
            x: rect.midX - bounds.width / 2 - bounds.minX,
            y: rect.midY - bounds.height / 2 - bounds.minY
        )
        CTLineDraw(line, context)
        context.restoreGState()
    }

    private enum Metrics {
        static let cardSide: CGFloat = 0.8047
        static let cornerRadius: CGFloat = 0.2237
        static let bandTopInset: CGFloat = 0.0146
        static let bandHeight: CGFloat = 0.2330
        static let dayFontScale: CGFloat = 0.86
        static let dayVerticalInset: CGFloat = 0.06
        static let weekdayFontScale: CGFloat = 0.58
        static let bodyColor = CGColor(red: 0.925, green: 0.922, blue: 0.925, alpha: 1)
        static let dayColor = CGColor(red: 0.09, green: 0.09, blue: 0.10, alpha: 1)
        static let weekdayColor = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
    }
}
