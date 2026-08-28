import AppKit
import CoreGraphics
import Foundation
import UniformTypeIdentifiers

public struct IconRequest: Sendable, Hashable {
    public let cacheKey: String
    public let url: URL?
    public let flavour: Flavour
    public let pixelSize: Int

    public enum Flavour: Sendable, Hashable {
        case application
        case folder
        case file
        case webLocation
        case trash(isEmpty: Bool)
        case calendar(weekday: String, day: String)
        case minimizedWindow
    }

    public init(cacheKey: String, url: URL?, flavour: Flavour, pixelSize: Int) {
        self.cacheKey = cacheKey
        self.url = url
        self.flavour = flavour
        self.pixelSize = pixelSize
    }

    public var storageKey: String {
        "\(cacheKey)|\(flavour)|\(pixelSize)"
    }
}

public actor IconProvider {
    private let cache = NSCache<NSString, CGImage>()
    private var storageKeysByCacheKey: [String: Set<String>] = [:]

    public init(memoryLimitBytes: Int = 32 * 1024 * 1024) {
        cache.totalCostLimit = memoryLimitBytes
    }

    public func image(for request: IconRequest) -> CGImage? {
        let key = request.storageKey as NSString
        if let cached = cache.object(forKey: key) {
            return cached
        }

        let state = DockLog.signposts.beginInterval("icon-rasterize")
        defer { DockLog.signposts.endInterval("icon-rasterize", state) }

        guard let rendered = Self.rasterize(request) else { return nil }
        cache.setObject(rendered, forKey: key, cost: rendered.bytesPerRow * rendered.height)
        storageKeysByCacheKey[request.cacheKey, default: []].insert(request.storageKey)
        return rendered
    }

    public func invalidate(cacheKey: String) {
        guard let keys = storageKeysByCacheKey.removeValue(forKey: cacheKey) else { return }
        for key in keys {
            cache.removeObject(forKey: key as NSString)
        }
        DockLog.icons.debug("Icon cache invalidated for \(cacheKey, privacy: .private)")
    }

    public func invalidateAll() {
        storageKeysByCacheKey.removeAll()
        cache.removeAllObjects()
    }

    private static func rasterize(_ request: IconRequest) -> CGImage? {
        guard let source = sourceImage(for: request) else { return nil }
        if case .minimizedWindow = request.flavour {
            let badgeSize = MinimizedWindowTileRenderer.badgePixelSize(for: request.pixelSize)
            return MinimizedWindowTileRenderer.card(
                badge: draw(source, pixelSize: badgeSize),
                pixelSize: request.pixelSize
            )
        }
        guard let base = draw(source, pixelSize: request.pixelSize) else { return nil }
        guard case .calendar(let weekday, let day) = request.flavour else { return base }
        return CalendarTileRenderer.overlay(weekday: weekday, day: day, on: base) ?? base
    }

    private static func sourceImage(for request: IconRequest) -> NSImage? {
        switch request.flavour {
        case .trash(let isEmpty):
            return trashImage(isEmpty: isEmpty) ?? genericIcon()
        case .webLocation:
            return NSWorkspace.shared.icon(for: .internetLocation)
        case .application, .folder, .file, .calendar, .minimizedWindow:
            guard let url = request.url, FileManager.default.fileExists(atPath: url.path) else {
                return genericIcon()
            }
            return NSWorkspace.shared.icon(forFile: url.path)
        }
    }

    private static let dockResources = URL(
        fileURLWithPath: "/System/Library/CoreServices/Dock.app/Contents/Resources",
        isDirectory: true
    )

    private static func trashImage(isEmpty: Bool) -> NSImage? {
        let candidates =
            isEmpty
            ? ["s-trashempty@2x.png", "trashempty@2x.png"]
            : ["s-trashfull@2x.png", "trashfull@2x.png"]
        for candidate in candidates {
            let url = dockResources.appendingPathComponent(candidate)
            if let image = NSImage(contentsOf: url) {
                return image
            }
        }
        return NSImage(named: isEmpty ? NSImage.trashEmptyName : NSImage.trashFullName)
    }

    private static func genericIcon() -> NSImage? {
        NSWorkspace.shared.icon(for: .item)
    }

    private static func draw(_ image: NSImage, pixelSize: Int) -> CGImage? {
        let size = max(pixelSize, 1)
        var proposed = CGRect(x: 0, y: 0, width: size, height: size)

        guard let representation = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else {
            return nil
        }

        guard
            let context = CGContext(
                data: nil,
                width: size,
                height: size,
                bitsPerComponent: 8,
                bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
            )
        else {
            return representation
        }

        context.interpolationQuality = .high
        let aspect = CGFloat(representation.width) / CGFloat(max(representation.height, 1))
        let target: CGRect
        if aspect >= 1 {
            let height = CGFloat(size) / aspect
            target = CGRect(x: 0, y: (CGFloat(size) - height) / 2, width: CGFloat(size), height: height)
        } else {
            let width = CGFloat(size) * aspect
            target = CGRect(x: (CGFloat(size) - width) / 2, y: 0, width: width, height: CGFloat(size))
        }

        context.draw(representation, in: target)
        return context.makeImage()
    }
}

extension IconRequest {
    public static let calendarBundleIdentifier = "com.apple.iCal"

    public init(tile: DockTile, pixelSize: Int) {
        let flavour: Flavour
        switch tile.kind {
        case .application:
            if tile.bundleIdentifier == Self.calendarBundleIdentifier {
                let today = CalendarTileRenderer.today()
                flavour = .calendar(weekday: today.weekday, day: today.day)
            } else {
                flavour = .application
            }
        case .folder:
            flavour = .folder
        case .url:
            flavour = .webLocation
        case .trash(let isEmpty):
            flavour = .trash(isEmpty: isEmpty)
        case .minimizedWindow:
            flavour = .minimizedWindow
        case .separator, .spacer:
            flavour = .application
        }
        self.init(
            cacheKey: tile.url?.path ?? tile.bundleIdentifier ?? tile.label,
            url: tile.url,
            flavour: flavour,
            pixelSize: pixelSize
        )
    }
}

extension IconRequest {
    public init(entry: FolderStackEntry, pixelSize: Int) {
        self.init(
            cacheKey: entry.url.path,
            url: entry.url,
            flavour: entry.isDirectory ? .folder : .file,
            pixelSize: pixelSize
        )
    }
}
