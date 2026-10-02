import Foundation
import CryptoKit

public enum ReferenceOrigin: String, Codable, Sendable {
    case recordedCheck, importedReport
    public var title: String { self == .recordedCheck ? L("Check enregistré sur ce Mac") : L("Rapport iTelier importé") }
}

public struct ReferenceValue: Codable, Sendable {
    public let id: String
    public let value: String
    public let source: String?
}

/// A dated observation, never a claim of factory authenticity.
public struct CheckReference: Codable, Sendable {
    public let schemaVersion: Int
    public let productType: String
    public let ecid: String
    public let demo: Bool
    public let date: Date
    public let origin: ReferenceOrigin
    public let values: [ReferenceValue]

    // Volatile measurements and manual checks are deliberately not treated as component references.
    public static let comparableIDs: Set<String> = [
        "model", "hardware", "serial", "ecid", "model-number", "region", "color", "storage",
        "battery-serial", "logic-board-serial", "front-camera-serial", "rear-camera-serial",
        "ultrawide-camera-serial", "telephoto-camera-serial", "screen-serial", "screen-module-serial",
        "coverglass-serial", "ir-camera-serial", "projector-serial", "lidar-serial", "ambient-light-serial",
        "wifi", "bluetooth", "imei"
    ]

    public static func capture(_ report: DiagnosticReport, demo: Bool) throws -> Self {
        guard let ecid = DeviceParser.normalizedECID(report.device.ecid) else { throw ReferenceError.identityMissing }
        let values = report.items.compactMap { item -> ReferenceValue? in
            guard comparableIDs.contains(item.id), [.read, .verified].contains(item.status), let value = validValue(item.actual) else { return nil }
            return ReferenceValue(id: item.id, value: value, source: item.source)
        }
        let result = Self(schemaVersion: 1, productType: report.device.productType, ecid: ecid,
                          demo: demo, date: report.date, origin: .recordedCheck, values: values)
        try result.validate(for: report.device, demo: demo)
        return result
    }

    public static func importReport(_ data: Data, for report: DiagnosticReport, demo: Bool) throws -> Self {
        guard data.count <= 1_048_576,
              let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              LegacyAppMigration.acceptsReportApplication(json["application"] as? String ?? ""),
              let schema = json["schemaVersion"] as? Int, [2, 3].contains(schema),
              let importedDemo = json["demo"] as? Bool,
              let device = json["device"] as? [String: Any],
              let product = device["productType"] as? String,
              let dateString = json["date"] as? String,
              let date = ISO8601DateFormatter().date(from: dateString),
              let rows = json["checks"] as? [[String: Any]], rows.count <= 200 else { throw ReferenceError.invalidFile }
        guard json["identifiersIncluded"] as? Bool == true,
              let ecid = DeviceParser.normalizedECID(device["ecid"] as? String) else { throw ReferenceError.redacted }
        var values: [ReferenceValue] = []
        var seen = Set<String>()
        for row in rows {
            // Version 2 used French titles; version 3 exports stable IDs.
            let id = schema == 3 ? row["id"] as? String
                : report.items.first(where: { $0.title == row["element"] as? String })?.id
            guard let id, comparableIDs.contains(id) else { continue }
            guard seen.insert(id).inserted else { throw ReferenceError.invalidFile }
            guard ["read", "verified"].contains(row["status"] as? String ?? ""),
                  let value = validValue(row["value"] as? String) else { continue }
            let source = (row["source"] as? String).flatMap { $0.count <= 512 ? $0 : nil }
            values.append(ReferenceValue(id: id, value: value, source: source))
        }
        let reference = Self(schemaVersion: 1, productType: product, ecid: ecid, demo: importedDemo,
                             date: date, origin: .importedReport, values: values)
        try reference.validate(for: report.device, demo: demo)
        return reference
    }

    public func validate(for device: DeviceSnapshot, demo expectedDemo: Bool) throws {
        guard schemaVersion == 1, values.count <= 100, !values.isEmpty,
              date.timeIntervalSince1970.isFinite, date.timeIntervalSince1970 > 0,
              Set(values.map(\.id)).count == values.count,
              values.allSatisfy({ Self.comparableIDs.contains($0.id) && Self.validValue($0.value) != nil && ($0.source?.count ?? 0) <= 512 }) else {
            throw ReferenceError.invalidFile
        }
        guard demo == expectedDemo, productType == device.productType,
              let target = DeviceParser.normalizedECID(device.ecid), target == ecid else { throw ReferenceError.wrongDevice }
        if let row = values.first(where: { $0.id == "ecid" }), DeviceParser.normalizedECID(row.value) != ecid { throw ReferenceError.invalidFile }
        if let row = values.first(where: { $0.id == "model" }), row.value != productType { throw ReferenceError.invalidFile }
    }

