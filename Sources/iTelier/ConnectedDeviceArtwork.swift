import AppKit
import SwiftUI
import UniformTypeIdentifiers
import iTelierCore

@MainActor
enum SystemDeviceArtwork {
    private static let catalog: DeviceArtworkCatalog? = {
        let path = "/System/Library/CoreServices/CoreTypes.bundle/Contents/Library/MobileDevices.bundle/Contents/Resources/MobileDevices-Info.plist"
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: path)) else { return nil }
        return try? DeviceArtworkCatalog(data: data)
    }()
    private static let images = NSCache<NSString, NSImage>()
    private static let screens = NSCache<NSString, Screen>()

    final class Screen: NSObject {
        let mask: NSImage
        let bounds: CGRect
        init(mask: NSImage, bounds: CGRect) { self.mask = mask; self.bounds = bounds }
    }

    static func match(_ device: DeviceSnapshot?) -> DeviceArtworkCatalog.Match? {
        guard let device else { return nil }
        return catalog?.match(for: device)
    }

    static func image(_ match: DeviceArtworkCatalog.Match) -> NSImage? {
        let key = match.typeIdentifier as NSString
        if let cached = images.object(forKey: key) { return cached }
        guard let type = UTType(match.typeIdentifier) else { return nil }
        let image = NSWorkspace.shared.icon(for: type)
        image.size = NSSize(width: 512, height: 512)
        images.setObject(image, forKey: key)
        return image
    }

    static func screen(_ match: DeviceArtworkCatalog.Match, image: NSImage) -> Screen? {
        let key = match.typeIdentifier as NSString
        if let cached = screens.object(forKey: key) { return cached }
        let size = 512
        var rect = CGRect(x: 0, y: 0, width: size, height: size)
        guard let source = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else { return nil }
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        let rendered = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: size, height: size, bitsPerComponent: 8,
                                          bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.draw(source, in: CGRect(x: 0, y: 0, width: size, height: size))
            return true
        }
        guard rendered, let detected = DeviceScreenMask.detect(rgba: pixels, width: size, height: size) else { return nil }
        var maskPixels = [UInt8](repeating: 0, count: size * size * 4)
        for index in detected.alpha.indices where detected.alpha[index] > 0 {
            for channel in 0..<4 { maskPixels[index * 4 + channel] = 255 }
        }
        guard let provider = CGDataProvider(data: Data(maskPixels) as CFData),
              let cgMask = CGImage(width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32,
                                   bytesPerRow: size * 4, space: CGColorSpaceCreateDeviceRGB(),
                                   bitmapInfo: CGBitmapInfo(rawValue: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue),
                                   provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return nil }
        let result = Screen(mask: NSImage(cgImage: cgMask, size: NSSize(width: size, height: size)),
                            bounds: CGRect(x: Double(detected.minX) / Double(size), y: Double(detected.minY) / Double(size),
                                           width: Double(detected.width) / Double(size), height: Double(detected.height) / Double(size)))
        screens.setObject(result, forKey: key)
        return result
    }
}

@MainActor
enum BundledWallpapers {
    private static let images = NSCache<NSString, NSImage>()
    static func image(for device: DeviceSnapshot?) -> NSImage? {
        guard let device, let name = DeviceWallpaper.resource(for: device) else { return nil }
        if let cached = images.object(forKey: name as NSString) { return cached }
        let extensions = ["jpg", "png", "heic"]
        // SwiftPM flattens processed resource directories in the signed app bundle.
        let resources = Bundle.main.resourceURL?.appendingPathComponent("iTelier_iTelier.bundle")
        let bundle = resources.flatMap(Bundle.init(url:))
        var url = extensions.compactMap { bundle?.url(forResource: name, withExtension: $0) }.first
        if url == nil, Bundle.main.bundleURL.pathExtension != "app" {
            url = extensions.compactMap { Bundle.module.url(forResource: name, withExtension: $0) }.first
        }
        guard let url, let image = NSImage(contentsOf: url) else { return nil }
        images.setObject(image, forKey: name as NSString)
        return image
    }
}

struct ConnectedDeviceArtwork: View {
    @EnvironmentObject private var model: AppModel
    let device: DeviceSnapshot?
    @ViewState private var personalWallpaper: NSImage?
    private var wallpaperData: Data? { device.flatMap { model.deviceWallpapers[$0.id] } }
    var body: some View {
        Group {
            if let match = SystemDeviceArtwork.match(device), let image = SystemDeviceArtwork.image(match),
               let screen = SystemDeviceArtwork.screen(match, image: image) {
                GeometryReader { geometry in
                    let side = min(geometry.size.width, geometry.size.height)
                    ZStack(alignment: .topLeading) {
                        Image(nsImage: image).resizable().interpolation(.high)
                            .saturation(match.matchesFinish ? 1 : 0)
                            .frame(width: side, height: side)
                        Group {
                            let width = screen.bounds.width * side
                            let height = screen.bounds.height * side
                            ZStack(alignment: .top) {
                                if let wallpaper = personalWallpaper ?? (model.isDemo ? BundledWallpapers.image(for: device) : nil) {
                                    Image(nsImage: wallpaper).resizable().interpolation(.high).scaledToFill()
                                        .frame(width: width, height: height).clipped()
                                } else {
                                    LinearGradient(colors: [Color(white: 0.14), Color(white: 0.04)], startPoint: .top, endPoint: .bottom)
                                }
                            }.frame(width: width, height: height).clipped()
                                .offset(x: screen.bounds.minX * side, y: screen.bounds.minY * side)
                                .frame(width: side, height: side, alignment: .topLeading)
                                .mask(Image(nsImage: screen.mask).resizable().frame(width: side, height: side))
                        }
                    }.frame(width: side, height: side)
                        .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                }
                    .shadow(color: .black.opacity(0.28), radius: 12, y: 10)
                    .help(personalWallpaper != nil
                          ? L("Aperçu de l’écran verrouillé fourni par l’appareil. L’heure et la date sont celles de cet aperçu.")
                          : L("Illustration du modèle · fond personnel indisponible par USB pour le moment."))
            } else if let personalWallpaper {
                Image(nsImage: personalWallpaper).resizable().interpolation(.high).scaledToFit()
                    .clipShape(RoundedRectangle(cornerRadius: 18))
                    .overlay(RoundedRectangle(cornerRadius: 18).stroke(Palette.line, lineWidth: 2))
                    .help(L("Aperçu de l’écran verrouillé fourni par l’appareil. L’heure et la date sont celles de cet aperçu."))
            } else if device == nil {
                GeometryReader { geometry in
                    GlassIcon(systemName: "iphone.gen3", size: min(geometry.size.width, geometry.size.height) * 0.68,
                              color: Palette.violet, phoneDuo: true)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            } else {
                Image(systemName: device?.symbolName ?? "iphone")
                    .resizable().scaledToFit().padding(28)
                    .foregroundStyle(Palette.secondary)
                    .help(L("Illustration générique : modèle ou finition non disponible sur ce Mac."))
            }
        }.accessibilityHidden(true)
            .onAppear { personalWallpaper = wallpaperData.flatMap(NSImage.init(data:)) }
            .onChange(of: wallpaperData) { data in personalWallpaper = data.flatMap(NSImage.init(data:)) }
    }
}
