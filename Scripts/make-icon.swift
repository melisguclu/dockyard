#!/usr/bin/env swift

import AppKit
import CoreGraphics
import Foundation

let output = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : FileManager.default.currentDirectoryPath + "/build/Dockyard.iconset"

try? FileManager.default.createDirectory(
    at: URL(fileURLWithPath: output),
    withIntermediateDirectories: true
)

func draw(size: Int) -> Data? {
    let dimension = CGFloat(size)
    guard let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
            | CGBitmapInfo.byteOrder32Little.rawValue
    ) else { return nil }

    let inset = dimension * 0.06
    let plate = CGRect(x: inset, y: inset, width: dimension - 2 * inset, height: dimension - 2 * inset)
    let plateRadius = plate.width * 0.235

    let gradientColors = [
        CGColor(red: 0.16, green: 0.18, blue: 0.26, alpha: 1),
        CGColor(red: 0.05, green: 0.06, blue: 0.10, alpha: 1)
    ] as CFArray
    guard let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: gradientColors,
        locations: [0, 1]
    ) else { return nil }

    context.saveGState()
    context.addPath(CGPath(roundedRect: plate, cornerWidth: plateRadius, cornerHeight: plateRadius, transform: nil))
    context.clip()
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: plate.minX, y: plate.maxY),
        end: CGPoint(x: plate.maxX, y: plate.minY),
        options: []
    )
    context.restoreGState()

    func screen(_ rect: CGRect, fill: CGColor, bar: CGColor) {
        let radius = rect.height * 0.14
        context.setFillColor(fill)
        context.addPath(CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil))
        context.fillPath()

        let barHeight = rect.height * 0.17
        let barRect = CGRect(
            x: rect.minX + rect.width * 0.13,
            y: rect.minY + rect.height * 0.10,
            width: rect.width * 0.74,
            height: barHeight
        )
        context.setFillColor(bar)
        context.addPath(
            CGPath(
                roundedRect: barRect,
                cornerWidth: barHeight / 2,
                cornerHeight: barHeight / 2,
                transform: nil
            )
        )
        context.fillPath()
    }

    let back = CGRect(
        x: plate.minX + plate.width * 0.30,
        y: plate.minY + plate.height * 0.34,
        width: plate.width * 0.56,
        height: plate.height * 0.40
    )
    let front = CGRect(
        x: plate.minX + plate.width * 0.11,
        y: plate.minY + plate.height * 0.20,
        width: plate.width * 0.52,
        height: plate.height * 0.37
    )

    screen(
        back,
        fill: CGColor(red: 0.36, green: 0.42, blue: 0.58, alpha: 1),
        bar: CGColor(red: 0.85, green: 0.90, blue: 1.0, alpha: 0.9)
    )
    screen(
        front,
        fill: CGColor(red: 0.62, green: 0.74, blue: 0.98, alpha: 1),
        bar: CGColor(red: 0.10, green: 0.12, blue: 0.20, alpha: 0.85)
    )

    guard let image = context.makeImage() else { return nil }
    let representation = NSBitmapImageRep(cgImage: image)
    representation.size = NSSize(width: dimension, height: dimension)
    return representation.representation(using: .png, properties: [:])
}

let variants: [(Int, String)] = [
    (16, "icon_16x16.png"),
    (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"),
    (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"),
    (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"),
    (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"),
    (1024, "icon_512x512@2x.png")
]

for (size, name) in variants {
    guard let data = draw(size: size) else {
        print("failed to render \(name)")
        exit(1)
    }
    try data.write(to: URL(fileURLWithPath: output).appendingPathComponent(name))
}

print("wrote \(variants.count) images to \(output)")
