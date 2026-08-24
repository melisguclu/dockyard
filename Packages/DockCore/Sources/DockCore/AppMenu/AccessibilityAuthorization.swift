import AppKit
import ApplicationServices
import Foundation

public enum AccessibilityAuthorization {
    public static var isTrusted: Bool {
        AXIsProcessTrusted()
    }

    public static func requestTrust() {
        let options = ["AXTrustedCheckOptionPrompt" as CFString: kCFBooleanTrue] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
    }

    @MainActor
    public static func openSettings() {
        let target = "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        guard let url = URL(string: target) else { return }
        NSWorkspace.shared.open(url)
    }
}
