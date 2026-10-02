import Foundation
import CryptoKit

public struct LocalBackup: Identifiable, Sendable {
    public var id: String { directory.path }
    public let directory: URL
    public let name: String
    public let productType: String
    public let version: String
    public let date: Date?
    public let encrypted: Bool
    public let complete: Bool
    public let fingerprint: String
    public var source: String { directory.lastPathComponent }

    public static func read(_ directory: URL) throws -> LocalBackup {
        let directory = directory.standardizedFileURL
        guard directory == directory.resolvingSymlinksInPath(),
              directory.lastPathComponent.range(of: "^[a-zA-Z0-9-]{1,100}$", options: .regularExpression) != nil else {
            throw BackupError.invalid(L("Le dossier de sauvegarde n’est pas valide ou contient un lien symbolique."))
        }
        var bytes = Data()
        func plist(_ name: String) throws -> [String: Any] {
            let url = directory.appendingPathComponent(name)
            guard url == url.resolvingSymlinksInPath() else { throw BackupError.invalid(L("Les métadonnées ne peuvent pas être des liens symboliques.")) }
            let data = try RestoreHost.readBounded(url, limit: 16 * 1_024 * 1_024)
            bytes.append(data)
            guard let object = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
                throw BackupError.invalid(L("Métadonnées de sauvegarde illisibles."))
            }
            return object
        }
        let info = try plist("Info.plist"), manifest = try plist("Manifest.plist"), status = try plist("Status.plist")
        guard let product = info["Product Type"] as? String, product.hasPrefix("iPhone") || product.hasPrefix("iPad"),
              let version = info["Product Version"] as? String,
              let encryption = manifest["IsEncrypted"] as? Bool else {
            throw BackupError.invalid(L("La sauvegarde ne contient pas les informations nécessaires."))
        }
        let db = directory.appendingPathComponent("Manifest.db")
        let database = try? db.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey])
        let hasDatabase = db == db.resolvingSymlinksInPath() && database?.isRegularFile == true && (database?.fileSize ?? 0) > 0
        bytes.append(Data("\(database?.fileSize ?? 0):\(database?.contentModificationDate?.timeIntervalSince1970 ?? 0)".utf8))
        let marker = directory.deletingLastPathComponent().appendingPathComponent("rescope-incomplete")
        return LocalBackup(directory: directory, name: String((info["Device Name"] as? String ?? product).prefix(120)),
            productType: product, version: version, date: info["Last Backup Date"] as? Date ?? status["Date"] as? Date,
            encrypted: encryption, complete: status["SnapshotState"] as? String == "finished" && hasDatabase && !FileManager.default.fileExists(atPath: marker.path),
            fingerprint: SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined())
    }

    public func restorationIssue(for device: DeviceSnapshot?) -> String? {
        guard complete else { return L("Cette sauvegarde est incomplète. Elle ne peut pas être restaurée.") }
        guard let device, device.mode == .normal else { return L("Connectez et déverrouillez l’appareil en mode normal.") }
        guard productType.hasPrefix("iPad") == device.productType.hasPrefix("iPad") else { return L("Choisissez une sauvegarde de la même famille d’appareils.") }
        guard let current = device.osVersion, let target = Self.versionParts(current), let source = Self.versionParts(version) else {
            return L("La version du système n’est pas vérifiable.")
        }
        guard !target.lexicographicallyPrecedes(source) else { return L("Installez iOS/iPadOS \(version) ou une version plus récente sur l’appareil.") }
        return nil
    }
    static func versionParts(_ value: String) -> [Int]? {
        guard value.range(of: "^[0-9]+(\\.[0-9]+){0,2}$", options: .regularExpression) != nil else { return nil }
        let values = value.split(separator: ".").compactMap { Int($0) }
        return values + Array(repeating: 0, count: 3 - values.count)
    }
}

public enum BackupError: LocalizedError {
    case invalid(String)
    public var errorDescription: String? { if case let .invalid(message) = self { return message }; return nil }
}

public enum BackupLibrary {
    public static var defaultDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("ReScope/Backups", isDirectory: true)
    }
    /// Only the root, direct Apple backup folders and one ReScope session level are inspected.
    public static func scan(_ root: URL) throws -> [LocalBackup] {
        if !FileManager.default.fileExists(atPath: root.path) { return [] }
        let root = root.standardizedFileURL.resolvingSymlinksInPath()
        var result: [LocalBackup] = []
        if let item = try? LocalBackup.read(root) { return [item] }
        let children = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        for child in children.prefix(1_000) {
            guard let flags = try? child.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey]) else { continue }
            guard flags.isDirectory == true, flags.isSymbolicLink != true else { continue }
            if let item = try? LocalBackup.read(child) { result.append(item) }
            else if UUID(uuidString: child.lastPathComponent) != nil {
                // Une session inaccessible ou disparue ne masque pas les autres sauvegardes.
                guard let nestedFolders = try? FileManager.default.contentsOfDirectory(at: child, includingPropertiesForKeys: nil) else { continue }
                for nested in nestedFolders.prefix(100) {
                    if let item = try? LocalBackup.read(nested) { result.append(item) }
                }
            }
        }
        return result.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
    }
}
