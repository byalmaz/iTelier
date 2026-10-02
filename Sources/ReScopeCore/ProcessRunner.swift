import Foundation
import Darwin

struct CommandResult: Sendable {
    let stdout: Data
    let stderr: Data
    let exitCode: Int32
}

enum ToolResolver {
    static let names = ["idevice_id", "ideviceinfo", "idevicediagnostics", "irecovery", "idevicerestore", "idevicebackup2"]

    static func resolve(_ name: String, bundleURL: URL = Bundle.main.bundleURL,
                        environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        guard names.contains(name) else { return nil }
        // Ignore relative and empty PATH components; a firmware file cannot change executable lookup.
        let inherited = (environment["PATH"] ?? "")
            .split(separator: ":").map(String.init).filter { $0.hasPrefix("/") }
        var seen = Set<String>()
        let bundled = bundleURL.pathExtension == "app"
            ? [bundleURL.appendingPathComponent("Contents/Helpers", isDirectory: true).path] : []
        for directory in bundled + ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"] + inherited {
            guard seen.insert(directory).inserted else { continue }
            let path = URL(fileURLWithPath: directory, isDirectory: true).appendingPathComponent(name).path
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory),
               !isDirectory.boolValue, FileManager.default.isExecutableFile(atPath: path) { return path }
        }
        return nil
    }
}

/// A process receives arguments directly, never a command interpreted by a shell.
/// Both pipes are drained concurrently and memory is bounded even during a long restore.
struct ProcessRunner: Sendable {
    func run(executable: String, arguments: [String], timeout: TimeInterval? = 15,
             outputLimit: Int = 2 * 1_024 * 1_024,
             workingDirectory: URL? = nil,
             environmentOverrides: [String: String] = [:],
             input: Data? = nil,
             onLine: (@Sendable (String) -> Void)? = nil) async throws -> CommandResult {
        // Secrets go through standard input: `ps eww` shows a process's initial environment
        // to every program of the same user. The bound keeps the write within a pipe buffer.
        if let input, input.count > 4_096 { throw DeviceServiceError.invalidData(L("Les données transmises à l’outil sont trop volumineuses.")) }
        let control = ProcessControl()
        return try await withTaskCancellationHandler(operation: {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                DispatchQueue.global(qos: .userInitiated).async {
                    let process = Process()
                    process.executableURL = URL(fileURLWithPath: executable)
                    process.arguments = arguments
                    let inputPipe = input.map { _ in Pipe() }
                    process.standardInput = inputPipe ?? FileHandle.nullDevice
                    if let workingDirectory { process.currentDirectoryURL = workingDirectory }
                    var environment = ProcessInfo.processInfo.environment
                    // Prevent the desktop app's inherited loader overrides from affecting external tools.
                    for key in environment.keys where key.hasPrefix("DYLD_") { environment.removeValue(forKey: key) }
                    environment.removeValue(forKey: "BACKUP_PASSWORD")
                    environment.removeValue(forKey: "BACKUP_PASSWORD_NEW")
                    environment.merge(environmentOverrides) { _, new in new }
                    environment["LC_ALL"] = "C"
                    process.environment = environment
                    let out = Pipe(), err = Pipe()
                    process.standardOutput = out; process.standardError = err
                    control.assign(process)
                    do {
                        try control.checkBeforeLaunch()
                        if let inputPipe, let input {
                            // Buffered before launch while this process still holds the read end:
                            // no blocking and no SIGPIPE, even if the child exits immediately.
                            try inputPipe.fileHandleForWriting.write(contentsOf: input)
                            try inputPipe.fileHandleForWriting.close()
                        }
                        try process.run()
                        try? inputPipe?.fileHandleForReading.close()
                        control.didLaunch()
                        // Parent write ends must close so readers receive EOF after the child exits.
                        try? out.fileHandleForWriting.close()
                        try? err.fileHandleForWriting.close()
                        let timer: DispatchSourceTimer?
                        if let timeout {
                            let source = DispatchSource.makeTimerSource(queue: .global())
                            source.schedule(deadline: .now() + timeout)
                            source.setEventHandler { control.stop(reason: .timedOut(URL(fileURLWithPath: executable).lastPathComponent)) }
                            source.resume(); timer = source
                        } else { timer = nil }
                        let group = DispatchGroup()
                        let capture = ProcessCapture()
                        for (handle, isError) in [(out.fileHandleForReading, false), (err.fileHandleForReading, true)] {
                            group.enter()
                            DispatchQueue.global(qos: .utility).async {
                                let bytes = Self.readPipe(handle, process: process, limit: outputLimit,
                                                          control: control, onLine: onLine,
                                                          boundedCommand: timeout != nil)
                                capture.set(bytes, isError: isError)
                                group.leave()
                            }
                        }
                        process.waitUntilExit()
                        timer?.cancel()
                        group.wait()
                        control.didExit()
                        if let error = control.error { continuation.resume(throwing: error) }
                        else { continuation.resume(returning: capture.result(exitCode: process.terminationStatus)) }
                    } catch {
                        try? out.fileHandleForReading.close(); try? err.fileHandleForReading.close()
                        try? out.fileHandleForWriting.close(); try? err.fileHandleForWriting.close()
                        try? inputPipe?.fileHandleForWriting.close(); try? inputPipe?.fileHandleForReading.close()
                        continuation.resume(throwing: error)
                    }
                }
            }
        }, onCancel: { control.cancel() })
    }

    private static func readPipe(_ handle: FileHandle, process: Process, limit: Int,
                                 control: ProcessControl, onLine: (@Sendable (String) -> Void)?,
                                 boundedCommand: Bool) -> Data {
        defer { try? handle.close() }
        var captured = Data(), pending = Data()
        var buffer = [UInt8](repeating: 0, count: 16_384)
        let fd = handle.fileDescriptor
        while true {
            var descriptor = pollfd(fd: fd, events: Int16(POLLIN | POLLHUP), revents: 0)
            let ready = Darwin.poll(&descriptor, 1, 200)
            if ready < 0 { if errno == EINTR { continue }; break }
            if ready == 0 { if !process.isRunning { break }; continue }
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count <= 0 { if count < 0 && errno == EINTR { continue }; break }
            let data = Data(buffer.prefix(count))
            if captured.count + data.count <= limit { captured.append(data) }
            else if boundedCommand {
                control.stop(reason: .outputTooLarge(process.executableURL?.lastPathComponent ?? "outil"))
            } else {
                // The return value is a bounded diagnostic tail; events still stream in full.
                captured.append(data)
                if captured.count > limit { captured.removeFirst(captured.count - limit) }
            }
            if let onLine {
                pending.append(data)
                while let index = pending.firstIndex(where: { $0 == 10 || $0 == 13 }) {
                    let line = String(decoding: pending[..<index], as: UTF8.self)
                    pending.removeSubrange(...index)
                    if !line.isEmpty { onLine(line) }
                }
                // Bound even a malformed stream containing no newline.
                if pending.count > 65_536 {
                    onLine(String(decoding: pending, as: UTF8.self)); pending.removeAll(keepingCapacity: true)
                }
            }
        }
        if let onLine, !pending.isEmpty { onLine(String(decoding: pending, as: UTF8.self)) }
        return captured
    }
}

