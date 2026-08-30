#!/usr/bin/env swift

import AppKit
import CoreGraphics
import Foundation

let repeats = Int(CommandLine.arguments.dropFirst().first ?? "10") ?? 10

func barFrame() -> CGRect? {
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly], kCGNullWindowID) as? [[String: Any]]
    var widest: CGRect?
    for window in list ?? [] {
        guard window[kCGWindowOwnerName as String] as? String == "Dockyard" else { continue }
        guard let raw = window[kCGWindowBounds as String] as? [String: Any],
              let bounds = CGRect(dictionaryRepresentation: raw as CFDictionary),
              bounds.width > 200, bounds.height > 20
        else { continue }
        if widest == nil || bounds.width > widest!.width { widest = bounds }
    }
    return widest
}

@discardableResult
func shell(_ arguments: [String]) -> Int32 {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = arguments
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try? process.run()
    process.waitUntilExit()
    return process.terminationStatus
}

func waitForChange(from baseline: CGRect, timeout: Double) -> Double? {
    let start = CFAbsoluteTimeGetCurrent()
    while CFAbsoluteTimeGetCurrent() - start < timeout {
        if let now = barFrame(), now != baseline {
            return (CFAbsoluteTimeGetCurrent() - start) * 1000
        }
        usleep(500)
    }
    return nil
}

func percentile(_ values: [Double], _ fraction: Double) -> Double {
    let ordered = values.sorted()
    return ordered[min(ordered.count - 1, Int(Double(ordered.count) * fraction))]
}

func summarise(_ name: String, _ samples: [Double]) {
    guard !samples.isEmpty else {
        print("\(name): no sample completed")
        return
    }
    let ordered = samples.sorted()
    print(String(format: "%@: n=%d  p50 %.0f ms  p95 %.0f ms  worst %.0f ms",
                 name, samples.count, ordered[ordered.count / 2],
                 percentile(samples, 0.95), ordered.last!))
}

guard barFrame() != nil else {
    FileHandle.standardError.write(Data("No Dockyard bar is on screen. Launch it first.\n".utf8))
    exit(1)
}

let original = (CFPreferencesCopyAppValue("tilesize" as CFString, "com.apple.dock" as CFString) as? NSNumber)?.intValue ?? 48
var samples: [Double] = []

for pass in 0..<repeats {
    guard let baseline = barFrame() else { break }
    let target = pass % 2 == 0 ? original + 6 : original
    shell(["defaults", "write", "com.apple.dock", "tilesize", "-int", "\(target)"])
    if let elapsed = waitForChange(from: baseline, timeout: 3) {
        samples.append(elapsed)
    }
    Thread.sleep(forTimeInterval: 0.8)
}

shell(["defaults", "write", "com.apple.dock", "tilesize", "-int", "\(original)"])
Thread.sleep(forTimeInterval: 1)

summarise("Dock preference write to resized bar", samples)
print("  tilesize restored to \(original)")

let unpinned = "TextEdit"
let bundle = "com.apple.TextEdit"

func running() -> NSRunningApplication? {
    NSRunningApplication.runningApplications(withBundleIdentifier: bundle).first
}

func waitUntilFinishedLaunching(timeout: Double) -> Double? {
    let start = CFAbsoluteTimeGetCurrent()
    while CFAbsoluteTimeGetCurrent() - start < timeout {
        if running()?.isFinishedLaunching == true { return CFAbsoluteTimeGetCurrent() }
        usleep(500)
    }
    return nil
}

func waitUntilGone(timeout: Double) -> Double? {
    let start = CFAbsoluteTimeGetCurrent()
    while CFAbsoluteTimeGetCurrent() - start < timeout {
        if running() == nil { return CFAbsoluteTimeGetCurrent() }
        usleep(500)
    }
    return nil
}

func waitForFrameChange(from baseline: CGRect, timeout: Double) -> Double? {
    let start = CFAbsoluteTimeGetCurrent()
    while CFAbsoluteTimeGetCurrent() - start < timeout {
        if let now = barFrame(), now != baseline { return CFAbsoluteTimeGetCurrent() }
        usleep(500)
    }
    return nil
}

var launches: [Double] = []
var quits: [Double] = []
var headStart: [Double] = []

for _ in 0..<repeats {
    guard let beforeLaunch = barFrame() else { break }
    let requested = CFAbsoluteTimeGetCurrent()
    shell(["open", "-b", bundle])
    if let tile = waitForFrameChange(from: beforeLaunch, timeout: 10) {
        launches.append((tile - requested) * 1000)
        if let ready = waitUntilFinishedLaunching(timeout: 10) {
            headStart.append((ready - tile) * 1000)
        }
    }
    Thread.sleep(forTimeInterval: 3)

    guard let beforeQuit = barFrame() else { break }
    running()?.terminate()
    let gone = waitUntilGone(timeout: 10)
    if let tile = waitForFrameChange(from: beforeQuit, timeout: 10), let gone {
        quits.append((tile - gone) * 1000)
    }
    Thread.sleep(forTimeInterval: 1.5)
}

summarise("\(unpinned) asked to launch to its tile appearing", launches)
summarise("\(unpinned) tile on screen before the app finished launching, by", headStart)
summarise("\(unpinned) gone to its tile leaving", quits)
