import Foundation

enum DockCoreText {
    static func string(_ key: String) -> String {
        SystemDockStrings.string(for: key, fallback: NSLocalizedString(key, bundle: .module, comment: ""))
    }
}
