#!/usr/bin/env swift
// Original iTelier icon, drawn with native vector paths. No third-party artwork.
import AppKit
import Foundation
import ImageIO

let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let assets = root.appendingPathComponent("assets", isDirectory: true)
try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)

func render(_ pixels: Int) throws -> Data {
    let size = CGFloat(pixels)
    guard let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                                        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: bitmap) else { fatalError("Could not create icon context") }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: size / 1024, y: size / 1024)
    let shape = NSBezierPath(roundedRect: NSRect(x: 80, y: 80, width: 864, height: 864), xRadius: 195, yRadius: 195)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.14)
    shadow.shadowBlurRadius = 23
    shadow.shadowOffset = NSSize(width: 0, height: -8)
    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor(calibratedRed: 0.81, green: 0.87, blue: 0.83, alpha: 1).setFill()
    shape.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(colors: [
        NSColor(calibratedRed: 0.83, green: 0.93, blue: 0.84, alpha: 1),
        NSColor(calibratedRed: 0.74, green: 0.66, blue: 0.90, alpha: 1)
    ])!.draw(in: shape, angle: -40)
    NSColor.white.withAlphaComponent(0.42).setStroke()
    shape.lineWidth = 3; shape.stroke()
    let ring = NSBezierPath(ovalIn: NSRect(x: 275, y: 275, width: 474, height: 474))
    NSColor(calibratedRed: 0.22, green: 0.19, blue: 0.32, alpha: 1).setStroke()
    ring.lineWidth = 53; ring.stroke()
    let lens = NSBezierPath(ovalIn: NSRect(x: 396, y: 396, width: 232, height: 232))
    NSColor.white.withAlphaComponent(0.52).setFill(); lens.fill()
    let brackets = NSBezierPath()
    for (x, y, sx, sy) in [(228.0, 228.0, 1.0, 1.0), (796.0, 228.0, -1.0, 1.0),
                            (228.0, 796.0, 1.0, -1.0), (796.0, 796.0, -1.0, -1.0)] {
        brackets.move(to: NSPoint(x: x + sx * 65, y: y))
        brackets.line(to: NSPoint(x: x, y: y))
        brackets.line(to: NSPoint(x: x, y: y + sy * 65))
    }
    brackets.lineCapStyle = .round; brackets.lineJoinStyle = .round; brackets.lineWidth = 26
    brackets.stroke()
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

func appendUInt32(_ value: UInt32, to data: inout Data) {
    var bigEndian = value.bigEndian
    withUnsafeBytes(of: &bigEndian) { data.append(contentsOf: $0) }
}

func appendElement(_ type: String, payload: Data, to data: inout Data) {
    precondition(type.utf8.count == 4 && payload.count < Int(UInt32.max) - 8)
    data.append(contentsOf: type.utf8)
    appendUInt32(UInt32(payload.count + 8), to: &data)
    data.append(payload)
}

// ICNS RGB channels use a PackBits-like stream. Literal packets avoid compression
// dependencies and preserve the original 16px/32px colours exactly.
func literalPackets(_ channel: [UInt8]) -> Data {
    var data = Data()
    for offset in stride(from: 0, to: channel.count, by: 128) {
        let end = min(offset + 128, channel.count)
        data.append(UInt8(end - offset - 1))
        data.append(contentsOf: channel[offset..<end])
    }
    return data
}

func legacyRGBAndMask(_ png: Data, pixels: Int) -> (rgb: Data, mask: Data) {
    guard let bitmap = NSBitmapImageRep(data: png) else { fatalError("Could not decode rendered PNG") }
    var red = [UInt8](), green = [UInt8](), blue = [UInt8](), mask = Data()
    for y in 0..<pixels {
        for x in 0..<pixels {
            guard let colour = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else {
                fatalError("Could not read icon colour")
            }
            func byte(_ component: CGFloat) -> UInt8 {
                UInt8((min(1, max(0, component)) * 255).rounded())
            }
            red.append(byte(colour.redComponent))
            green.append(byte(colour.greenComponent))
            blue.append(byte(colour.blueComponent))
            mask.append(byte(colour.alphaComponent))
        }
    }
    return (literalPackets(red) + literalPackets(green) + literalPackets(blue), mask)
}

// The container header and element sizes are big-endian (IconStorage.h).
// Larger and Retina representations contain native PNG data. The two legacy
// small representations use RGB + alpha masks for macOS Icon Services.
var images = [Int: Data]()
for pixels in [16, 32, 64, 128, 256, 512, 1024] { images[pixels] = try render(pixels) }
var elements = Data()
for (pixels, rgbType, maskType) in [(16, "is32", "s8mk"), (32, "il32", "l8mk")] {
    let channels = legacyRGBAndMask(images[pixels]!, pixels: pixels)
    appendElement(rgbType, payload: channels.rgb, to: &elements)
    appendElement(maskType, payload: channels.mask, to: &elements)
}
for (type, pixels) in [("ic07", 128), ("ic08", 256), ("ic09", 512), ("ic10", 1024),
                       ("ic11", 32), ("ic12", 64), ("ic13", 256), ("ic14", 512)] {
    appendElement(type, payload: images[pixels]!, to: &elements)
}
var icon = Data("icns".utf8)
appendUInt32(UInt32(elements.count + 8), to: &icon)
icon.append(elements)
let iconURL = assets.appendingPathComponent("AppIcon.icns")
try icon.write(to: iconURL, options: .atomic)
try images[512]!.write(to: assets.appendingPathComponent("AppIcon.png"), options: .atomic)

// Verify with the same native decoder used by macOS, without depending on
// iconutil being able to create an ICNS file on the installed SDK.
guard let source = CGImageSourceCreateWithURL(iconURL as CFURL, nil),
      CGImageSourceGetCount(source) >= 7 else { fatalError("Generated ICNS could not be decoded") }
var decodedSizes = Set<Int>()
for index in 0..<CGImageSourceGetCount(source) {
    guard let image = CGImageSourceCreateImageAtIndex(source, index, nil), image.width == image.height else {
        fatalError("Invalid ICNS representation")
    }
    decodedSizes.insert(image.width)
}
guard decodedSizes == Set([16, 32, 64, 128, 256, 512, 1024]) else {
    fatalError("Missing ICNS sizes: \(decodedSizes.sorted())")
}
print("Generated assets/AppIcon.icns and assets/AppIcon.png")
print("Native ICNS decoder verified sizes: \(decodedSizes.sorted())")
