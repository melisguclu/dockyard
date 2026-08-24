import Foundation

public protocol AppMenuInspecting: Sendable {
    func snapshot(processIdentifier: pid_t) async -> AppMenuSnapshot
    func windows(processIdentifier: pid_t) async -> [AppWindowEntry]
    func perform(_ command: AppMenuCommand, processIdentifier: pid_t) async -> Bool
    func raise(_ window: AppWindowEntry, processIdentifier: pid_t) async -> Bool
}

extension AppMenuInspector: AppMenuInspecting {}
