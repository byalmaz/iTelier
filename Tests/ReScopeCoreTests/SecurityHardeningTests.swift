import XCTest
@testable import ReScopeCore

/// Regression tests for the security review of 1 October 2026: secrets never reach a
/// process environment, and an IPSW name cannot redirect the manifest read by unzip.
final class SecurityHardeningTests: XCTestCase {
    private let deviceID = "TEST-DEVICE-0001"
    private let secret = "test-only-secret"

    func testProcessRunnerSendsInputOnStandardInputOnly() async throws {
        let echoed = try await ProcessRunner().run(executable: "/bin/cat", arguments: [], input: Data("first\nsecond\n".utf8))
        XCTAssertEqual(String(decoding: echoed.stdout, as: UTF8.self), "first\nsecond\n")
        // Without input, standard input stays /dev/null: the child reads end of file at once.
        let empty = try await ProcessRunner().run(executable: "/bin/cat", arguments: [], timeout: 5)
        XCTAssertTrue(empty.stdout.isEmpty)
        do {
            _ = try await ProcessRunner().run(executable: "/bin/cat", arguments: [], input: Data(count: 4_097))
            XCTFail("Une entrée plus grande qu’un tampon de pipe doit être refusée.")
        } catch {}
    }

    func testBackupPasswordRulesMatchWhatTheEngineCanReceive() {
        XCTAssertNil(BackupHost.passwordIssue("Correct horse 9!~"))
        XCTAssertNil(BackupHost.passwordIssue(String(repeating: "a", count: 255)))
        XCTAssertTrue(BackupHost.passwordIssue(String(repeating: "a", count: 256)) != nil)
        // idevicebackup2 -i silently drops these characters: refuse them instead.
        for rejected in ["mot-de-passé", "tab\tchar", "emoji 🔒", "line\nbreak"] {
            XCTAssertTrue(BackupHost.passwordIssue(rejected) != nil, rejected)
        }
        XCTAssertEqual(String(decoding: BackupHost.interactiveInput("pw", prompts: 2), as: UTF8.self), "pw\npw\n\n")
        XCTAssertEqual(String(decoding: BackupHost.interactiveInput("pw", prompts: 1), as: UTF8.self), "pw\n\n")
    }

    func testOnlyEncryptedRestoreAsksTheEngineForAPassword() throws {
        let directory = URL(fileURLWithPath: "/private/tmp").resolvingSymlinksInPath()
        let restore = BackupRequest(operation: .restore, target: target(), directory: directory,
                                    source: deviceID, fingerprint: "test", enableEncryption: false)
        XCTAssertEqual(try restore.arguments(interactivePassword: true),
                       ["-u", deviceID, "-s", deviceID, "-i", "restore", "--system", "--settings", directory.path])
        XCTAssertFalse(try restore.arguments().contains("-i"))
        let backup = BackupRequest(operation: .backup, target: target(), directory: directory,
                                   source: nil, fingerprint: nil, enableEncryption: true)
        XCTAssertFalse(try backup.arguments(interactivePassword: true).contains("-i"))
    }

    func testWorkerReadsAPipedPasswordWithABound() throws {
        let pipe = Pipe()
        try pipe.fileHandleForWriting.write(contentsOf: Data(secret.utf8))
        try pipe.fileHandleForWriting.close()
        XCTAssertEqual(BackupHost.readPassword(from: pipe.fileHandleForReading), secret)
        let oversized = Pipe()
        try oversized.fileHandleForWriting.write(contentsOf: Data(repeating: 0x61, count: 1_025))
        try oversized.fileHandleForWriting.close()
        XCTAssertEqual(BackupHost.readPassword(from: oversized.fileHandleForReading), "")
    }

