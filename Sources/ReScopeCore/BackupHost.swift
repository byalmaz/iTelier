import Foundation
import Darwin

public enum BackupOperation: String, Codable, Sendable { case backup, restore }
public struct BackupHostState: Codable, Sendable {
    public let sessionID: String
    public let operation: BackupOperation
    public var phase: String
    public var progress: Double?
    public var finished = false
    public var exitCode: Int32?
    public var updatedAt = Date()
}

struct BackupRequest: Codable {
    let operation: BackupOperation
    let target: DeviceSnapshot
    let directory: URL
    let source: String?
    let fingerprint: String?
    let enableEncryption: Bool

    /// `interactivePassword` adds `-i`: the engine then reads the password from standard input.
    func arguments(interactivePassword: Bool = false) throws -> [String] {
        guard DeviceParser.validUDID(target.id), target.mode == .normal, directory.isFileURL,
              directory.path.hasPrefix("/"), directory == directory.standardizedFileURL.resolvingSymlinksInPath() else {
            throw BackupError.invalid(L("La cible ou le dossier de sauvegarde n’est pas valide."))
        }
        // A backup never needs the password: the device encrypts with its own stored one.
        if operation == .backup { return ["-u", target.id, "backup", "--full", directory.path] }
        guard let source, source.range(of: "^[a-zA-Z0-9-]{1,100}$", options: .regularExpression) != nil else {
            throw BackupError.invalid(L("Le dossier source n’est pas valide."))
        }
        // Never remove un-restored items or change the installed version of iOS.
        return ["-u", target.id, "-s", source] + (interactivePassword ? ["-i"] : []) + ["restore", "--system", "--settings", directory.path]
    }
}

public enum BackupHost {
    public static var root: URL { BackupLibrary.defaultDirectory.deletingLastPathComponent().appendingPathComponent("BackupOperations") }
    static var sharedLockRoot: URL { root.deletingLastPathComponent().appendingPathComponent("USBOperation") }
    public static var isRunning: Bool { RestoreHost.isLocked(root: root) }

    /// idevicebackup2 -i keeps only printable ASCII and at most 255 bytes of each password.
    /// Anything else is refused: the engine would otherwise silently use a different password.
    public static func passwordIssue(_ password: String) -> String? {
        guard password.utf8.count <= 255, password.unicodeScalars.allSatisfy({ (0x20...0x7E).contains($0.value) }) else {
            return L("Le mot de passe doit compter au plus 255 caractères : lettres sans accents, chiffres, espaces ou ponctuation ASCII.")
        }
        return nil
    }

    /// One line per expected prompt, plus an empty line: an unexpected extra prompt then
    /// fails on an empty password instead of looping forever on end of input.
    static func interactiveInput(_ password: String, prompts: Int) -> Data {
        Data((String(repeating: password + "\n", count: prompts) + "\n").utf8)
    }

