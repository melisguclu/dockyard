#!/usr/bin/env swift

import AppKit
import ApplicationServices
import Foundation

let arguments = Array(CommandLine.arguments.dropFirst())
let watches = arguments.contains("--watch")
let seconds = Double(arguments.first { Double($0) != nil } ?? "30") ?? 30

func value(_ subject: AXUIElement, _ attribute: String) -> CFTypeRef? {
    var result: CFTypeRef?
    guard AXUIElementCopyAttributeValue(subject, attribute as CFString, &result) == .success else {
        return nil
    }
    return result
}

func text(_ subject: AXUIElement, _ attribute: String) -> String? {
    value(subject, attribute) as? String
}

func children(_ subject: AXUIElement) -> [AXUIElement] {
    (value(subject, kAXChildrenAttribute as String) as? [AXUIElement]) ?? []
}

func attributes(_ subject: AXUIElement) -> [String] {
    var names: CFArray?
    guard AXUIElementCopyAttributeNames(subject, &names) == .success else { return [] }
    return (names as? [String]) ?? []
}

guard AXIsProcessTrusted() else {
    print("This process is not trusted for Accessibility. Grant it and run again.")
    exit(2)
}

guard
    let dock = NSRunningApplication
        .runningApplications(withBundleIdentifier: "com.apple.dock")
        .first
else {
    print("No Dock process")
    exit(1)
}

let application = AXUIElementCreateApplication(dock.processIdentifier)
AXUIElementSetMessagingTimeout(application, 3)

guard let list = children(application).first(where: { text($0, kAXRoleAttribute as String) == kAXListRole })
else {
    print("The Dock has no AXList child. The tree changed; DockItemInspector needs revisiting.")
    exit(1)
}

let items = children(list)
print("Dock pid \(dock.processIdentifier), \(items.count) items")
print("Item attributes: \(attributes(items.first ?? list))")
print("")

for (index, item) in items.enumerated() {
    let subrole = text(item, kAXSubroleAttribute as String) ?? "-"
    let title = text(item, kAXTitleAttribute as String) ?? "-"
    let badge = text(item, "AXStatusLabel") ?? "-"
    let url = (value(item, "AXURL") as? NSURL)?.path ?? "-"
    let running = (value(item, "AXIsApplicationRunning") as? NSNumber)?.boolValue ?? false
    print(
        """
        [\(index)] \(subrole) title=\(title) badge=\(badge) running=\(running ? 1 : 0) url=\(url)
        """
    )
}

guard watches else { exit(0) }

print("")
print("Notification support on the Dock's application element:")

let candidates = [
    kAXCreatedNotification,
    kAXUIElementDestroyedNotification,
    kAXValueChangedNotification,
    kAXTitleChangedNotification,
    kAXLayoutChangedNotification,
]

let callback: AXObserverCallback = { _, element, notification, _ in
    let role = text(element, kAXRoleAttribute as String) ?? "?"
    let title = text(element, kAXTitleAttribute as String) ?? "-"
    print("  \(notification as String) role=\(role) title=\(title)")
}

var created: AXObserver?
guard AXObserverCreate(dock.processIdentifier, callback, &created) == .success, let observer = created
else {
    print("Could not create an observer")
    exit(1)
}

for notification in candidates {
    let status = AXObserverAddNotification(observer, application, notification as CFString, nil)
    let verdict = status == .success ? "supported" : "unsupported (\(status.rawValue))"
    print("  \(notification): \(verdict)")
}

print("")
print("Watching for \(Int(seconds)) s. Launch or quit an app, or minimize a window.")
CFRunLoopAddSource(CFRunLoopGetCurrent(), AXObserverGetRunLoopSource(observer), .defaultMode)
CFRunLoopRunInMode(.defaultMode, seconds, false)
