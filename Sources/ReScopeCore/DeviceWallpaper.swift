import Foundation

public enum DeviceWallpaper {
    /// Unknown versions keep the system artwork instead of showing a wrong release.
    public static func resource(for device: DeviceSnapshot) -> String? {
        guard device.productType.hasPrefix("iPhone") || device.productType.hasPrefix("iPad"),
              let version = device.osVersion?.trimmingCharacters(in: .whitespacesAndNewlines),
              let major = Int(version.prefix(while: { $0.isNumber })), [16, 17, 18, 26].contains(major) else { return nil }
        return (device.productType.hasPrefix("iPad") ? "iPadOS" : "iOS") + String(major)
    }
}

/// Locates the connected blue screen region in macOS device illustrations.
/// The screen's black camera cutouts and the device frame stay outside the mask.
public struct DeviceScreenMask: Sendable {
    public let alpha: [UInt8]
    public let minX: Int
    public let minY: Int
    public let width: Int
    public let height: Int

    public static func detect(rgba: [UInt8], width: Int, height: Int) -> DeviceScreenMask? {
        guard (8...1024).contains(width), (8...1024).contains(height), rgba.count == width * height * 4 else { return nil }
        func blue(_ index: Int) -> Bool {
            let offset = index * 4
            let r = Int(rgba[offset]), g = Int(rgba[offset + 1]), b = Int(rgba[offset + 2])
            return rgba[offset + 3] > 240 && b > g + 15 && g > r + 25 && b > 100
        }
        let seed = (height / 2) * width + width / 2
        guard blue(seed) else { return nil }
        var alpha = [UInt8](repeating: 0, count: width * height)
        var queue = [seed], cursor = 0
        alpha[seed] = 255
        var left = width, right = 0, top = height, bottom = 0
        while cursor < queue.count {
            let index = queue[cursor]; cursor += 1
            let x = index % width, y = index / width
            left = min(left, x); right = max(right, x); top = min(top, y); bottom = max(bottom, y)
            var neighbors: [Int] = []
            if x > 0 { neighbors.append(index - 1) }
            if x + 1 < width { neighbors.append(index + 1) }
            if y > 0 { neighbors.append(index - width) }
            if y + 1 < height { neighbors.append(index + width) }
            for neighbor in neighbors where alpha[neighbor] == 0 && blue(neighbor) {
                alpha[neighbor] = 255; queue.append(neighbor)
            }
        }
        // Reject tiny camera reflections, edge-to-edge backgrounds and unexpected art.
        let fraction = Double(queue.count) / Double(width * height)
        guard fraction > 0.10, fraction < 0.85, left > 0, top > 0,
              right < width - 1, bottom < height - 1 else { return nil }
        return DeviceScreenMask(alpha: alpha, minX: left, minY: top, width: right - left + 1, height: bottom - top + 1)
    }
}
