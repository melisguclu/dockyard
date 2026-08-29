import Foundation

public protocol DockItemInspecting: Sendable {
    func read(processIdentifier: pid_t) async -> DockItemList
}

extension DockItemInspector: DockItemInspecting {}
