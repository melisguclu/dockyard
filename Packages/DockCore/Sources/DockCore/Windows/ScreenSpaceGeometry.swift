import CoreGraphics
import Foundation

public struct ReservedArea: Sendable, Equatable {
    public let display: CGRect
    public let thickness: CGFloat
    public let edge: DockOrientation

    public init(display: CGRect, thickness: CGFloat, edge: DockOrientation) {
        self.display = display
        self.thickness = thickness
        self.edge = edge
    }

    public var usable: CGRect {
        switch edge {
        case .bottom:
            return CGRect(
                x: display.minX,
                y: display.minY,
                width: display.width,
                height: max(display.height - thickness, 0)
            )
        case .left:
            return CGRect(
                x: display.minX + thickness,
                y: display.minY,
                width: max(display.width - thickness, 0),
                height: display.height
            )
        case .right:
            return CGRect(
                x: display.minX,
                y: display.minY,
                width: max(display.width - thickness, 0),
                height: display.height
            )
        }
    }
}

public enum ScreenSpaceGeometry {
    public static let minimumWindowWidth: CGFloat = 160
    public static let minimumWindowHeight: CGFloat = 120
    public static let tolerance: CGFloat = 1

    public static func area(for window: CGRect, in areas: [ReservedArea]) -> ReservedArea? {
        let centre = CGPoint(x: window.midX, y: window.midY)
        if let containing = areas.first(where: { $0.display.contains(centre) }) {
            return containing
        }
        return areas.max { first, second in
            first.display.intersection(window).area < second.display.intersection(window).area
        }
        .flatMap { $0.display.intersects(window) ? $0 : nil }
    }

    public static func adjusted(window: CGRect, avoiding areas: [ReservedArea]) -> CGRect? {
        guard let area = area(for: window, in: areas) else { return nil }
        return adjusted(window: window, avoiding: area)
    }

    public static func adjusted(window: CGRect, avoiding area: ReservedArea) -> CGRect? {
        guard window.width > 0, window.height > 0 else { return nil }
        let usable = area.usable
        var adjusted = window

        switch area.edge {
        case .bottom:
            guard window.maxY > usable.maxY + tolerance else { return nil }
            adjusted.size.height = usable.maxY - window.minY
        case .left:
            guard window.minX < usable.minX - tolerance else { return nil }
            adjusted.origin.x = usable.minX
            adjusted.size.width = window.maxX - usable.minX
        case .right:
            guard window.maxX > usable.maxX + tolerance else { return nil }
            adjusted.size.width = usable.maxX - window.minX
        }

        guard adjusted.width >= minimumWindowWidth, adjusted.height >= minimumWindowHeight else { return nil }
        guard adjusted != window else { return nil }
        return adjusted
    }
}

extension CGRect {
    fileprivate var area: CGFloat {
        isNull || isEmpty ? 0 : width * height
    }
}