    public static func encryptionEnabled(deviceID: String) async throws -> Bool {
        guard DeviceParser.validUDID(deviceID), let info = ToolResolver.resolve("ideviceinfo") else {
            throw BackupError.invalid(L("Le moteur de lecture de l’appareil est indisponible."))
        }
        let result = try await ProcessRunner().run(executable: info, arguments: ["-u", deviceID, "-q", "com.apple.mobile.backup", "-k", "WillEncrypt"])
        let value = String(decoding: result.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard result.exitCode == 0, ["true", "false"].contains(value) else {
            throw BackupError.invalid(L("Impossible de lire le chiffrement de l’appareil."))
        }
        return value == "true"
    }

    public static func markInterrupted(_ directory: URL) {
        guard !isRunning, directory.deletingLastPathComponent() == root, var state = read(directory), !state.finished else { return }
        state.finished = true; state.exitCode = -1; state.updatedAt = Date()
        state.phase = L("Opération interrompue · résultat non confirmé")
        try? RestoreHost.write(state, to: directory.appendingPathComponent("state.json"))
    }

    public static func read(_ directory: URL) -> BackupHostState? {
        guard let data = try? RestoreHost.readBounded(directory.appendingPathComponent("state.json"), limit: 8_192),
              let state = try? JSONDecoder().decode(BackupHostState.self, from: data), state.sessionID == directory.lastPathComponent else { return nil }
        return state
    }
    public static func latest() -> (directory: URL, state: BackupHostState)? {
        ((try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? [])
            .filter { UUID(uuidString: $0.lastPathComponent) != nil }
            .compactMap { url in read(url).map { (directory: url, state: $0) } }
            .max { $0.state.updatedAt < $1.state.updatedAt }
    }

    public static func launch(device: DeviceSnapshot, library: URL, backup: LocalBackup? = nil,
                              enableEncryption: Bool = false, password: String = "") throws -> URL {
        guard !isRunning, !RestoreHost.isRunning else { throw BackupError.invalid(L("Une opération sur l’appareil est déjà en cours.")) }
        if !password.isEmpty, let issue = passwordIssue(password) { throw BackupError.invalid(issue) }
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/ReScopeRestoreHost")
        guard FileManager.default.isExecutableFile(atPath: helper.path) else { throw BackupError.invalid(L("Ouvrez le bundle iTelier complet pour utiliser les sauvegardes.")) }
        let session = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let fm = FileManager.default
        try fm.createDirectory(at: session, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let operation: BackupOperation = backup == nil ? .backup : .restore
        let directory: URL
        if let backup {
            if let issue = backup.restorationIssue(for: device) { throw BackupError.invalid(issue) }
            directory = backup.directory.deletingLastPathComponent()
        } else {
            let library = library.standardizedFileURL.resolvingSymlinksInPath()
            try fm.createDirectory(at: library, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            directory = library.appendingPathComponent(UUID().uuidString, isDirectory: true)
            try fm.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
            try Data().write(to: directory.appendingPathComponent("rescope-incomplete"))
        }
        // Persist only the target identity required for revalidation; never persist passwords.
        let target = DeviceSnapshot(id: device.id, name: L("Appareil"), productType: device.productType,
                                    osVersion: device.osVersion, ecid: device.ecid)
        let request = BackupRequest(operation: operation, target: target, directory: directory,
                                    source: backup?.source, fingerprint: backup?.fingerprint, enableEncryption: enableEncryption)
        _ = try request.arguments()
        try RestoreHost.write(request, to: session.appendingPathComponent("request.json"))
        try RestoreHost.write(BackupHostState(sessionID: session.lastPathComponent, operation: operation, phase: L("Vérification de l’appareil")), to: session.appendingPathComponent("state.json"))
        let process = Process()
        process.executableURL = helper; process.arguments = ["--backup", session.path]
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        // The password crosses a pipe, never the environment or the arguments: `ps eww` shows
        // a process's initial environment to every program of the user, even after unsetenv().
        // Written before launch (at most 255 bytes) while this process holds the read end.
        let input = Pipe()
        try input.fileHandleForWriting.write(contentsOf: Data(password.utf8))
        try input.fileHandleForWriting.close()
        process.standardInput = input
        var environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("DYLD_") && !$0.key.hasPrefix("BACKUP_PASSWORD") }
        environment["RESCOPE_LANGUAGE"] = AppLocalization.language
        process.environment = environment
        try process.run()
        try? input.fileHandleForReading.close()
        return session
    }

    public static func cancel(_ directory: URL) throws {
        guard directory.deletingLastPathComponent() == root, let state = read(directory), state.operation == .backup, !state.finished else { return }
        try Data().write(to: directory.appendingPathComponent("cancel"), options: .atomic)
    }

    public static func runWorker(sessionPath: String) async -> Int32 {
        let password = readPassword(from: .standardInput)
        guard let helperDirectory = RestoreHost.helperDirectory else { return 2 }
        return await runWorker(sessionPath: sessionPath, root: root,
                               engine: helperDirectory.appendingPathComponent("idevicebackup2"),
                               infoTool: helperDirectory.appendingPathComponent("ideviceinfo"), password: password)
    }

    /// Reads the password piped by the app until end of input. A terminal is never read,
    /// and oversized input yields no password, so steps that need one fail safely.
    static func readPassword(from handle: FileHandle) -> String {
        guard isatty(handle.fileDescriptor) == 0,
              let data = try? handle.read(upToCount: 1_025), data.count <= 1_024 else { return "" }
        return String(decoding: data, as: UTF8.self)
    }

    static func runWorker(sessionPath: String, root: URL, engine: URL, infoTool: URL, password: String = "") async -> Int32 {
        let session = URL(fileURLWithPath: sessionPath).standardizedFileURL.resolvingSymlinksInPath()
        guard session.deletingLastPathComponent() == root.resolvingSymlinksInPath(), UUID(uuidString: session.lastPathComponent) != nil else { return 2 }
        do {
            let lock = try HostLock(root: root, acquire: true)
            let operationLock = try HostLock(root: root == Self.root ? sharedLockRoot : root.appendingPathComponent("operation-lock"), acquire: true)
            defer { withExtendedLifetime((lock, operationLock)) {} }
            // One-shot worker, including after an app crash; never replay a restore request.
            let fd = Darwin.open(session.appendingPathComponent("started").path, O_CREAT | O_EXCL | O_WRONLY, S_IRUSR | S_IWUSR)
            guard fd >= 0 else { return 3 }; Darwin.close(fd)
            let data = try RestoreHost.readBounded(session.appendingPathComponent("request.json"), limit: 16_384)
            let request = try JSONDecoder().decode(BackupRequest.self, from: data)
            let journal = BackupProgressJournal(session: session, operation: request.operation)
            let activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled], reason: L("Sauvegarde d’un appareil"))
            defer { ProcessInfo.processInfo.endActivity(activity) }
            _ = umask(0o077)
            do {
                if !password.isEmpty, let issue = passwordIssue(password) { throw BackupError.invalid(issue) }
                var arguments = try request.arguments()
                var passwordInput: Data?
                let runner = ProcessRunner()
                let identity = try await runner.run(executable: infoTool.path, arguments: ["-u", request.target.id, "-x"])
                guard identity.exitCode == 0 else { throw BackupError.invalid(L("Déverrouillez l’appareil et acceptez « Faire confiance » avant de réessayer.")) }
                let current = try DeviceParser.normalDevice(id: request.target.id, data: identity.stdout)
                guard current.productType == request.target.productType, let ecid = request.target.ecid,
                      DeviceParser.normalizedECID(ecid) == current.ecid else { throw BackupError.invalid(L("L’appareil connecté a changé. Confirmez à nouveau la cible.")) }
                if request.operation == .restore {
                    let backup = try LocalBackup.read(request.directory.appendingPathComponent(request.source!))
                    if let issue = backup.restorationIssue(for: current) { throw BackupError.invalid(issue) }
                    guard backup.fingerprint == request.fingerprint else { throw BackupError.invalid(L("La sauvegarde a changé depuis sa sélection.")) }
                    if backup.encrypted {
                        if password.isEmpty { throw BackupError.invalid(L("Le mot de passe de cette sauvegarde est nécessaire.")) }
                        arguments = try request.arguments(interactivePassword: true)
                        passwordInput = Self.interactiveInput(password, prompts: 1)
                    }
                } else {
                    let space = try FileManager.default.attributesOfFileSystem(forPath: request.directory.path)[.systemFreeSize] as? NSNumber
                    guard let space, space.int64Value > 512 * 1_024 * 1_024 else { throw BackupError.invalid(L("L’espace libre est insuffisant pour démarrer une sauvegarde.")) }
                    if request.enableEncryption {
                        let result = try await runner.run(executable: infoTool.path, arguments: ["-u", current.id, "-q", "com.apple.mobile.backup", "-k", "WillEncrypt"])
                        let state = String(decoding: result.stdout, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                        guard result.exitCode == 0, ["true", "false"].contains(state) else { throw BackupError.invalid(L("Impossible de vérifier le chiffrement de l’appareil.")) }
                        if state == "false" {
                            guard !password.isEmpty else { throw BackupError.invalid(L("Choisissez un mot de passe pour activer le chiffrement.")) }
                            journal.phase(L("Confirmez le chiffrement sur l’appareil"))
                            // -i: the new password and its confirmation are read from standard input.
                            let encrypted = try await runner.run(executable: engine.path, arguments: ["-u", current.id, "-i", "encryption", "on"], timeout: 180,
                                input: Self.interactiveInput(password, prompts: 2))
                            guard encrypted.exitCode == 0 else { throw BackupError.invalid(L("Le chiffrement n’a pas été activé. Vérifiez le code demandé sur l’appareil.")) }
                        }
                    }
                }
                journal.phase(request.operation == .backup ? L("Sauvegarde en cours · gardez l’appareil connecté") : L("Restauration des données en cours · gardez l’appareil connecté"))
                let operationArguments = arguments, operationInput = passwordInput
                let task = Task {
                    try await runner.run(executable: engine.path, arguments: operationArguments, timeout: nil, outputLimit: 64 * 1_024,
                        input: operationInput, onLine: { journal.receive($0) })
                }
                let cancelWatcher = Task {
                    while !Task.isCancelled {
                        if request.operation == .backup, FileManager.default.fileExists(atPath: session.appendingPathComponent("cancel").path) { task.cancel(); return }
                        try? await Task.sleep(nanoseconds: 300_000_000)
                    }
                }
                defer { cancelWatcher.cancel() }
                let result = try await task.value
                let output = String(decoding: result.stdout + result.stderr, as: UTF8.self)
                guard result.exitCode == 0, output.contains(request.operation == .backup ? "Backup Successful." : "Restore Successful.") else {
                    throw BackupError.invalid(Self.failureMessage(output))
                }
                if request.operation == .backup {
                    let folder = request.directory.appendingPathComponent(current.id)
                    let marker = request.directory.appendingPathComponent("rescope-incomplete")
                    // Completion requires both the engine's success and Apple's finished snapshot.
                    let statusData = try RestoreHost.readBounded(folder.appendingPathComponent("Status.plist"), limit: 1_048_576)
                    let status = try PropertyListSerialization.propertyList(from: statusData, format: nil) as? [String: Any]
                    guard status?["SnapshotState"] as? String == "finished" else { throw BackupError.invalid(L("La sauvegarde n’a pas été confirmée comme complète.")) }
                    let metadata = try LocalBackup.read(folder)
                    guard !request.enableEncryption || metadata.encrypted else { throw BackupError.invalid(L("Le chiffrement demandé n’est pas confirmé dans la sauvegarde.")) }
                    try FileManager.default.removeItem(at: marker)
                    guard try LocalBackup.read(folder).complete else {
                        try? Data().write(to: marker)
                        throw BackupError.invalid(L("La sauvegarde est incomplète."))
                    }
                }
                journal.finish(code: 0, phase: request.operation == .backup ? L("Sauvegarde terminée") : L("Données restaurées · l’appareil peut redémarrer"))
                return 0
            } catch is CancellationError {
                journal.finish(code: 130, phase: L("Sauvegarde annulée · données partielles non restaurables"))
                return 130
            } catch {
                let message = (error as? BackupError)?.localizedDescription ?? L("L’opération a été interrompue. Vérifiez la connexion USB et l’espace libre, puis consultez le rapport.")
                journal.finish(code: 1, phase: message)
                return 1
            }
        } catch { return 2 }
    }

    static func failureMessage(_ output: String) -> String {
        let text = output.lowercased()
        if text.contains("password") && (text.contains("incorrect") || text.contains("invalid")) { return L("Le mot de passe de la sauvegarde est incorrect.") }
        if text.contains("no space") { return L("Le disque est plein. Libérez de l’espace et recommencez la sauvegarde.") }
        if text.contains("find my") { return L("L’appareil demande de désactiver Localiser avant la restauration. Vérifiez son écran.") }
        return L("L’appareil n’a pas confirmé la fin de l’opération. Vérifiez son écran, la connexion USB et le mot de passe éventuel. Un rapport d’incident est disponible.")
    }
}

private final class BackupProgressJournal: @unchecked Sendable {
    private let lock = NSLock()
    private let session: URL
    private var state: BackupHostState
    private var lastSave = Date.distantPast
    init(session: URL, operation: BackupOperation) {
        self.session = session
        state = BackupHostState(sessionID: session.lastPathComponent, operation: operation, phase: L("Vérification de l’appareil"))
    }
    func phase(_ phase: String) { lock.lock(); defer { lock.unlock() }; state.phase = phase; save() }
    func receive(_ line: String) {
        lock.lock(); defer { lock.unlock() }
        // Allowlisted progress only: no file paths, contacts, identifiers or passwords in journals.
        if line.contains("Waiting for passcode") { state.phase = L("Saisissez le code de déverrouillage sur l’appareil") }
        if let range = line.range(of: "[0-9]{1,3}%", options: .regularExpression), let percent = Double(line[range].dropLast()), percent <= 100 {
            state.progress = percent / 100
        }
        if Date().timeIntervalSince(lastSave) > 0.5 { save() }
    }
    func finish(code: Int32, phase: String) {
        lock.lock(); defer { lock.unlock() }
        state.finished = true; state.exitCode = code; state.phase = phase
        if code == 0 { state.progress = 1 }; save()
    }
    private func save() {
        state.updatedAt = Date(); lastSave = Date()
        try? RestoreHost.write(state, to: session.appendingPathComponent("state.json"))
    }
}
