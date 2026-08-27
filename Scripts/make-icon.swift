#!/usr/bin/env swift

import AppKit
import CoreGraphics
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconsetPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : root.appendingPathComponent("build/Dockyard.iconset").path

try? FileManager.default.createDirectory(
    at: URL(fileURLWithPath: iconsetPath),
    withIntermediateDirectories: true
)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        red: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

let plateTop: UInt32 = 0xFDFDFE
let plateBottom: UInt32 = 0xD6DAE1
let screenTop: UInt32 = 0x333A48
let screenBottom: UInt32 = 0x141821
let distantScreenTop: UInt32 = 0x4A5266
let distantScreenBottom: UInt32 = 0x252B38
let dockTop: UInt32 = 0xFFFFFF
let dockBottom: UInt32 = 0xDDE2EA
let tileTints: [UInt32] = [0x5B8CFF, 0x3FD6B0, 0xFFA04A, 0xFF6B8A, 0x9B8CFF, 0x67D2FF]

func squircle(_ rect: CGRect, exponent: CGFloat = 5) -> CGPath {
    let path = CGMutablePath()
    let halfWidth = rect.width / 2
    let halfHeight = rect.height / 2
    let steps = 512
    for step in 0...steps {
        let angle = CGFloat(step) / CGFloat(steps) * 2 * .pi
        let cosine = cos(angle)
        let sine = sin(angle)
        let x = rect.midX + halfWidth * (cosine < 0 ? -1 : 1) * pow(abs(cosine), 2 / exponent)
        let y = rect.midY + halfHeight * (sine < 0 ? -1 : 1) * pow(abs(sine), 2 / exponent)
        if step == 0 {
            path.move(to: CGPoint(x: x, y: y))
        } else {
            path.addLine(to: CGPoint(x: x, y: y))
        }
    }
    path.closeSubpath()
    return path
}

func rounded(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(
        roundedRect: rect,
        cornerWidth: min(radius, rect.width / 2),
        cornerHeight: min(radius, rect.height / 2),
        transform: nil
    )
}

func fillVertical(_ context: CGContext, _ path: CGPath, _ top: CGColor, _ bottom: CGColor, in rect: CGRect) {
    guard let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [top, bottom] as CFArray,
        locations: [0, 1]
    ) else { return }
    context.saveGState()
    context.addPath(path)
    context.clip()
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: rect.midX, y: rect.maxY),
        end: CGPoint(x: rect.midX, y: rect.minY),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )
    context.restoreGState()
}

func fillRadial(_ context: CGContext, clip: CGPath, center: CGPoint, radius: CGFloat, _ tint: CGColor, _ fade: CGColor) {
    guard let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [tint, fade] as CFArray,
        locations: [0, 1]
    ) else { return }
    context.saveGState()
    context.addPath(clip)
    context.clip()
    context.drawRadialGradient(
        gradient,
        startCenter: center,
        startRadius: 0,
        endCenter: center,
        endRadius: radius,
        options: [.drawsAfterEndLocation]
    )
    context.restoreGState()
}

func drawPlate(_ context: CGContext, dimension: CGFloat) -> CGRect {
    let inset = dimension * 0.088
    let rect = CGRect(x: inset, y: inset, width: dimension - 2 * inset, height: dimension - 2 * inset)
    let path = squircle(rect)

    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -dimension * 0.012),
        blur: dimension * 0.035,
        color: color(0x000000, 0.30)
    )
    context.addPath(path)
    context.setFillColor(color(plateBottom))
    context.fillPath()
    context.restoreGState()

    fillVertical(context, path, color(plateTop), color(plateBottom), in: rect)

    context.saveGState()
    context.addPath(path)
    context.clip()
    context.setLineWidth(dimension * 0.006)
    context.setStrokeColor(color(0x000000, 0.06))
    context.addPath(squircle(rect.insetBy(dx: dimension * 0.003, dy: dimension * 0.003)))
    context.strokePath()
    context.restoreGState()

    return rect
}

