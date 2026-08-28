import DockCore
import Foundation
import Testing

@Suite("A stack reads its folder the way the Dock arranges it")
struct FolderStackReaderTests {
    private func makeFolder(_ names: [String]) throws -> URL {
        let root = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("dockyard-stack-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for name in names {
            let child = root.appendingPathComponent(name)
            if name.hasSuffix("/") {
                try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
            } else {
                try Data().write(to: child)
            }
        }
        return root
    }

    @Test("Entries come back sorted by name, the Dock's own default")
    func nameOrder() throws {
        let folder = try makeFolder(["banana.txt", "Apple.txt", "cherry.txt"])
        defer { try? FileManager.default.removeItem(at: folder) }

        let contents = FolderStackReader.read(folder, arrangement: .name)

        #expect(contents.isReadable)
        #expect(contents.entries.map(\.name) == ["Apple.txt", "banana.txt", "cherry.txt"])
        #expect(contents.truncated == 0)
    }

    @Test("A directory is marked as one, so a click can open it rather than a file")
    func directories() throws {
        let folder = try makeFolder(["Reports/", "note.txt"])
        defer { try? FileManager.default.removeItem(at: folder) }

        let contents = FolderStackReader.read(folder, arrangement: .name)
        let directories = contents.entries.filter(\.isDirectory).map(\.name)

        #expect(directories == ["Reports"])
    }

    @Test("Dotfiles stay out, exactly as they do in the Dock's own stack")
    func hiddenEntries() throws {
        let folder = try makeFolder([".hidden", "visible.txt"])
        defer { try? FileManager.default.removeItem(at: folder) }

        #expect(FolderStackReader.read(folder, arrangement: .name).entries.map(\.name) == ["visible.txt"])
    }

    @Test("A folder past the entry limit reports what it left out instead of dropping it silently")
    func truncation() throws {
        let names = (0..<(FolderStackReader.entryLimit + 12)).map { String(format: "file-%04d.txt", $0) }
        let folder = try makeFolder(names)
        defer { try? FileManager.default.removeItem(at: folder) }

        let contents = FolderStackReader.read(folder, arrangement: .name)

        #expect(contents.entries.count == FolderStackReader.entryLimit)
        #expect(contents.truncated == 12)
    }

    @Test("An unreadable folder is a state of its own, not an empty one")
    func unreadable() {
        let missing = URL(fileURLWithPath: "/Users/nobody/dockyard-missing", isDirectory: true)
        let contents = FolderStackReader.read(missing, arrangement: .name)

        #expect(!contents.isReadable)
        #expect(contents.entries.isEmpty)
    }

    @Test("Sorting by kind groups the types and falls back to the name inside a group")
    func kindOrder() throws {
        let folder = try makeFolder(["b.txt", "a.txt", "c.txt"])
        defer { try? FileManager.default.removeItem(at: folder) }

        let contents = FolderStackReader.read(folder, arrangement: .kind)

        #expect(contents.entries.map(\.name) == ["a.txt", "b.txt", "c.txt"])
    }
}
