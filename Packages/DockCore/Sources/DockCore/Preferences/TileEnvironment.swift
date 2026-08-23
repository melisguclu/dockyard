import Foundation

public struct TileEnvironment: Sendable {
    public var resolveSymlinks: @Sendable (URL) -> URL
    public var fileExists: @Sendable (URL) -> Bool
    public var directoryExists: @Sendable (URL) -> Bool
    public var isLaunchableApplicationBundle: @Sendable (URL) -> Bool
    public var trashIsEmpty: @Sendable () -> Bool
    public var finderURL: @Sendable () -> URL?

    public init(
        resolveSymlinks: @escaping @Sendable (URL) -> URL = { $0.resolvingSymlinksInPath() },
        fileExists: @escaping @Sendable (URL) -> Bool,
        directoryExists: @escaping @Sendable (URL) -> Bool,
        isLaunchableApplicationBundle: @escaping @Sendable (URL) -> Bool,
        trashIsEmpty: @escaping @Sendable () -> Bool,
        finderURL: @escaping @Sendable () -> URL? = { TileEnvironment.systemFinderURL }
    ) {
        self.resolveSymlinks = resolveSymlinks
        self.fileExists = fileExists
        self.directoryExists = directoryExists
        self.isLaunchableApplicationBundle = isLaunchableApplicationBundle
        self.trashIsEmpty = trashIsEmpty
        self.finderURL = finderURL
    }

    public static let live = TileEnvironment(
        resolveSymlinks: { $0.resolvingSymlinksInPath() },
        fileExists: { FileManager.default.fileExists(atPath: $0.path) },
        directoryExists: { url in
            var isDirectory: ObjCBool = false
            let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
            return exists && isDirectory.boolValue
        },
        isLaunchableApplicationBundle: { url in
            guard let bundle = Bundle(url: url) else { return false }
            return bundle.infoDictionary?["CFBundleExecutable"] is String
        },
        trashIsEmpty: {
            guard let trash = TileEnvironment.trashDirectory else { return true }
            guard let entries = DirectoryEntryCount.count(of: trash) else { return true }
            return entries == 0
        },
        finderURL: {
            let url = TileEnvironment.systemFinderURL
            return FileManager.default.fileExists(atPath: url.path) ? url : nil
        }
    )

    public static let permissive = TileEnvironment(
        resolveSymlinks: { $0 },
        fileExists: { _ in true },
        directoryExists: { _ in true },
        isLaunchableApplicationBundle: { $0.pathExtension == "app" },
        trashIsEmpty: { true },
        finderURL: { TileEnvironment.systemFinderURL }
    )

    public static let systemFinderURL = URL(
        fileURLWithPath: "/System/Library/CoreServices/Finder.app",
        isDirectory: true
    )

    public static let finderBundleIdentifier = "com.apple.finder"

    public static var trashDirectory: URL? {
        try? FileManager.default.url(
            for: .trashDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
    }
}