func drawDock(_ context: CGContext, _ rect: CGRect, tiles: Int, firstTint: Int) {
    let radius = rect.height * 0.30
    let path = rounded(rect, radius)

    context.saveGState()
    context.setShadow(offset: .zero, blur: rect.height * 0.55, color: color(0xFFFFFF, 0.55))
    context.addPath(path)
    context.setFillColor(color(dockBottom))
    context.fillPath()
    context.restoreGState()

    fillVertical(context, path, color(dockTop), color(dockBottom), in: rect)

    if tiles > 0 {
        let padding = rect.height * 0.185
        let inner = rect.insetBy(dx: padding * 1.5, dy: padding)
        let side = inner.height
        let gap = (inner.width - CGFloat(tiles) * side) / CGFloat(max(tiles - 1, 1))
        for index in 0..<tiles {
            let tile = CGRect(
                x: inner.minX + CGFloat(index) * (side + gap),
                y: inner.minY,
                width: side,
                height: side
            )
            let tint = tileTints[(index + firstTint) % tileTints.count]
            fillVertical(context, rounded(tile, side * 0.30), color(tint, 0.97), color(tint, 0.66), in: tile)
        }
    }

    context.saveGState()
    context.addPath(path)
    context.clip()
    context.setLineWidth(rect.height * 0.055)
    context.setStrokeColor(color(0xFFFFFF, 0.50))
    context.addPath(rounded(rect.insetBy(dx: rect.height * 0.028, dy: rect.height * 0.028), radius))
    context.strokePath()
    context.restoreGState()
}

func drawScreen(
    _ context: CGContext,
    _ rect: CGRect,
    plateWidth: CGFloat,
    tiles: Int,
    firstTint: Int,
    distant: Bool
) {
    let radius = plateWidth * 0.045
    let path = rounded(rect, radius)
    let top = distant ? distantScreenTop : screenTop
    let bottom = distant ? distantScreenBottom : screenBottom

    context.saveGState()
    context.setShadow(
        offset: CGSize(width: -rect.height * 0.03, height: -rect.height * 0.05),
        blur: rect.height * (distant ? 0.16 : 0.22),
        color: color(0x000000, distant ? 0.28 : 0.42)
    )
    context.addPath(path)
    context.setFillColor(color(bottom))
    context.fillPath()
    context.restoreGState()

    fillVertical(context, path, color(top), color(bottom), in: rect)

    context.saveGState()
    context.addPath(path)
    context.clip()
    context.setLineWidth(plateWidth * 0.008)
    context.setStrokeColor(color(0xFFFFFF, distant ? 0.16 : 0.24))
    context.addPath(rounded(rect.insetBy(dx: plateWidth * 0.004, dy: plateWidth * 0.004), radius))
    context.strokePath()

    fillRadial(
        context,
        clip: path,
        center: CGPoint(x: rect.midX, y: rect.maxY - rect.height * 0.12),
        radius: rect.width * 0.85,
        color(0xFFFFFF, 0.14),
        color(0xFFFFFF, 0)
    )

    let bar = CGRect(
        x: rect.minX + rect.width * 0.075,
        y: rect.minY + rect.height * 0.075,
        width: rect.width * 0.85,
        height: rect.height * 0.275
    )
    drawDock(context, bar, tiles: tiles, firstTint: firstTint)
    context.restoreGState()
}

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

    context.setAllowsAntialiasing(true)
    context.interpolationQuality = .high

    let plate = drawPlate(context, dimension: dimension)
    let width = plate.width
    let height = plate.height

    context.saveGState()
    context.addPath(squircle(plate))
    context.clip()

    let external = CGRect(
        x: plate.minX + width * 0.370,
        y: plate.minY + height * 0.420,
        width: width * 0.550,
        height: height * 0.410
    )
    let builtIn = CGRect(
        x: plate.minX + width * 0.052,
        y: plate.minY + height * 0.140,
        width: width * 0.468,
        height: height * 0.375
    )

    let resolvesTiles = size >= 48
    drawScreen(context, external, plateWidth: width, tiles: resolvesTiles ? 4 : 0, firstTint: 2, distant: true)
    drawScreen(context, builtIn, plateWidth: width, tiles: resolvesTiles ? 3 : 0, firstTint: 0, distant: false)

    context.restoreGState()

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
    try data.write(to: URL(fileURLWithPath: iconsetPath).appendingPathComponent(name))
}

print("wrote \(variants.count) images to \(iconsetPath)")

let bundleIcon = root.appendingPathComponent("Dockyard/Resources/AppIcon.icns")
if FileManager.default.fileExists(atPath: bundleIcon.deletingLastPathComponent().path) {
    let convert = Process()
    convert.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    convert.arguments = ["--convert", "icns", iconsetPath, "--output", bundleIcon.path]
    try convert.run()
    convert.waitUntilExit()
    if convert.terminationStatus == 0 {
        print("wrote \(bundleIcon.path)")
    } else {
        print("iconutil failed with status \(convert.terminationStatus)")
        exit(1)
    }
}
