import Foundation
import SwiftUI

enum DockyardText {
    static func string(_ key: String) -> String {
        NSLocalizedString(key, bundle: .module, comment: "")
    }

    static func text(_ key: LocalizedStringKey) -> Text {
        Text(key, bundle: .module)
    }
}
