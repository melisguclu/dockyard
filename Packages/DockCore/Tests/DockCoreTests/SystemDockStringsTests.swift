import DockCore
import Foundation
import Testing

@Suite("The Dock's own words are read from the Dock rather than translated again")
struct SystemDockStringsTests {
    private let sentinel = "«Dockyard's own»"

    @Test("Every mapped key still resolves against the installed Dock")
    func mappedKeysResolve() {
        for (key, entry) in SystemDockStrings.mapping {
            let resolved = SystemDockStrings.string(for: key, fallback: sentinel)
            #expect(resolved != sentinel, "\(entry.table.rawValue)/\(entry.name) is gone, mapped from \(key)")
            #expect(!resolved.isEmpty)
        }
    }

    @Test("A key the Dock does not answer for keeps Dockyard's own word")
    func unmappedKeyFallsBack() {
        #expect(SystemDockStrings.string(for: "stack.unreadable", fallback: sentinel) == sentinel)
        #expect(SystemDockStrings.string(for: "accessibility.badge", fallback: sentinel) == sentinel)
    }

    @Test("The Dock ships the wording in more languages than Dockyard does")
    func dockCarriesManyLocalizations() throws {
        let bundle = try #require(Bundle(path: SystemDockStrings.bundlePath))
        #expect(bundle.localizations.count > 20)
    }
}
