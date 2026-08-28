import Foundation

enum DockCoreText {
    static func string(_ key: String) -> String {
        NSLocalizedString(key, bundle: .module, comment: "")
    }
}
