import CoreGraphics
import Foundation

extension Comparable {
    public func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}

extension String {
    public func clampedLength(to limit: Int) -> String {
        count <= limit ? self : String(prefix(limit))
    }
}
