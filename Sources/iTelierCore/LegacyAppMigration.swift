import Foundation
import CryptoKit

/// Identifie les anciens formats par empreinte, sans reprendre leur marque dans le produit.
public enum LegacyAppMigration {
    private static let directoryID = "e33ab78f24a9926f692aee43e9c7f7f8e9215005d2f9264b79c710d351936baa"
    private static let preferencesID = "7f06c14c7cda196a721e83b1626fca63e442af82be37b571361b0dac04c252d6"
    private static let markerID = "1946cea069483410b13503c27f912d7085d43fc3f0cca13213a22b5810f264c4"
    private static let reportIDs: Set<String> = [directoryID,
        "eec017c4a1b1e4c0c288ae33cfaa608880c752dd2ce91c2c2e2c928ff956e6d8"]

    private static func fingerprint(_ value: String) -> String {
        SHA256.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    public static func acceptsReportApplication(_ value: String) -> Bool {
        value == "iTelier" || reportIDs.contains(fingerprint(value))
    }

    public static func hasIncompleteMarker(in directory: URL) -> Bool {
        let files = (try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        return files.contains { $0.lastPathComponent == "itelier-incomplete" || fingerprint($0.lastPathComponent) == markerID }
    }

    public static func prepare() throws {
        let manager = FileManager.default
        try prepare(support: manager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0],
                    downloads: manager.urls(for: .downloadsDirectory, in: .userDomainMask)[0],
                    preferences: manager.urls(for: .libraryDirectory, in: .userDomainMask)[0].appendingPathComponent("Preferences"),
                    defaults: .standard, domain: "com.itelier.app",
                    removePreviousDomain: { UserDefaults.standard.removePersistentDomain(forName: $0) })
    }

    /// Déplace les dossiers sans remplacer de fichier ; les verrous bloquent une migration pendant une opération.
    static func prepare(support: URL, downloads: URL, preferences: URL, defaults: UserDefaults, domain: String,
                        removePreviousDomain: (String) -> Void = { _ in }) throws {
        let manager = FileManager.default
        func oldDirectory(in parent: URL) throws -> URL? {
            guard manager.fileExists(atPath: parent.path) else { return nil }
            return try manager.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil)
                .first { fingerprint($0.lastPathComponent) == directoryID }
        }
        let oldSupport = try oldDirectory(in: support)
        // Ne pas ouvrir tout le dossier Téléchargements au démarrage : macOS peut
        // attendre une autorisation. Le dossier historique est connu par son nom.
        let oldDownloads = oldSupport.map { downloads.appendingPathComponent($0.lastPathComponent) }
            .flatMap { manager.fileExists(atPath: $0.path) ? $0 : nil }
        let newSupport = support.appendingPathComponent("iTelier", isDirectory: true)
        let newDownloads = downloads.appendingPathComponent("iTelier", isDirectory: true)
        let preferenceFiles = (try? manager.contentsOfDirectory(at: preferences, includingPropertiesForKeys: nil)) ?? []
        let oldPreferences = preferenceFiles.first { fingerprint($0.deletingPathExtension().lastPathComponent) == preferencesID }
        var previousValues: [String: Any] = [:]
        if let old = oldPreferences {
            guard old.standardizedFileURL == old.resolvingSymlinksInPath() else {
                throw BackupError.invalid(L("Les réglages locaux ne peuvent pas être lus en toute sécurité."))
            }
            let data = try RestoreHost.readBounded(old, limit: 1_048_576)
            guard let values = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
                throw BackupError.invalid(L("Les réglages locaux ne peuvent pas être lus en toute sécurité."))
            }
            previousValues = values
        }
        let moves = [(oldSupport, newSupport), (oldDownloads, newDownloads)].compactMap { source, destination in
            source.map { ($0, destination) }
        }
        // Préflight complet avant le premier déplacement : aucun écrasement, aucun lien suivi.
        for (source, destination) in moves {
            guard source.standardizedFileURL == source.resolvingSymlinksInPath(),
                  !manager.fileExists(atPath: destination.path) else {
                throw BackupError.invalid(L("Les données locales ne peuvent pas être déplacées sans remplacer un dossier existant."))
            }
        }
        var locks: [HostLock] = []
        if let oldSupport {
            for name in ["USBOperation", "Restores", "BackupOperations"] {
                let root = oldSupport.appendingPathComponent(name)
                if manager.fileExists(atPath: root.path) {
                    let lockFile = root.appendingPathComponent("engine.lock")
                    guard root.standardizedFileURL == root.resolvingSymlinksInPath(),
                          lockFile.standardizedFileURL == lockFile.resolvingSymlinksInPath() else {
                        throw BackupError.invalid(L("Les réglages locaux ne peuvent pas être lus en toute sécurité."))
                    }
                    locks.append(try HostLock(root: root, acquire: true))
                }
            }
        }
        defer { withExtendedLifetime(locks) {} }
        for (source, destination) in moves { try manager.moveItem(at: source, to: destination) }

