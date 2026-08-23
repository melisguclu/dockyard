import Foundation

public enum DockPreferencesDecoder {
    public static func decodeEntries(from array: [Any]) -> [RawDockEntry] {
        array.compactMap { element in
            guard let dictionary = element as? [String: Any] else { return nil }
            return decodeEntry(dictionary)
        }
    }

    public static func decodeEntry(_ dictionary: [String: Any]) -> RawDockEntry? {
        guard let rawType = dictionary["tile-type"] as? String else {
            DockLog.preferences.debug("Dropping dock entry without tile-type")
            return nil
        }
        guard let tileType = DockTileType(rawValue: rawType) else {
            DockLog.preferences.debug("Dropping dock entry with unknown tile-type \(rawType, privacy: .public)")
            return nil
        }

        let tileData = dictionary["tile-data"] as? [String: Any] ?? [:]

        return RawDockEntry(
            tileType: tileType,
            label: label(from: tileData),
            bundleIdentifier: nonEmptyString(tileData["bundle-identifier"]),
            urlString: urlString(from: tileData),
            displayAs: integer(tileData["displayas"]),
            showAs: integer(tileData["showas"])
        )
    }

    public static func decodeAppearance(_ values: DockPreferencesValues) -> DockAppearance {
        DockAppearance(
            tileSize: CGFloat(values.double("tilesize", default: Double(DockAppearance.defaultTileSize)))
                .clamped(to: DockAppearance.tileSizeRange),
            largeSize: CGFloat(values.double("largesize", default: Double(DockAppearance.defaultLargeSize)))
                .clamped(to: DockAppearance.largeSizeRange),
            magnificationEnabled: values.bool("magnification", default: false),
            orientation: DockOrientation(rawValue: values.string("orientation", default: "bottom")) ?? .bottom,
            autoHide: values.bool("autohide", default: false),
            autoHideDelay: values.double("autohide-delay", default: 0.5)
                .clamped(to: DockAppearance.autoHideDelayRange),
            autoHideTimeModifier: values.double("autohide-time-modifier", default: 1.0)
                .clamped(to: DockAppearance.autoHideTimeModifierRange),
            showProcessIndicators: values.bool("show-process-indicators", default: true),
            showRecents: values.bool("show-recents", default: true),
            minimizeToApplication: values.bool("minimize-to-application", default: false)
        )
    }

    private static func label(from tileData: [String: Any]) -> String? {
        let candidates = ["file-label", "label", "url-label"]
        for key in candidates {
            if let value = nonEmptyString(tileData[key]) {
                return value.clampedLength(to: DockTile.maximumLabelLength)
            }
        }
        return nil
    }

    private static func urlString(from tileData: [String: Any]) -> String? {
        if let fileData = tileData["file-data"] as? [String: Any],
           let string = nonEmptyString(fileData["_CFURLString"]) {
            return string
        }
        if let urlData = tileData["url"] as? [String: Any],
           let string = nonEmptyString(urlData["_CFURLString"]) {
            return string
        }
        return nonEmptyString(tileData["_CFURLString"])
    }

    private static func nonEmptyString(_ value: Any?) -> String? {
        guard let string = value as? String, !string.isEmpty else { return nil }
        return string
    }

    private static func integer(_ value: Any?) -> Int? {
        if let number = value as? Int { return number }
        if let number = value as? NSNumber { return number.intValue }
        return nil
    }
}
