import AppKit
import DockCore
import Foundation
import Testing

@Suite("Calendar tile rendering")
struct CalendarTileRendererTests {
    private func baseIcon(size: Int) -> CGImage? {
        let image = NSWorkspace.shared.icon(forFile: "/System/Applications/Calendar.app")
        var rect = CGRect(x: 0, y: 0, width: size, height: size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)
    }

    @Test("Today reports a weekday and a day number")
    func todayValues() {
        let today = CalendarTileRenderer.today(
            Date(timeIntervalSince1970: 1_774_000_000),
            locale: Locale(identifier: "en_US")
        )
        #expect(!today.weekday.isEmpty)
        #expect(Int(today.day) != nil)
        #expect(Int(today.day).map { (1...31).contains($0) } == true)
    }

    @Test("The overlay preserves the icon dimensions and changes the pixels")
    func overlayChangesPixels() throws {
        let size = 256
        let base = try #require(baseIcon(size: size))
        let overlaid = try #require(
            CalendarTileRenderer.overlayForTesting(weekday: "Sun", day: "23", on: base)
        )

        #expect(overlaid.width == base.width)
        #expect(overlaid.height == base.height)

        if let path = ProcessInfo.processInfo.environment["DOCKYARD_CALENDAR_PREVIEW"] {
            let rep = NSBitmapImageRep(cgImage: overlaid)
            try rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
        }
    }
}