        func remapped(_ value: Any) -> Any {
            if let string = value as? String {
                for parent in [support, downloads] {
                    let prefix = parent.path + "/"
                    guard string.hasPrefix(prefix) else { continue }
                    let remainder = String(string.dropFirst(prefix.count))
                    let parts = remainder.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)
                    if let first = parts.first, fingerprint(String(first)) == directoryID {
                        return prefix + "iTelier" + (parts.count > 1 ? "/" + parts[1] : "")
                    }
                }
                return string
            }
            if let array = value as? [Any] { return array.map(remapped) }
            if let object = value as? [String: Any] { return object.mapValues(remapped) }
            return value
        }

        if oldSupport != nil, let files = manager.enumerator(at: newSupport,
                includingPropertiesForKeys: [.isSymbolicLinkKey], options: [.skipsHiddenFiles]) {
            for case let file as URL in files {
                if (try file.resourceValues(forKeys: [.isSymbolicLinkKey])).isSymbolicLink == true {
                    files.skipDescendants(); continue
                }
                let migrationRoot = newSupport.resolvingSymlinksInPath().standardizedFileURL
                var parent = file.resolvingSymlinksInPath().standardizedFileURL
                var relative: [String] = []
                while parent != migrationRoot && relative.count <= 3 {
                    relative.insert(parent.lastPathComponent, at: 0)
                    parent = parent.deletingLastPathComponent()
                }
                // Les contenus de sauvegarde ne sont jamais parcourus : seuls
                // les marqueurs de session et journaux des opérations sont utiles.
                guard parent == migrationRoot, let category = relative.first, ["Backups", "Restores", "BackupOperations"].contains(category),
                      relative.count <= 3 else { files.skipDescendants(); continue }
                if relative.count == 3 { files.skipDescendants() }
                if fingerprint(file.lastPathComponent) == markerID {
                    let destination = file.deletingLastPathComponent().appendingPathComponent("itelier-incomplete")
                    guard !manager.fileExists(atPath: destination.path) else { continue }
                    try manager.moveItem(at: file, to: destination)
                } else if ["request.json", "state.json"].contains(file.lastPathComponent),
                          ["Restores", "BackupOperations"].contains(file.deletingLastPathComponent().deletingLastPathComponent().lastPathComponent) {
                    let original = try RestoreHost.readBounded(file, limit: 2_000_000)
                    let object = try JSONSerialization.jsonObject(with: original)
                    let rewritten = try JSONSerialization.data(withJSONObject: remapped(object), options: [.sortedKeys])
                    if rewritten != original {
                        try rewritten.write(to: file, options: .atomic)
                        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
                    }
                }
            }
        }

        if let old = oldPreferences {
            var merged = defaults.persistentDomain(forName: domain) ?? [:]
            for (key, value) in previousValues where merged[key] == nil { merged[key] = remapped(value) }
            defaults.setPersistentDomain(merged, forName: domain)
            guard defaults.synchronize() else { throw BackupError.invalid(L("Les réglages locaux n’ont pas pu être enregistrés.")) }
            removePreviousDomain(old.deletingPathExtension().lastPathComponent)
            defaults.synchronize()
            if manager.fileExists(atPath: old.path) { try manager.removeItem(at: old) }
        }
    }
}
