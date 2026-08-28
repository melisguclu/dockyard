import DockCore
import Foundation
import Testing

@Suite("Tile validation treats the Dock domain as untrusted input")
struct TileValidationTests {
    @Test("A well-formed application bundle resolves")
    func validApplication() {
        let url = TileValidation.resolveApplicationURL(
            from: "file:///Applications/Safari.app/",
            environment: TestEnvironment.standard
        )
        #expect(url?.path == "/Applications/Safari.app")
    }

    @Test("A plain executable outside a bundle is never launchable")
    func executableRejected() {
        #expect(
            TileValidation.resolveApplicationURL(
                from: "file:///tmp/payload.sh",
                environment: TestEnvironment.standard
            ) == nil
        )
    }

    @Test("A relative traversal is normalised and then rejected when absent")
    func traversalRejected() {
        #expect(
            TileValidation.resolveApplicationURL(
                from: "file:///Applications/../../../tmp/Evil.app/",
                environment: TestEnvironment.standard
            ) == nil
        )
    }

    @Test("A remote URL is never treated as an application")
    func remoteApplicationRejected() {
        #expect(
            TileValidation.resolveApplicationURL(
                from: "https://evil.example/Evil.app",
                environment: TestEnvironment.standard
            ) == nil
        )
    }

    @Test("A missing application bundle is dropped")
    func missingApplicationRejected() {
        #expect(
            TileValidation.resolveApplicationURL(
                from: "file:///Applications/Deleted.app/",
                environment: TestEnvironment.standard
            ) == nil
        )
    }

    @Test("An app-extension path that is not a real bundle is dropped")
    func nonBundleRejected() {
        let environment = TileEnvironment(
            resolveSymlinks: { $0 },
            fileExists: { _ in true },
            directoryExists: { _ in true },
            isLaunchableApplicationBundle: { _ in false },
            trashIsEmpty: { true }
        )
        #expect(
            TileValidation.resolveApplicationURL(
                from: "file:///Applications/Fake.app/",
                environment: environment
            ) == nil
        )
    }

    @Test("Only http and https survive URL tile validation", arguments: [
        ("https://example.com/x", true),
        ("http://example.com", true),
        ("javascript:alert(1)", false),
        ("file:///etc/passwd", false),
        ("ftp://example.com", false),
        ("https://", false)
    ])
    func webURLValidation(input: String, expected: Bool) {
        #expect((TileValidation.resolveWebURL(from: input) != nil) == expected)
    }

    @Test("Labels are trimmed, flattened, and length-clamped")
    func labelSanitising() {
        let long = String(repeating: "L", count: 4096)
        #expect(TileValidation.sanitizedLabel(long, fallback: "x").count == DockTile.maximumLabelLength)
        #expect(TileValidation.sanitizedLabel("  Safari  ", fallback: "x") == "Safari")
        #expect(TileValidation.sanitizedLabel("", fallback: "Fallback") == "Fallback")
        #expect(TileValidation.sanitizedLabel("a\nb", fallback: "x") == "a b")
        #expect(TileValidation.sanitizedLabel(nil, fallback: "Fallback") == "Fallback")
    }

    @Test("A hostile domain yields only the entries that pass every guard")
    func maliciousFixture() {
        let resolved = Fixture.maliciousURL.resolved()

        #expect(resolved.pinnedApps.count == 1)
        #expect(resolved.pinnedApps[0].url?.path == "/Applications/Safari.app")
        #expect(resolved.pinnedApps[0].label.count == DockTile.maximumLabelLength)
    }

    @Test("Directory tiles require an existing directory")
    func directoryValidation() {
        let resolved = Fixture.withFolders.resolved()

        #expect(resolved.others.count == 3)
        #expect(resolved.others[0].label == "Downloads")
        if case .folder(let presentation) = resolved.others[0].kind {
            #expect(presentation.displayAs == .folder)
            #expect(presentation.showAs == .grid)
            #expect(presentation.arrangement == .name)
        } else {
            Issue.record("expected a folder tile")
        }
    }

    @Test("A directory tile pointing at a missing path is dropped")
    func missingDirectoryDropped() {
        let entry = RawDockEntry(
            tileType: .directory,
            label: "Ghost",
            urlString: "file:///Users/tester/Ghost/"
        )
        #expect(TileValidation.resolve(entry: entry, environment: TestEnvironment.standard) == nil)
    }

    @Test("Spacer entries never carry a URL")
    func spacersResolveWithoutURL() {
        let widths: [DockTileType: SpacerWidth] = [
            .spacer: .full,
            .smallSpacer: .small,
            .flexSpacer: .flexible
        ]
        for (type, width) in widths {
            let resolved = TileValidation.resolve(
                entry: RawDockEntry(tileType: type),
                environment: TestEnvironment.standard
            )
            #expect(resolved?.url == nil)
            #expect(resolved?.kind == .spacer(width))
        }
    }
}