    func testEncryptedRestoreSendsThePasswordOnStandardInput() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let data = root.appendingPathComponent("data")
        try backupFixture(at: data.appendingPathComponent(deviceID), encrypted: true)
        let backup = try LocalBackup.read(data.appendingPathComponent(deviceID))
        let session = try session(in: root, request: BackupRequest(operation: .restore, target: target(), directory: data,
            source: backup.source, fingerprint: backup.fingerprint, enableEncryption: false))
        // The inert engine succeeds only with -i, the password on stdin and no password variable.
        let engine = try script(root, "engine", """
            case " $* " in *" -i restore "*) ;; *) echo "missing -i"; exit 1 ;; esac
            [ -z "${BACKUP_PASSWORD+x}" ] || { echo "password in environment"; exit 1; }
            IFS= read -r line && [ "$line" = '\(secret)' ] || { echo "password not on stdin"; exit 1; }
            echo "Restore Successful."
            """)
        let code = await BackupHost.runWorker(sessionPath: session.path, root: root, engine: engine,
                                              infoTool: try infoTool(root), password: secret)
        XCTAssertEqual(code, 0, BackupHost.read(session)?.phase ?? "")
        try assertNoSecret(in: session)
    }

    func testEncryptionIsEnabledThroughStandardInputAndBackupGetsNoPassword() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let data = root.appendingPathComponent("data")
        try backupFixture(at: data.appendingPathComponent(deviceID), encrypted: true)
        try Data().write(to: data.appendingPathComponent("rescope-incomplete"))
        let session = try session(in: root, request: BackupRequest(operation: .backup, target: target(), directory: data,
            source: nil, fingerprint: nil, enableEncryption: true))
        let engine = try script(root, "engine", """
            [ -z "${BACKUP_PASSWORD+x}" ] || { echo "password in environment"; exit 1; }
            case " $* " in
            *" -i encryption on "*)
                IFS= read -r first && IFS= read -r second || exit 1
                [ "$first" = '\(secret)' ] && [ "$second" = '\(secret)' ] || exit 1
                echo "Backup encryption has been enabled successfully." ;;
            *" backup --full "*)
                if IFS= read -r unexpected; then echo "unexpected stdin"; exit 1; fi
                echo "Backup Successful." ;;
            *) exit 1 ;;
            esac
            """)
        let code = await BackupHost.runWorker(sessionPath: session.path, root: root, engine: engine,
                                              infoTool: try infoTool(root, willEncrypt: "false"), password: secret)
        XCTAssertEqual(code, 0, BackupHost.read(session)?.phase ?? "")
        try assertNoSecret(in: session)
    }

    func testIPSWNamesWithUnzipWildcardsAreRefused() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        // Wildcards in parent directories are read literally by unzip and stay accepted.
        let folder = root.appendingPathComponent("IPSW [archive]", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for name in ["a[b].ipsw", "x?.ipsw", "all*.ipsw", "back\\slash.ipsw", "firmware.ipsw"] {
            try Data("fixture".utf8).write(to: folder.appendingPathComponent(name))
        }
        for name in ["a[b].ipsw", "x?.ipsw", "all*.ipsw", "back\\slash.ipsw"] {
            XCTAssertThrowsError(try FileFingerprint.read(folder.appendingPathComponent(name)), name)
        }
        XCTAssertEqual(try FileFingerprint.read(folder.appendingPathComponent("firmware.ipsw")).size, 7)
    }

    func testRestoreEngineIsResolvedFromTheRealExecutable() {
        guard let directory = RestoreHost.helperDirectory else { return XCTFail("Exécutable introuvable.") }
        XCTAssertEqual(directory, Bundle.main.executableURL?.resolvingSymlinksInPath().deletingLastPathComponent())
        var isDirectory: ObjCBool = false
        XCTAssertTrue(FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory) && isDirectory.boolValue)
    }

    // MARK: - Fixtures

    private func target() -> DeviceSnapshot {
        DeviceSnapshot(id: deviceID, name: "Appareil", productType: "iPhone14,2", osVersion: "27.2", ecid: "123456789")
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
    }

    private func session(in root: URL, request: BackupRequest) throws -> URL {
        let session = root.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        try RestoreHost.write(request, to: session.appendingPathComponent("request.json"))
        return session
    }

    private func backupFixture(at folder: URL, encrypted: Bool) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let files: [(String, [String: Any])] = [
            ("Info.plist", ["Product Type": "iPhone14,2", "Product Version": "27.2", "Device Name": "Test"]),
            ("Manifest.plist", ["IsEncrypted": encrypted]),
            ("Status.plist", ["SnapshotState": "finished"])
        ]
        for (name, values) in files {
            try PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0).write(to: folder.appendingPathComponent(name))
        }
        try Data("fixture database".utf8).write(to: folder.appendingPathComponent("Manifest.db"))
    }

    private func infoTool(_ root: URL, willEncrypt: String = "true") throws -> URL {
        let values: [String: Any] = ["ProductType": "iPhone14,2", "ProductVersion": "27.2", "UniqueChipID": 123456789]
        let xml = String(decoding: try PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0), as: UTF8.self)
        return try script(root, "info", "case \" $* \" in *\" WillEncrypt \"*) echo \(willEncrypt) ;; *) cat <<'PLIST'\n\(xml)\nPLIST\n;; esac")
    }

    private func script(_ root: URL, _ name: String, _ body: String) throws -> URL {
        let url = root.appendingPathComponent(name)
        try Data(("#!/bin/sh\n" + body + "\n").utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }

    private func assertNoSecret(in session: URL) throws {
        for file in try FileManager.default.contentsOfDirectory(at: session, includingPropertiesForKeys: nil) {
            let text = String(decoding: (try? Data(contentsOf: file)) ?? Data(), as: UTF8.self)
            XCTAssertFalse(text.contains(secret), file.lastPathComponent)
        }
    }
}
