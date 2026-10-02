import Foundation
import Darwin

public struct RestoreHostSnapshot: Codable, Sendable {
    public let sessionID: String
    public var phase: String
    public var progress: Double?
    public var finished: Bool
    public var exitCode: Int32?
    public var updatedAt: Date
    /// Private local journal; excluded from support exports unless explicitly requested.
    public var log: [String]
    public var engineCompletion: RestoreCompletion? = nil

    /// Relit aussi les anciens journaux dont le code 0 pouvait masquer un échec.
    public var completion: RestoreCompletion {
        guard finished, let exitCode else { return .unconfirmed }
        var tracker = RestoreCompletionTracker()
        log.forEach { tracker.append($0) }
        let observed = tracker.completion(exitCode: exitCode)
        if observed == .failed || engineCompletion == .failed { return .failed }
        if engineCompletion == .confirmed { return .confirmed }
        return observed
    }
}

private struct RestoreHostRequest: Codable {
    let arguments: [String]
    let firmwareSHA256: String
}

/// The worker owns the restore process and its pipes. Closing/crashing the UI cannot
/// break the engine's stdout pipe or implicitly cancel a firmware write.
public enum RestoreHost {
    public static var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ReScope/Restores", isDirectory: true)
    }

    static func launch(arguments: [String], firmwareSHA256: String, directory: URL) throws {
        guard !isRunning else { throw DeviceServiceError.unsafeRestore(L("Une restauration est déjà en cours. iTelier doit d’abord retrouver son état.")) }
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/ReScopeRestoreHost")
        guard FileManager.default.isExecutableFile(atPath: helper.path) else {
            throw DeviceServiceError.unsafeRestore(L("Le module de protection de la restauration est absent. Lancez le bundle iTelier complet."))
        }
        try write(RestoreHostRequest(arguments: arguments, firmwareSHA256: firmwareSHA256), to: directory.appendingPathComponent("request.json"))
        try detach(executable: helper, directory: directory)
    }

    static func detach(executable: URL, directory: URL) throws {
        let worker = Process()
        worker.executableURL = executable
        worker.arguments = [directory.path]
        worker.standardInput = FileHandle.nullDevice
        worker.standardOutput = FileHandle.nullDevice
        worker.standardError = FileHandle.nullDevice
        var environment = ProcessInfo.processInfo.environment
        for key in environment.keys where key.hasPrefix("DYLD_") { environment.removeValue(forKey: key) }
        environment["RESCOPE_LANGUAGE"] = AppLocalization.language
        worker.environment = environment
        try worker.run()
        // Deliberately no termination handler tied to app lifetime or task cancellation.
    }

    public static var isRunning: Bool { isLocked(root: root) }

    static func isLocked(root: URL) -> Bool {
        guard let lock = try? HostLock(root: root, acquire: false) else { return true }
        return lock.wasBusy
    }

    public static func latest() -> (directory: URL, snapshot: RestoreHostSnapshot)? {
        let entries = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
        return entries.compactMap { directory -> (URL, RestoreHostSnapshot)? in
            guard UUID(uuidString: directory.lastPathComponent) != nil,
                  let snapshot = read(directory) else { return nil }
            return (directory, snapshot)
        }.max { $0.1.updatedAt < $1.1.updatedAt }
    }

    public static func read(_ directory: URL) -> RestoreHostSnapshot? {
        guard let data = try? readBounded(directory.appendingPathComponent("state.json"), limit: 2_000_000),
              let state = try? JSONDecoder().decode(RestoreHostSnapshot.self, from: data),
              state.sessionID == directory.lastPathComponent else { return nil }
        return state
    }

    static func wait(directory: URL, onEvent: @escaping @Sendable (RestoreEvent) -> Void) async throws -> CommandResult {
        let started = Date()
        var previous: RestoreHostSnapshot?
        while true {
            if let state = read(directory) {
                if state.phase != previous?.phase { onEvent(.phase(state.phase)) }
                if let progress = state.progress, progress != previous?.progress { onEvent(.progress(progress)) }
                if state.log != previous?.log {
                    let common = previous?.log.last.flatMap { state.log.lastIndex(of: $0) }
                    for line in common.map({ Array(state.log.dropFirst($0 + 1)) }) ?? state.log { onEvent(.log(line)) }
                }
                previous = state
                if state.finished, let exitCode = state.exitCode {
                    return CommandResult(stdout: Data(state.log.joined(separator: "\n").utf8), stderr: Data(), exitCode: exitCode)
                }
            }
            if !isRunning, Date().timeIntervalSince(started) > 15 {
                throw DeviceServiceError.unsafeRestore(L("Le moteur de restauration s’est arrêté sans résultat confirmé. Gardez l’appareil connecté et consultez le rapport d’incident."))
            }
            // Cancellation stops observing, never the independent worker.
            try await Task.sleep(nanoseconds: 500_000_000)
        }
    }

    /// Entry point of the separately signed helper; accepts only our private session directory.
    public static func runWorker(sessionPath: String) async -> Int32 {
        guard let helperDirectory else { return 2 }
        return await runWorker(sessionPath: sessionPath, root: root, engine: helperDirectory.appendingPathComponent("idevicerestore"))
    }

    /// Directory of the helper's real executable, symlinks resolved. Never derived from argv[0],
    /// which whoever launches the process chooses freely (`exec -a`).
    static var helperDirectory: URL? {
        Bundle.main.executableURL?.resolvingSymlinksInPath().deletingLastPathComponent()
    }

    // Internal injection point for process-lifetime tests with an inert engine and a temporary root.
    // The shipped helper has no command-line or environment override for either value.
    static func runWorker(sessionPath: String, root: URL, engine: URL) async -> Int32 {
        let directory = URL(fileURLWithPath: sessionPath).standardizedFileURL.resolvingSymlinksInPath()
        guard directory.deletingLastPathComponent().resolvingSymlinksInPath() == root.resolvingSymlinksInPath(),
              UUID(uuidString: directory.lastPathComponent) != nil else { return 2 }
        do {
            let lock = try HostLock(root: root, acquire: true)
            let operationLock = try HostLock(root: root == Self.root ? BackupHost.sharedLockRoot : root.appendingPathComponent("operation-lock"), acquire: true)
            defer { withExtendedLifetime((lock, operationLock)) {} }
            let activity = ProcessInfo.processInfo.beginActivity(options: [.userInitiated, .idleSystemSleepDisabled],
                reason: L("Restauration d’un iPhone ou d’un iPad en cours"))
            defer { ProcessInfo.processInfo.endActivity(activity) }
            let consumed = directory.appendingPathComponent("started")
            let fd = Darwin.open(consumed.path, O_CREAT | O_EXCL | O_WRONLY, S_IRUSR | S_IWUSR)
            guard fd >= 0 else { return 3 }
            Darwin.close(fd)
            let journal = HostJournal(directory: directory)
            try journal.save()
            do {
                let data = try readBounded(directory.appendingPathComponent("request.json"), limit: 16_384)
                let request = try JSONDecoder().decode(RestoreHostRequest.self, from: data)
                let validated = try validateArguments(request.arguments)
                guard try await FirmwareInspector.sha256(validated.url) == request.firmwareSHA256 else {
                    throw DeviceServiceError.unsafeRestore(L("Le fichier IPSW a changé avant le démarrage du moteur."))
                }
                let result = try await ProcessRunner().run(executable: engine.path, arguments: request.arguments,
                    timeout: nil, workingDirectory: directory, onLine: { journal.append($0) })
                return try journal.finish(code: result.exitCode)
            } catch {
                journal.append(error.localizedDescription)
                _ = try? journal.finish(code: 1)
                return 1
            }
        } catch { return 4 }
    }

    static func validateArguments(_ arguments: [String]) throws -> (url: URL, mode: RestoreMode) {
        let preserves = arguments.first == "--variant"
        let offset = preserves ? 2 : 1
        guard arguments.count == offset + 5, arguments[0] == (preserves ? "--variant" : "-e"),
              Array(arguments[offset..<(offset + 3)]) == ["-y", "-P", "-i"] else {
            throw DeviceServiceError.unsafeRestore(L("Options de restauration refusées."))
        }
        let url = URL(fileURLWithPath: arguments.last!)
        let mode: RestoreMode = preserves ? .preserveData : .erase
        let canonical = try RestoreValidator.arguments(ecid: arguments[offset + 3], url: url, mode: mode,
                                                       upgradeVariant: preserves ? arguments[1] : nil)
        guard canonical == arguments else { throw DeviceServiceError.unsafeRestore(L("Options non canoniques.")) }
        return (url, mode)
    }

    static func write<T: Encodable>(_ value: T, to url: URL) throws {
        let data = try JSONEncoder().encode(value)
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    static func readBounded(_ url: URL, limit: Int) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        let data = try handle.read(upToCount: limit + 1) ?? Data()
        guard data.count <= limit else { throw DeviceServiceError.invalidData(L("Le journal de restauration est trop volumineux.")) }
        return data
    }
}

