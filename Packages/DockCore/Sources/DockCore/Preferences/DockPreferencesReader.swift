import Foundation

public struct DockPreferencesReader {
    public static let dockDomain = "com.apple.dock"

    private let values: DockPreferencesValues
    private let synchronize: () -> Void

    public init(values: DockPreferencesValues, synchronize: @escaping () -> Void = {}) {
        self.values = values
        self.synchronize = synchronize
    }

    public static func live() -> DockPreferencesReader {
        let source = CFPreferencesValues()
        return DockPreferencesReader(values: source, synchronize: source.synchronize)
    }

    public static func fixture(_ dictionary: [String: Any]) -> DockPreferencesReader {
        DockPreferencesReader(values: DictionaryPreferencesValues(dictionary))
    }

    public func read() -> RawDockPreferences {
        let state = DockLog.signposts.beginInterval("preference-read")
        defer { DockLog.signposts.endInterval("preference-read", state) }

        synchronize()

        return RawDockPreferences(
            persistentApps: DockPreferencesDecoder.decodeEntries(from: values.array("persistent-apps")),
            persistentOthers: DockPreferencesDecoder.decodeEntries(from: values.array("persistent-others")),
            recentApps: DockPreferencesDecoder.decodeEntries(from: values.array("recent-apps")),
            appearance: DockPreferencesDecoder.decodeAppearance(values)
        )
    }
}
