import Foundation
import CryptoKit

struct FileFingerprint: Equatable, Sendable {
    let size: UInt64
    let modificationDate: Date
    let inode: UInt64
    let device: UInt64

    static func read(_ url: URL) throws -> FileFingerprint {
        guard url.isFileURL, url.pathExtension.lowercased() == "ipsw" else {
            throw DeviceServiceError.invalidData(L("Sélectionnez un fichier local portant l’extension .ipsw."))
        }
        // /usr/bin/unzip treats these characters in an archive name as a pattern: "a[b].ipsw" would
        // validate the manifest of "ab.ipsw" while the hash and the restore use the selected file.
        guard url.lastPathComponent.rangeOfCharacter(from: CharacterSet(charactersIn: "*?[]\\")) == nil else {
            throw DeviceServiceError.invalidData(L("Renommez ce fichier IPSW : son nom ne doit contenir ni *, ni ?, ni crochets, ni barre oblique inverse."))
        }
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              let size = (attributes[.size] as? NSNumber)?.uint64Value, size > 0,
              size < UInt64(Int64.max), let date = attributes[.modificationDate] as? Date,
              let inode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value,
              let device = (attributes[.systemNumber] as? NSNumber)?.uint64Value else {
            throw DeviceServiceError.invalidData(L("Le fichier IPSW est vide, inaccessible ou n’est pas un fichier régulier."))
        }
        return FileFingerprint(size: size, modificationDate: date, inode: inode, device: device)
    }
}

enum FirmwareInspector {
    static let manifestLimit = 16 * 1_024 * 1_024

    static func inspect(_ url: URL, runner: ProcessRunner) async throws -> FirmwareInfo {
        let fingerprint = try FileFingerprint.read(url)
        let result = try await runner.run(executable: "/usr/bin/unzip", arguments: ["-p", url.path, "BuildManifest.plist"],
                                          timeout: 30, outputLimit: manifestLimit)
        guard result.exitCode == 0 else {
            throw DeviceServiceError.invalidData(L("Impossible de lire BuildManifest.plist. Le fichier doit être une archive IPSW valide."))
        }
        let manifest = try FirmwareManifest.parse(result.stdout)
        let digest = try await sha256(url)
        guard try FileFingerprint.read(url) == fingerprint else {
            throw DeviceServiceError.unsafeRestore(L("Le fichier IPSW a changé pendant sa vérification. Sélectionnez-le à nouveau."))
        }
        return FirmwareInfo(url: url, version: manifest.version, build: manifest.build,
                            supportedProductTypes: manifest.supportedProductTypes,
                            sizeBytes: Int64(fingerprint.size), sha256: digest,
                            eraseHardwareModels: manifest.eraseHardwareModels, updateVariants: manifest.updateVariants)
    }

    /// Streaming avoids loading a multi-gigabyte IPSW into memory. Cancellation is checked per MiB.
    static func sha256(_ url: URL) async throws -> String {
        try await digest(url, using: SHA256())
    }

    static func sha1(_ url: URL) async throws -> String {
        try await digest(url, using: Insecure.SHA1())
    }

    private static func digest<H: HashFunction & Sendable>(_ url: URL, using initialHasher: H) async throws -> String {
        let worker = Task.detached(priority: .userInitiated) {
            let file = try FileHandle(forReadingFrom: url)
            defer { try? file.close() }
            var hasher = initialHasher
            while true {
                try Task.checkCancellation()
                guard let data = try file.read(upToCount: 1_024 * 1_024), !data.isEmpty else { break }
                hasher.update(data: data)
            }
            try Task.checkCancellation()
            return hasher.finalize().map { String(format: "%02x", $0) }.joined()
        }
        return try await withTaskCancellationHandler(operation: {
            try Task.checkCancellation()
            return try await worker.value
        }, onCancel: { worker.cancel() })
    }
}
