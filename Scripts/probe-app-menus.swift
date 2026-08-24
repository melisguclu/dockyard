#!/usr/bin/env swift

import AppKit
import ApplicationServices
import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())
let verbose = arguments.contains("--verbose")
let names = arguments.filter { !$0.hasPrefix("--") }

func many(_ subject: AXUIElement, _ attribute: String) -> [AXUIElement] {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(subject, attribute as CFString, &value) == .success else { return [] }
    return (value as? [AXUIElement]) ?? []
}

func child(_ subject: AXUIElement, _ attribute: String) -> AXUIElement? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(subject, attribute as CFString, &value) == .success else { return nil }
    guard let value, CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
    return (([value] as CFArray) as? [AXUIElement])?.first
}

func text(_ subject: AXUIElement, _ attribute: String) -> String? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(subject, attribute as CFString, &value) == .success else { return nil }
    return value as? String
}

func integer(_ subject: AXUIElement, _ attribute: String) -> Int? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(subject, attribute as CFString, &value) == .success else { return nil }
    return (value as? NSNumber)?.intValue
}

func flag(_ subject: AXUIElement, _ attribute: String) -> Bool? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(subject, attribute as CFString, &value) == .success else { return nil }
    return value as? Bool
}

struct Entry {
    let menuIndex: Int
    let menuTitle: String
    let title: String
    let key: String?
    let modifiers: Int
    let isEnabled: Bool
    let hasSubmenu: Bool

    var shortcut: String {
        guard let key, !key.isEmpty, modifiers & 8 == 0 else { return "" }
        var glyphs = ""
        if modifiers & 4 != 0 { glyphs += "⌃" }
        if modifiers & 2 != 0 { glyphs += "⌥" }
        if modifiers & 1 != 0 { glyphs += "⇧" }
        return "\(glyphs)⌘\(printable(key))"
    }

    private func printable(_ key: String) -> String {
        switch key {
        case "\u{F700}": return "↑"
        case "\u{F701}": return "↓"
        case "\u{F702}": return "←"
        case "\u{F703}": return "→"
        default: return key
        }
    }
}

struct Walk {
    let entries: [Entry]
    let calls: Int
    let seconds: Double
}

func walk(_ application: AXUIElement) -> Walk {
    var calls = 1
    let start = DispatchTime.now()
    var entries: [Entry] = []
    guard let bar = child(application, kAXMenuBarAttribute) else {
        return Walk(entries: [], calls: calls, seconds: 0)
    }
    calls += 1
    for (index, top) in many(bar, kAXChildrenAttribute).enumerated() where index >= 2 {
        calls += 2
        guard let menuTitle = text(top, kAXTitleAttribute) else { continue }
        for menu in many(top, kAXChildrenAttribute) {
            calls += 1
            for item in many(menu, kAXChildrenAttribute) {
                calls += 3
                guard let title = text(item, kAXTitleAttribute), !title.isEmpty else { continue }
                let modifiers = integer(item, kAXMenuItemCmdModifiersAttribute) ?? 8
                let key = modifiers & 8 == 0 ? text(item, kAXMenuItemCmdCharAttribute) : nil
                let hasSubmenu = key == nil && !many(item, kAXChildrenAttribute).isEmpty
                if key != nil { calls += 1 } else { calls += 1 }
                entries.append(
                    Entry(
                        menuIndex: index,
                        menuTitle: menuTitle,
                        title: title,
                        key: key,
                        modifiers: modifiers,
                        isEnabled: flag(item, kAXEnabledAttribute) ?? true,
                        hasSubmenu: hasSubmenu
                    )
                )
            }
        }
    }
    let seconds = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1e9
    return Walk(entries: entries, calls: calls, seconds: seconds)
}

let creationShortcuts = [("N", 0), ("N", 1), ("N", 2), ("T", 0)]

func selected(_ entries: [Entry]) -> [String] {
    let creation =
        entries
        .filter { $0.menuIndex == 2 && $0.isEnabled && !$0.hasSubmenu && $0.modifiers & 8 == 0 }
        .filter { entry in
            creationShortcuts.contains { $0.0 == entry.key?.uppercased() && $0.1 == entry.modifiers }
        }
        .sorted { first, second in
            let rank = { (entry: Entry) -> Int in
                creationShortcuts.firstIndex { $0.0 == entry.key?.uppercased() && $0.1 == entry.modifiers } ?? 9
            }
            return rank(first) < rank(second)
        }

    let next = Set(entries.filter { $0.key == "\u{F703}" && $0.modifiers == 0 }.map(\.menuIndex))
    let previous = Set(entries.filter { $0.key == "\u{F702}" && $0.modifiers == 0 }.map(\.menuIndex))
    var transport: [Entry] = []
    if let index = next.intersection(previous).min() {
        var toggleFound = false
        transport = entries.filter { entry in
            guard entry.menuIndex == index, entry.isEnabled, !entry.hasSubmenu else { return false }
            if entry.modifiers & 8 == 0 {
                guard entry.modifiers == 0 else { return false }
                return entry.key == "\u{F702}" || entry.key == "\u{F703}"
            }
            guard !toggleFound else { return false }
            toggleFound = true
            return true
        }
    }

    var seen: Set<String> = []
    return (creation + transport).compactMap { seen.insert($0.title).inserted ? $0.title : nil }
}

func windows(_ application: AXUIElement) -> (titles: [String], seconds: Double) {
    let start = DispatchTime.now()
    let titles = many(application, kAXWindowsAttribute).compactMap { window -> String? in
        guard let title = text(window, kAXTitleAttribute), !title.isEmpty else { return nil }
        let minimized = flag(window, kAXMinimizedAttribute) ?? false
        return minimized ? "\(title) (minimized)" : title
    }
    return (titles, Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1e9)
}

guard AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt" as CFString: kCFBooleanTrue] as CFDictionary) else {
    print("Not trusted. Grant Accessibility access to this terminal and run again.")
    exit(1)
}

let applications = NSWorkspace.shared.runningApplications
    .filter { $0.activationPolicy == .regular }
    .filter { names.isEmpty || names.contains($0.localizedName ?? "") }
    .sorted { ($0.localizedName ?? "") < ($1.localizedName ?? "") }

print("app                   entries  calls    cold     warm  windows")
print(String(repeating: "-", count: 78))

for application in applications {
    let element = AXUIElementCreateApplication(application.processIdentifier)
    AXUIElementSetMessagingTimeout(element, 3)

    let cold = walk(element)
    let warm = walk(element)
    let windowRead = windows(element)

    let label = (application.localizedName ?? "?").padding(toLength: 20, withPad: " ", startingAt: 0)
    print(
        label
            + String(
                format: " %7d %6d %7.1fms %6.1fms %8.1fms",
                cold.entries.count,
                cold.calls,
                cold.seconds * 1000,
                warm.seconds * 1000,
                windowRead.seconds * 1000
            )
    )

    let commands = selected(warm.entries)
    if !commands.isEmpty {
        print("    commands: \(commands.joined(separator: " · "))")
    }
    if !windowRead.titles.isEmpty {
        print("    windows:  \(windowRead.titles.joined(separator: " · "))")
    }
    guard verbose else { continue }
    for entry in warm.entries where entry.menuIndex == 2 || !entry.shortcut.isEmpty {
        let marks = [entry.isEnabled ? nil : "disabled", entry.hasSubmenu ? "submenu" : nil].compactMap { $0 }
        print(
            "      [\(entry.menuIndex)] \(entry.menuTitle) > \(entry.title)  \(entry.shortcut) \(marks.joined(separator: " "))"
        )
    }
}
