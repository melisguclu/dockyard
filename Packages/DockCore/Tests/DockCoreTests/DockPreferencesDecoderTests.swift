import DockCore
import Foundation
import Testing

@Suite("Dock preference decoding")
struct DockPreferencesDecoderTests {
    @Test("Every fixture loads")
    func fixturesLoad() {
        for fixture in Fixture.allCases {
            #expect(!fixture.dictionary.isEmpty, "fixture \(fixture.rawValue) is missing")
        }
    }

    @Test("A minimal domain decodes to empty arrays and documented defaults")
    func minimalDefaults() {
        let raw = Fixture.minimal.raw

        #expect(raw.persistentApps.isEmpty)
        #expect(raw.persistentOthers.isEmpty)
        #expect(raw.recentApps.isEmpty)
        #expect(raw.appearance == DockAppearance.default)
        #expect(raw.appearance.tileSize == 48)
        #expect(raw.appearance.largeSize == 128)
        #expect(raw.appearance.showProcessIndicators)
        #expect(raw.appearance.launchAnimation)
        #expect(raw.appearance.showRecents)
        #expect(raw.appearance.orientation == .bottom)
    }

    @Test("A typical domain decodes pinned apps in order")
    func typicalOrdering() {
        let raw = Fixture.typical.raw

        #expect(raw.persistentApps.count == 3)
        #expect(raw.persistentApps.map(\.bundleIdentifier) == [
            "com.apple.Safari",
            "com.apple.mail",
            "com.apple.dt.Xcode"
        ])
        #expect(raw.persistentApps.map(\.label) == ["Safari", "Mail", "Xcode"])
        #expect(raw.recentApps.count == 1)
        #expect(raw.appearance.magnificationEnabled)
    }

    @Test("Folder and URL tiles decode with their presentation keys")
    func folderDecoding() {
        let raw = Fixture.withFolders.raw

        #expect(raw.persistentOthers.count == 3)
        #expect(raw.persistentOthers[0].tileType == .directory)
        #expect(raw.persistentOthers[0].displayAs == 1)
        #expect(raw.persistentOthers[0].showAs == 2)
        #expect(raw.persistentOthers[0].arrangement == 1)
        #expect(raw.persistentOthers[2].tileType == .url)
        #expect(raw.persistentOthers[2].urlString == "https://example.com/handbook")
        #expect(raw.appearance.showRecents == false)
    }

    @Test("Spacer tile types are preserved in place")
    func spacerDecoding() {
        let raw = Fixture.withSpacers.raw

        #expect(raw.persistentApps.map(\.tileType) == [
            .file,
            .spacer,
            .file,
            .smallSpacer,
            .flexSpacer
        ])
    }

    @Test("Malformed entries are dropped without losing valid neighbours")
    func corruptEntriesAreDropped() {
        let raw = Fixture.corrupt.raw

        #expect(raw.persistentApps.count == 3)
        #expect(raw.persistentApps.contains { $0.bundleIdentifier == "com.apple.Safari" })
        #expect(raw.persistentOthers.isEmpty)
    }

    @Test("Out-of-range appearance values are clamped")
    func appearanceClamping() {
        let appearance = Fixture.corrupt.raw.appearance

        #expect(appearance.tileSize == DockAppearance.tileSizeRange.upperBound)
        #expect(appearance.largeSize == DockAppearance.largeSizeRange.lowerBound)
        #expect(appearance.autoHideDelay == DockAppearance.autoHideDelayRange.upperBound)
        #expect(appearance.autoHideTimeModifier == DockAppearance.autoHideTimeModifierRange.lowerBound)
    }

    @Test("An unknown orientation falls back to bottom")
    func orientationFallback() {
        #expect(Fixture.corrupt.raw.appearance.orientation == .bottom)
    }

    @Test("A newer macOS layout decodes its full appearance")
    func tahoeAppearance() {
        let appearance = Fixture.tahoe.raw.appearance

        #expect(appearance.tileSize == 64)
        #expect(appearance.largeSize == 96)
        #expect(appearance.orientation == .left)
        #expect(appearance.orientation.isVertical)
        #expect(appearance.autoHide)
        #expect(appearance.autoHideDelay == 0.2)
        #expect(appearance.autoHideTimeModifier == 0.75)
        #expect(appearance.showProcessIndicators == false)
        #expect(appearance.launchAnimation == false)
        #expect(appearance.minimizeToApplication)
    }

    @Test("Unknown tile types never decode as applications")
    func unknownTileTypesDropped() {
        let entry = DockPreferencesDecoder.decodeEntry([
            "tile-type": "hologram-tile",
            "tile-data": ["file-label": "Nope"]
        ])
        #expect(entry == nil)
    }

    @Test("Numeric preferences stored as strings still decode")
    func stringEncodedNumbers() {
        let values = DictionaryPreferencesValues([
            "tilesize": "72",
            "magnification": "1",
            "orientation": "right",
            "launchanim": "0"
        ])
        let appearance = DockPreferencesDecoder.decodeAppearance(values)

        #expect(appearance.tileSize == 72)
        #expect(appearance.magnificationEnabled)
        #expect(appearance.orientation == .right)
        #expect(appearance.launchAnimation == false)
    }
}
