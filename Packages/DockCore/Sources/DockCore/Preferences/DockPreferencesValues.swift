import Foundation

public protocol DockPreferencesValues {
    func rawValue(forKey key: String) -> Any?
}

extension DockPreferencesValues {
    public func double(_ key: String, default fallback: Double) -> Double {
        if let number = rawValue(forKey: key) as? NSNumber { return number.doubleValue }
        if let string = rawValue(forKey: key) as? String, let parsed = Double(string) { return parsed }
        return fallback
    }

    public func bool(_ key: String, default fallback: Bool) -> Bool {
        if let number = rawValue(forKey: key) as? NSNumber { return number.boolValue }
        if let string = rawValue(forKey: key) as? String {
            return ["1", "true", "yes", "YES"].contains(string)
        }
        return fallback
    }

    public func string(_ key: String, default fallback: String) -> String {
        guard let string = rawValue(forKey: key) as? String, !string.isEmpty else { return fallback }
        return string
    }

    public func array(_ key: String) -> [Any] {
        rawValue(forKey: key) as? [Any] ?? []
    }
}

public struct DictionaryPreferencesValues: DockPreferencesValues {
    private let storage: [String: Any]

    public init(_ storage: [String: Any]) {
        self.storage = storage
    }

    public func rawValue(forKey key: String) -> Any? {
        storage[key]
    }
}

public struct CFPreferencesValues: DockPreferencesValues {
    private let domain: CFString

    public init(domain: String = DockPreferencesReader.dockDomain) {
        self.domain = domain as CFString
    }

    public func synchronize() {
        CFPreferencesAppSynchronize(domain)
    }

    public func rawValue(forKey key: String) -> Any? {
        CFPreferencesCopyAppValue(key as CFString, domain)
    }
}