    public func applying(to report: DiagnosticReport, demo: Bool) throws -> DiagnosticReport {
        try validate(for: report.device, demo: demo)
        let indexed = Dictionary(uniqueKeysWithValues: values.map { ($0.id, $0) })
        let items = report.items.map { item -> CheckItem in
            guard let reference = indexed[item.id] else { return item }
            let match: ReferenceMatch
            if item.actual == nil || ![.read, .verified].contains(item.status) { match = .unreadable }
            else if origin == .recordedCheck && abs(report.date.timeIntervalSince(date)) < 0.001 { match = .initial }
            else { match = Self.comparisonValue(item.actual!, id: item.id) == Self.comparisonValue(reference.value, id: item.id) ? .same : .different }
            let explanation = match == .different
                ? L("La valeur diffère du relevé de référence. Un écart ne prouve ni un remplacement ni une contrefaçon.")
                : match == .same ? L("La valeur est identique au relevé de référence ; cela ne certifie pas son origine.")
                : match == .initial ? L("Ce contrôle est le relevé initial. Relancez le Check pour effectuer une nouvelle comparaison.")
                : L("La lecture actuelle ne permet pas de comparer cette valeur.")
            return CheckItem(id: item.id, title: item.title, category: item.category, expected: reference.value,
                             actual: item.actual, status: item.status, detail: item.detail + "\n\n" + explanation,
                             sensitive: item.sensitive || ["serial", "ecid", "imei", "wifi", "bluetooth"].contains(item.id) || item.id.hasSuffix("-serial"),
                             source: item.source, referenceMatch: match)
        }
        return DiagnosticReport(date: report.date, device: report.device, items: items, sources: report.sources)
    }

    private static func comparisonValue(_ value: String, id: String) -> String {
        if id == "ecid" { return DeviceParser.normalizedECID(value) ?? value }
        if ["wifi", "bluetooth", "hardware"].contains(id) { return value.lowercased() }
        return value
    }

    private static func validValue(_ value: String?) -> String? {
        guard let value, !value.isEmpty, value.count <= 4096,
              !["masqué", "indisponible", "unknown", "n/a", "non exposé"].contains(value.lowercased()),
              !value.contains("•"), value.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }) else { return nil }
        return value
    }
}

public enum ReferenceError: LocalizedError {
    case identityMissing, invalidFile, redacted, wrongDevice
    public var errorDescription: String? {
        switch self {
        case .identityMissing: return L("L’ECID de l’appareil est nécessaire pour lui associer une référence.")
        case .invalidFile: return L("Ce fichier ne contient pas de référence iTelier valide et exploitable.")
        case .redacted: return L("Ce rapport est masqué. Exportez-le avec « Afficher les numéros de série » activé pour pouvoir le comparer.")
        case .wrongDevice: return L("Cette référence appartient à un autre appareil ou à un exemple. Elle n’a pas été appliquée.")
        }
    }
}

public struct CheckReferenceStore {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }

    public func load(for device: DeviceSnapshot, demo: Bool) throws -> CheckReference? {
        let file = try url(for: device, demo: demo)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
        guard let size = attributes[.size] as? NSNumber, size.intValue <= 1_048_576 else { throw ReferenceError.invalidFile }
        let value = try JSONDecoder().decode(CheckReference.self, from: Data(contentsOf: file))
        try value.validate(for: device, demo: demo)
        return value
    }

    public func save(_ reference: CheckReference, for device: DeviceSnapshot, demo: Bool) throws {
        try reference.validate(for: device, demo: demo)
        let file = try url(for: device, demo: demo)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        // Keep the previous observation when the user explicitly replaces a reference.
        if FileManager.default.fileExists(atPath: file.path) {
            let previous = try Data(contentsOf: file)
            let backup = file.deletingPathExtension().appendingPathExtension("previous.json")
            try previous.write(to: backup, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path)
        }
        try JSONEncoder().encode(reference).write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
    }

    private func url(for device: DeviceSnapshot, demo: Bool) throws -> URL {
        guard let ecid = DeviceParser.normalizedECID(device.ecid) else { throw ReferenceError.identityMissing }
        let key = "\(demo ? "demo" : "device"):\(device.productType):\(ecid)"
        let hash = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(hash + ".json")
    }
}