final class HostLock {
    private var fd: Int32 = -1
    let wasBusy: Bool
    init(root: URL, acquire: Bool) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        fd = Darwin.open(root.appendingPathComponent("engine.lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw DeviceServiceError.unsafeRestore(L("Le verrou de restauration est inaccessible.")) }
        wasBusy = flock(fd, LOCK_EX | LOCK_NB) != 0
        if acquire && wasBusy { Darwin.close(fd); fd = -1; throw DeviceServiceError.unsafeRestore(L("Une restauration est déjà active.")) }
    }
    deinit { if fd >= 0 { if !wasBusy { flock(fd, LOCK_UN) }; Darwin.close(fd) } }
}

private final class HostJournal: @unchecked Sendable {
    let directory: URL
    private let lock = NSLock()
    private var state: RestoreHostSnapshot
    private var lastSave = Date.distantPast
    private var completionTracker = RestoreCompletionTracker()
    init(directory: URL) {
        self.directory = directory
        state = RestoreHostSnapshot(sessionID: directory.lastPathComponent, phase: L("Vérification du firmware avant écriture"),
                                    finished: false, updatedAt: Date(), log: [])
    }
    func append(_ line: String) {
        lock.lock(); defer { lock.unlock() }
        completionTracker.append(line)
        let previousPhase = state.phase
        if let event = RestoreValidator.progressEvent(line) { state.phase = event.phase; state.progress = event.progress }
        else {
            // Bound UTF-8 bytes as well as rows, including combining characters and JSON escaping.
            state.log.append(String(decoding: line.utf8.suffix(1_000), as: UTF8.self))
            if state.log.count > 150 { state.log.removeFirst(state.log.count - 150) }
        }
        if previousPhase != state.phase || Date().timeIntervalSince(lastSave) > 0.4 { try? saveLocked() }
    }
    func save() throws { lock.lock(); defer { lock.unlock() }; try saveLocked() }
    func finish(code: Int32) throws -> Int32 {
        lock.lock(); defer { lock.unlock() }
        let completion = completionTracker.completion(exitCode: code)
        let validatedCode: Int32 = code != 0 ? code : completion == .confirmed ? 0 : completion == .failed ? 1 : 2
        state.finished = true; state.exitCode = validatedCode; state.engineCompletion = completion
        state.progress = completion == .confirmed ? 1 : nil
        state.phase = completion == .confirmed ? L("Installation du système terminée") : completion == .failed ? L("La restauration n’a pas abouti") : L("Résultat de la restauration à vérifier")
        try saveLocked()
        return validatedCode
    }
    private func saveLocked() throws {
        state.updatedAt = Date()
        try RestoreHost.write(state, to: directory.appendingPathComponent("state.json"))
        lastSave = Date()
    }
}
