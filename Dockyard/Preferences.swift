import Combine
import DockCore
import Foundation
import SwiftUI

struct DisplayDescriptor: Identifiable, Hashable {
    let identity: DisplayIdentity
    let name: String
    let isBuiltIn: Bool
    let hostsSystemDock: Bool

    var id: String { identity.persistenceKey }
}

@MainActor
final class Preferences: ObservableObject {
    enum Key {
        static let disabledDisplays = "disabledDisplays"
        static let suppressOnSystemDockDisplay = "suppressOnSystemDockDisplay"
        static let reserveScreenSpace = "reserveScreenSpace"
    }

    @Published var suppressOnSystemDockDisplay: Bool {
        didSet {
            defaults.set(suppressOnSystemDockDisplay, forKey: Key.suppressOnSystemDockDisplay)
            onChange?()
        }
    }

    @Published var reservesScreenSpace: Bool {
        didSet {
            defaults.set(reservesScreenSpace, forKey: Key.reserveScreenSpace)
            onChange?()
        }
    }

    @Published private(set) var disabledDisplayKeys: Set<String> {
        didSet {
            defaults.set(Array(disabledDisplayKeys), forKey: Key.disabledDisplays)
            onChange?()
        }
    }

    @Published var knownDisplays: [DisplayDescriptor] = []
    @Published private(set) var appMenusAuthorized = AccessibilityAuthorization.isTrusted
    @Published var launchesAtLogin: Bool {
        didSet {
            guard launchesAtLogin != loginItemManager.isEnabled else { return }
            loginItemManager.setEnabled(launchesAtLogin)
        }
    }

    var onChange: (@MainActor () -> Void)?

    private let defaults: UserDefaults
    private let loginItemManager: LoginItemManager

    init(defaults: UserDefaults = .standard, loginItemManager: LoginItemManager = LoginItemManager()) {
        self.defaults = defaults
        self.loginItemManager = loginItemManager

        if defaults.object(forKey: Key.suppressOnSystemDockDisplay) == nil {
            defaults.set(true, forKey: Key.suppressOnSystemDockDisplay)
        }
        suppressOnSystemDockDisplay = defaults.bool(forKey: Key.suppressOnSystemDockDisplay)
        reservesScreenSpace = defaults.bool(forKey: Key.reserveScreenSpace)
        disabledDisplayKeys = Set(defaults.stringArray(forKey: Key.disabledDisplays) ?? [])
        launchesAtLogin = loginItemManager.isEnabled
    }

    func isEnabled(_ identity: DisplayIdentity) -> Bool {
        !disabledDisplayKeys.contains(identity.persistenceKey)
    }

    func setEnabled(_ enabled: Bool, for identity: DisplayIdentity) {
        var keys = disabledDisplayKeys
        if enabled {
            keys.remove(identity.persistenceKey)
        } else {
            keys.insert(identity.persistenceKey)
        }
        guard keys != disabledDisplayKeys else { return }
        disabledDisplayKeys = keys
    }

    func refreshAppMenuAuthorization() {
        let current = AccessibilityAuthorization.isTrusted
        guard appMenusAuthorized != current else { return }
        appMenusAuthorized = current
    }

    func requestAppMenuAuthorization() {
        AccessibilityAuthorization.requestTrust()
        refreshAppMenuAuthorization()
        guard !appMenusAuthorized else { return }
        AccessibilityAuthorization.openSettings()
    }

    func refreshLaunchAtLoginState() {
        let current = loginItemManager.isEnabled
        if launchesAtLogin != current {
            launchesAtLogin = current
        }
    }
}
