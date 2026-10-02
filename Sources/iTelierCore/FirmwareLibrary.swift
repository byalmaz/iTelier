import Foundation

/// Discovers completed IPSWs on disk; no session state or filename is trusted as proof.
public enum FirmwareLibrary {
    public static func existingFirmware(for release: FirmwareRelease, in directory: URL) async throws -> FirmwareInfo? {
        try Task.checkCancellation()
        guard directory.isFileURL, release.fileSize > 0 else { throw FirmwareTransferError.invalidMetadata }
        let expectedSHA256 = try FirmwareRelease.checksum(release.sha256, length: 64)
        let expectedSHA1 = try FirmwareRelease.checksum(release.sha1, length: 40)
        let files = try FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])
            .filter { $0.pathExtension.lowercased() == "ipsw" }
            .sorted {
                let left = $0.lastPathComponent == release.url.lastPathComponent
                let right = $1.lastPathComponent == release.url.lastPathComponent
                return left != right ? left : $0.lastPathComponent < $1.lastPathComponent
            }
        let runner = ProcessRunner()
        for file in files {
            try Task.checkCancellation()
            do {
                let before = try FileFingerprint.read(file)
                guard before.size == UInt64(release.fileSize) else { continue }
                // Check cheap identity metadata before hashing a multi-gigabyte file.
                let result = try await runner.run(executable: "/usr/bin/unzip",
                    arguments: ["-p", file.path, "BuildManifest.plist"], timeout: 30,
                    outputLimit: FirmwareInspector.manifestLimit)
                guard result.exitCode == 0 else { continue }
                let manifest = try FirmwareManifest.parse(result.stdout)
                guard manifest.version == release.version, manifest.build == release.buildID,
                      manifest.supportedProductTypes.contains(release.identifier) else { continue }
                let inspected = try await FirmwareInspector.inspect(file, runner: runner)
                if let expectedSHA256 {
                    guard inspected.sha256 == expectedSHA256 else { continue }
                } else if let expectedSHA1 {
                    guard try await FirmwareInspector.sha1(file) == expectedSHA1 else { continue }
                } else {
                    // Older/beta catalogue entries can omit a digest. Verify every ZIP
                    // member's CRC rather than accepting a readable manifest alone.
                    let archive = try await runner.run(executable: "/usr/bin/unzip",
                        arguments: ["-tqq", file.path], timeout: 600, outputLimit: 1_048_576)
                    guard archive.exitCode == 0 else { continue }
                }
                guard try FileFingerprint.read(file) == before else { continue }
                return inspected
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                // A damaged, partial or inaccessible file is left intact; try the next copy.
                try Task.checkCancellation()
                continue
            }
        }
        return nil
    }
}
