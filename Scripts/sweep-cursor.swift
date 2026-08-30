#!/usr/bin/env swift

import AppKit
import CoreGraphics
import Foundation

let seconds = Double(CommandLine.arguments.dropFirst().first ?? "30") ?? 30
let speed = Double(CommandLine.arguments.dropFirst(2).first ?? "500") ?? 500

func barWindow() -> CGRect? {
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

guard let bar = barWindow() else {
    FileHandle.standardError.write(Data("No Dockyard bar is on screen. Launch it first.\n".utf8))
    exit(1)
}

let y = bar.midY
let inset = bar.height
let x0 = bar.minX + inset
let x1 = bar.maxX - inset
let span = x1 - x0
FileHandle.standardError.write(Data("Sweeping \(Int(span)) pt at \(Int(speed)) pt/s for \(seconds) s\n".utf8))

let resting = CGEvent(source: nil)?.location
let start = CFAbsoluteTimeGetCurrent()

while true {
    let elapsed = CFAbsoluteTimeGetCurrent() - start
    guard elapsed < seconds else { break }
    let travelled = elapsed * speed
    let cycle = travelled.truncatingRemainder(dividingBy: span * 2)
    let x = cycle < span ? x0 + cycle : x1 - (cycle - span)
    CGEvent(
        mouseEventSource: nil,
        mouseType: .mouseMoved,
        mouseCursorPosition: CGPoint(x: x, y: y),
        mouseButton: .left
    )?.post(tap: .cghidEventTap)
    usleep(2000)
}

if let resting {
    CGEvent(
        mouseEventSource: nil,
        mouseType: .mouseMoved,
        mouseCursorPosition: resting,
        mouseButton: .left
    )?.post(tap: .cghidEventTap)
}
