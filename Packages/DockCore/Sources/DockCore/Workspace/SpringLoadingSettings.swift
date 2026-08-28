import Foundation

public struct SpringLoadingSettings: Sendable, Equatable {
    public static let enabledKey = "com.apple.springing.enabled"
    public static let delayKey = "com.apple.springing.delay"
    public static let delayRange: ClosedRange<TimeInterval> = 0...5

    public let isEnabled: Bool
    public let delay: TimeInterval

    public init(isEnabled: Bool, delay: TimeInterval) {
        self.isEnabled = isEnabled
        self.delay = delay.clamped(to: Self.delayRange)
    }

    public static let `default` = SpringLoadingSettings(isEnabled: true, delay: 0.5)

    public static var current: SpringLoadingSettings {
        resolve(UserDefaults.standard)
    }

    public static func resolve(_ defaults: UserDefaults) -> SpringLoadingSettings {
        let enabled = defaults.object(forKey: enabledKey) as? NSNumber
        let delay = defaults.object(forKey: delayKey) as? NSNumber
        return SpringLoadingSettings(
            isEnabled: enabled?.boolValue ?? `default`.isEnabled,
            delay: delay?.doubleValue ?? `default`.delay
        )
    }
}
