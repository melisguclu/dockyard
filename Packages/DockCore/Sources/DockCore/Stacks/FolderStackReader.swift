import Foundation

public protocol FolderStackReading: Sendable {
    func contents(of url: URL, arrangement: FolderStackArrangement) async -> FolderStackContents
}

public struct FolderStackReader: FolderStackReading {
    public static let entryLimit = 200

    private static let keys: [URLResourceKey] = [
        .isDirectoryKey,
        .isPackageKey,
        .isHiddenKey,
        .localizedNameKey,
        .localizedTypeDescriptionKey,
        .addedToDirectoryDateKey,
        .contentModificationDateKey,
        .creationDateKey,
    ]

    public init() {}

    public func contents(of url: URL, arrangement: FolderStackArrangement) async -> FolderStackContents {
        await Task.detached(priority: .userInitiated) {
            Self.read(url, arrangement: arrangement)
        }.value
    }

    public static func read(_ url: URL, arrangement: FolderStackArrangement) -> FolderStackContents {
        let state = DockLog.signposts.beginInterval("stack-read")
        defer { DockLog.signposts.endInterval("stack-read", state) }

        let children: [URL]
        do {
            children = try FileManager.default.contentsOfDirectory(
                at: url,
                includingPropertiesForKeys: keys,
                options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
            )
        } catch {
            DockLog.workspace.error(
                "A stack could not be read: \(error.localizedDescription, privacy: .private)"
            )
            return .unreadable(url)
        }

        let described = children.compactMap(describe)
        let sorted = sort(described, by: arrangement)
        let visible = sorted.prefix(entryLimit).map(\.entry)
        return FolderStackContents(
            url: url,
            entries: Array(visible),
            truncated: max(sorted.count - visible.count, 0)
        )
    }

    private struct Described {
        let entry: FolderStackEntry
        let kind: String
        let added: Date?
        let modified: Date?
        let created: Date?
    }

    private static func describe(_ url: URL) -> Described? {
        let values = try? url.resourceValues(forKeys: Set(keys))
        guard values?.isHidden != true else { return nil }
        let isPackage = values?.isPackage ?? false
        let isDirectory = (values?.isDirectory ?? false) && !isPackage
        return Described(
            entry: FolderStackEntry(
                url: url,
                name: values?.localizedName ?? url.lastPathComponent,
                isDirectory: isDirectory,
                isApplication: url.pathExtension == "app"
            ),
            kind: values?.localizedTypeDescription ?? "",
            added: values?.addedToDirectoryDate,
            modified: values?.contentModificationDate,
            created: values?.creationDate
        )
    }

    private static func sort(_ items: [Described], by arrangement: FolderStackArrangement) -> [Described] {
        switch arrangement {
        case .name:
            return items.sorted(by: byName)
        case .dateAdded:
            return items.sorted { newest($0.added, $1.added, tie: ($0, $1)) }
        case .dateModified:
            return items.sorted { newest($0.modified, $1.modified, tie: ($0, $1)) }
        case .dateCreated:
            return items.sorted { newest($0.created, $1.created, tie: ($0, $1)) }
        case .kind:
            return items.sorted { first, second in
                let comparison = first.kind.localizedStandardCompare(second.kind)
                guard comparison == .orderedSame else { return comparison == .orderedAscending }
                return byName(first, second)
            }
        }
    }

    private static func byName(_ first: Described, _ second: Described) -> Bool {
        first.entry.name.localizedStandardCompare(second.entry.name) == .orderedAscending
    }

    private static func newest(_ first: Date?, _ second: Date?, tie: (Described, Described)) -> Bool {
        guard let first else { return false }
        guard let second else { return true }
        guard first != second else { return byName(tie.0, tie.1) }
        return first > second
    }
}
