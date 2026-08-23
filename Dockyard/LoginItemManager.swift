import DockCore
import Foundation
import ServiceManagement

@MainActor
final class LoginItemManager {
    var isEnabled: Bool {
        SMAppService.mainApp.status == .enabled
    }

    func setEnabled(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            DockLog.app.error("Login item update failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
