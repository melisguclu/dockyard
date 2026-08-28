import DockCore
import Foundation
import Testing

@Suite("Spring loading follows the system's own springing settings")
struct SpringLoadingSettingsTests {
    private func defaults(_ values: [String: Any]) -> UserDefaults {
        let suite =
            UserDefaults(suiteName: "com.dockyard.tests.springing.\(UUID().uuidString)")
            ?? .standard
        for (key, value) in values {
            suite.set(value, forKey: key)
        }
        return suite
    }

    @Test("An empty domain answers with the system's documented defaults")
    func documentedDefaults() {
        let settings = SpringLoadingSettings.resolve(defaults([:]))

        #expect(settings.isEnabled)
        #expect(settings.delay == 0.5)
    }

    @Test("Springing turned off in the Finder turns it off in the bar")
    func disabled() {
        let settings = SpringLoadingSettings.resolve(
            defaults([SpringLoadingSettings.enabledKey: false])
        )

        #expect(!settings.isEnabled)
    }

    @Test("The delay is taken from the system slider")
    func delay() {
        let settings = SpringLoadingSettings.resolve(
            defaults([SpringLoadingSettings.delayKey: 0.87])
        )

        #expect(settings.delay == 0.87)
    }

    @Test("An absurd delay is clamped rather than trusted")
    func clamping() {
        #expect(SpringLoadingSettings.resolve(defaults([SpringLoadingSettings.delayKey: -4])).delay == 0)
        #expect(SpringLoadingSettings.resolve(defaults([SpringLoadingSettings.delayKey: 900])).delay == 5)
    }
}
