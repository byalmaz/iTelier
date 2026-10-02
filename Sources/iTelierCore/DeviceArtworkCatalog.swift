import Foundation

/// Resolves Apple's locally installed device artwork without treating the front
/// glass color as the enclosure finish or inventing a universal color-code map.
public struct DeviceArtworkCatalog: Sendable {
    public struct Match: Sendable {
        public let typeIdentifier: String
        public let modelName: String
        public let matchesFinish: Bool
    }
    private struct Entry: Sendable {
        let identifier: String
        let name: String
        let products: [String]
    }
    private let entries: [Entry]

    public init(data: Data) throws {
        let plist = try DeviceParser.plist(data)
        entries = (plist["UTExportedTypeDeclarations"] as? [[String: Any]] ?? []).compactMap { entry in
            guard let identifier = entry["UTTypeIdentifier"] as? String,
                  identifier.hasPrefix("com.apple."),
                  let name = entry["UTTypeDescription"] as? String,
                  let tags = entry["UTTypeTagSpecification"] as? [String: Any],
                  let codes = tags["com.apple.device-model-code"] as? [String] else { return nil }
            return Entry(identifier: identifier, name: name, products: codes)
        }
    }

    public func match(for device: DeviceSnapshot) -> Match? {
        // Exact product identity only: never choose a vaguely similar generation.
        let candidates = entries.filter { $0.products.contains(device.productType) }
        guard let first = candidates.first else { return nil }
        if let color = device.values["DeviceEnclosureColor"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !color.isEmpty, color.utf8.count <= 32,
           color.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) }) {
            let matching = candidates.filter { $0.identifier.lowercased().hasSuffix("-" + color.lowercased()) }
            if matching.count == 1, let exact = matching.first {
                return Match(typeIdentifier: exact.identifier, modelName: exact.name, matchesFinish: true)
            }
        }
        // A neutralized illustration may still show the correct hardware shape.
        return Match(typeIdentifier: first.identifier, modelName: first.name, matchesFinish: false)
    }
}
