import CoreGraphics
import DockCore
import Foundation

public struct DockLaunchBounce: Sendable, Equatable {
    public enum Axis: Sendable, Equatable {
        case horizontal
        case vertical

        public var keyPath: String {
            switch self {
            case .horizontal:
                return "position.x"
            case .vertical:
                return "position.y"
            }
        }
    }

    public static let travelRatio: CGFloat = 0.40
    public static let riseDuration: Double = 0.35
    public static let fallDuration: Double = 0.35
    public static let restDuration: Double = 0.01

    public let axis: Axis
    public let displacement: CGFloat

    public init?(appearance: DockAppearance) {
        let travel = Self.travel(appearance)
        guard travel > 0 else { return nil }
        switch appearance.orientation {
        case .bottom:
            axis = .vertical
            displacement = travel
        case .left:
            axis = .horizontal
            displacement = travel
        case .right:
            axis = .horizontal
            displacement = -travel
        }
    }

    public static func travel(_ appearance: DockAppearance) -> CGFloat {
        guard appearance.launchAnimation else { return 0 }
        return max((appearance.tileSize * travelRatio).rounded(), 0)
    }

    public static var period: Double {
        riseDuration + fallDuration + restDuration
    }

    public var travel: CGFloat {
        abs(displacement)
    }

    public var values: [CGFloat] {
        [0, displacement, 0, 0]
    }

    public var keyTimes: [Double] {
        [
            0,
            Self.riseDuration / Self.period,
            (Self.riseDuration + Self.fallDuration) / Self.period,
            1,
        ]
    }
}
