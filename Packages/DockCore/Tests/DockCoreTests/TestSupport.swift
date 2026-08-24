import DockCore
import Foundation
import Testing

enum Fixture: String, CaseIterable {
    case minimal
    case typical
    case withFolders = "with-folders"
    case withSpacers = "with-spacers"
    case corrupt
    case maliciousURL = "malicious-url"
    case tahoe = "tahoe-26"

    var dictionary: [String: Any] {
        guard let url = Bundle.module.url(
            forResource: "Fixtures/\(rawValue)",
            withExtension: "plist"
        ) else {
            return [:]
        }
        guard let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(
                from: data,
                options: [],
                format: nil
              ) as? [String: Any]
        else {
            return [:]
        }
        return plist
    }

    var reader: DockPreferencesReader {
        .fixture(dictionary)
    }

    var raw: RawDockPreferences {
        reader.read()
    }

    func resolved(environment: TileEnvironment = TestEnvironment.standard) -> ResolvedDockPreferences {
        ResolvedDockPreferences.resolve(raw, environment: environment)
    }
}

enum TestEnvironment {
    static let applications: Set<String> = [
        "/System/Library/CoreServices/Finder.app",
        "/Applications/Safari.app",
        "/System/Applications/Mail.app",
        "/Applications/Xcode.app",
        "/Applications/Notes.app",
        "/System/Applications/Messages.app"
    ]

    static let directories: Set<String> = [
        "/Users/tester/Downloads",
        "/Users/tester/Documents"
    ]

    static let standard = TileEnvironment(
        resolveSymlinks: { $0 },
        fileExists: { applications.contains($0.path) || directories.contains($0.path) },
        directoryExists: { directories.contains($0.path) },
        isLaunchableApplicationBundle: { applications.contains($0.path) },
        trashIsEmpty: { true },
        finderURL: { TileEnvironment.systemFinderURL }
    )

    static let emptyTrash = standard

    static let withoutFinder = TileEnvironment(
        resolveSymlinks: { $0 },
        fileExists: standard.fileExists,
        directoryExists: standard.directoryExists,
        isLaunchableApplicationBundle: standard.isLaunchableApplicationBundle,
        trashIsEmpty: { true },
        finderURL: { nil }
    )

    static let fullTrash = TileEnvironment(
        resolveSymlinks: standard.resolveSymlinks,
        fileExists: standard.fileExists,
        directoryExists: standard.directoryExists,
        isLaunchableApplicationBundle: standard.isLaunchableApplicationBundle,
        trashIsEmpty: { false },
        finderURL: standard.finderURL
    )
}

enum TestApplications {
    static func running(
        bundleIdentifier: String?,
        path: String?,
        pid: pid_t,
        sequence: UInt64,
        isActive: Bool = false,
        isHidden: Bool = false,
        name: String = "App"
    ) -> RunningApplicationState {
        RunningApplicationState(
            processIdentifier: pid,
            bundleIdentifier: bundleIdentifier,
            bundleURL: path.map { URL(fileURLWithPath: $0) },
            localizedName: name,
            isActive: isActive,
            isHidden: isHidden,
            launchSequence: sequence
        )
    }
}

extension DockTile {
    var isApplication: Bool {
        if case .application = kind { return true }
        return false
    }

    var isSeparator: Bool {
        if case .separator = kind { return true }
        return false
    }

    var isTrash: Bool {
        if case .trash = kind { return true }
        return false
    }

    var spacerWidth: SpacerWidth? {
        if case .spacer(let width) = kind { return width }
        return nil
    }
}

extension DockTile {
    var isMinimizedWindow: Bool {
        if case .minimizedWindow = kind { return true }
        return false
    }
}

enum TestWindows {
    static func minimized(
        token: UInt64,
        pid: pid_t = 900,
        index: Int = 0,
        title: String = "Window",
        application: String = "App",
        bundleIdentifier: String? = "com.example.app",
        path: String? = "/Applications/Safari.app"
    ) -> MinimizedWindow {
        MinimizedWindow(
            token: token,
            processIdentifier: pid,
            index: index,
            title: title,
            applicationName: application,
            bundleIdentifier: bundleIdentifier,
            applicationURL: path.map { URL(fileURLWithPath: $0) }
        )
    }
}
