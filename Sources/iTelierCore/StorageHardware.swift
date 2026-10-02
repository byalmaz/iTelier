import Foundation

/// Propriétés du contrôleur de stockage, sans déduire le fabricant d’un identifiant opaque.
public struct StorageHardware: Sendable {
    public let values: [String: String]
    public init(values: [String: String] = [:]) { self.values = values }
    public func text(_ key: String) -> String? {
        guard let value = values["IORegistry." + key]?.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters)),
              !value.isEmpty, value.count <= 256 else { return nil }
        return value
    }
    public func number(_ key: String) -> Int64? { text(key).flatMap(Int64.init).flatMap { $0 >= 0 ? $0 : nil } }
    public var vendor: String? { text("Controller Characteristics.vendor-name") ?? text("Vendor Name") }
    public var model: String? { text("Model Number") }
    public var firmware: String? { text("Controller Characteristics.firmware-version") ?? text("Firmware Revision") }
    public var flashName: String? { text("Controller Characteristics.nand-marketing-name") }
    public var cellType: String? {
        guard let first = flashName?.split(separator: "_").first?.uppercased(), ["SLC", "MLC", "TLC", "QLC"].contains(first) else { return nil }
        return first
    }
    public var serial: String? { DiagnosticReading.serial(text("Serial Number")) }

    /// Inventaire limité aux noms de pilotes de stockage : aucune propriété arbitraire n’est utilisée comme argument.
    static func controllerNames(_ data: Data) throws -> [String] {
        let root = try DeviceParser.plist(data)
        var names = Set<String>()
        func visit(_ value: Any) {
            if let object = value as? [String: Any] {
                if let name = object["name"] as? String,
                   name.range(of: "^Apple(ANS[A-Za-z0-9]*|EmbeddedNVMe|NAND[A-Za-z0-9]*)Controller$", options: .regularExpression) != nil {
                    names.insert(name)
                }
                for child in object.values where child is [String: Any] || child is [Any] { visit(child) }
            } else if let children = value as? [Any] { children.forEach(visit) }
        }
        visit(root)
        return Array(names.sorted().prefix(2))
    }
}