private final class ProcessCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var stdout = Data(), stderr = Data()
    func set(_ data: Data, isError: Bool) {
        lock.lock(); defer { lock.unlock() }
        if isError { stderr = data } else { stdout = data }
    }
    func result(exitCode: Int32) -> CommandResult {
        lock.lock(); defer { lock.unlock() }
        return CommandResult(stdout: stdout, stderr: stderr, exitCode: exitCode)
    }
}

private final class ProcessControl: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var failure: Error?
    private var launched = false
    private var exited = false

    var error: Error? { lock.lock(); defer { lock.unlock() }; return failure }
    func assign(_ process: Process) { lock.lock(); self.process = process; lock.unlock() }
    func checkBeforeLaunch() throws { if let error { throw error } }
    func didLaunch() {
        lock.lock(); launched = true; let stopped = failure != nil; lock.unlock()
        if stopped { terminate() }
    }
    func didExit() { lock.lock(); exited = true; lock.unlock() }
    func cancel() { stop(error: CancellationError()) }
    func stop(reason: DeviceServiceError) { stop(error: reason) }
    private func stop(error: Error) {
        lock.lock()
        if failure == nil && !exited { failure = error }
        let shouldStop = launched && !exited
        lock.unlock()
        if shouldStop { terminate() }
    }
    private func terminate() {
        lock.lock(); let running = process; lock.unlock()
        guard let running, running.isRunning else { return }
        running.terminate()
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
            if running.isRunning { _ = Darwin.kill(running.processIdentifier, SIGKILL) }
        }
    }
}
