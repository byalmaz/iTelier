import Foundation
import Darwin

public struct FirmwareDownloadProgress: Sendable {
    public let bytesWritten: Int64
    public let totalBytes: Int64?
    public var fraction: Double? {
        guard let totalBytes, totalBytes > 0 else { return nil }
        return min(1, max(0, Double(bytesWritten) / Double(totalBytes)))
    }
    public init(bytesWritten: Int64, totalBytes: Int64?) { self.bytesWritten = bytesWritten; self.totalBytes = totalBytes }
}

/// Controls one transfer in this session. Suspension retains URLSession's partial file.
/// It is deliberately separate from cancellation, which discards the partial download.
public final class FirmwareDownloadControl: @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionDownloadTask?
    private var paused = false
    private var finished = false

    public init() {}

    @discardableResult public func setPaused(_ value: Bool) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !finished, task?.state != .canceling, task?.state != .completed else { return false }
        guard paused != value else { return true }
        paused = value
        if let task {
            if value { task.suspend() } else { task.resume() }
        }
        return true
    }

    func start(_ task: URLSessionDownloadTask) {
        lock.lock(); defer { lock.unlock() }
        guard !finished else { task.cancel(); return }
        self.task = task
        if !paused { task.resume() }
    }

    func finish() {
        lock.lock(); defer { lock.unlock() }
        finished = true
        task = nil
        paused = false
    }
}

public struct FirmwareDownloader: Sendable {
    private let configurationFactory: @Sendable () -> URLSessionConfiguration
    public init() { configurationFactory = { .ephemeral } }
    init(configurationFactory: @escaping @Sendable () -> URLSessionConfiguration) { self.configurationFactory = configurationFactory }
    public static func isAllowedDownloadURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased(),
              url.user == nil, url.password == nil, url.fragment == nil,
              url.port == nil || url.port == 443,
              host.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789.-").contains($0) }) else { return false }
        return ["apple.com", "cdn-apple.com"].contains { host == $0 || host.hasSuffix("." + $0) }
    }
    public func download(_ firmware: FirmwareRelease, to directory: URL,
                         control: FirmwareDownloadControl = FirmwareDownloadControl(),
                         onTransferCompleted: @escaping @Sendable () -> Void = {},
                         onProgress: @escaping @Sendable (FirmwareDownloadProgress) -> Void) async throws -> URL {
        defer { control.finish() }
        guard Self.isAllowedDownloadURL(firmware.url), firmware.url.pathExtension.lowercased() == "ipsw" else {
            throw FirmwareTransferError.untrustedURL
        }
        guard firmware.fileSize > 0 else { throw FirmwareTransferError.invalidMetadata }
        let checksum = try FirmwareRelease.checksum(firmware.sha256, length: 64)
        let legacyChecksum = try FirmwareRelease.checksum(firmware.sha1, length: 40)
        guard directory.isFileURL else { throw FirmwareTransferError.invalidDestination }
        let scope = directory.startAccessingSecurityScopedResource()
        defer { if scope { directory.stopAccessingSecurityScopedResource() } }
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: directory.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw FirmwareTransferError.invalidDestination
        }
        let volume = try? directory.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey, .volumeAvailableCapacityKey])
        // Some mounted filesystems report important-usage capacity as zero despite available space.
        let capacity = volume?.volumeAvailableCapacityForImportantUsage.flatMap { $0 > 0 ? $0 : nil }
            ?? volume?.volumeAvailableCapacity.map(Int64.init)
        if let capacity, capacity >= 0, capacity < firmware.fileSize { throw FirmwareTransferError.insufficientSpace }
        // A unique hidden staging directory on the destination volume allows an atomic final rename.
        let staging = directory.appendingPathComponent(".rescope-download-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false,
                                                 attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: staging) }
        let stageURL = staging.appendingPathComponent("firmware.ipsw")
        let delegate = FirmwareDownloadDelegate(stageURL: stageURL, expectedSize: firmware.fileSize, control: control, onProgress: onProgress)
        let configuration = configurationFactory()
        configuration.httpShouldSetCookies = false; configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 60
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: firmware.url); request.setValue("identity", forHTTPHeaderField: "Accept-Encoding")
        try await withTaskCancellationHandler(operation: {
            try Task.checkCancellation()
            try await delegate.start(session: session, request: request)
        }, onCancel: { delegate.cancel() })
        control.finish()
        try Task.checkCancellation()
        onTransferCompleted()
        try Self.validateSize(at: stageURL, expected: firmware.fileSize)
        if let checksum {
            guard try await FirmwareInspector.sha256(stageURL) == checksum else { throw FirmwareTransferError.checksumMismatch }
        } else if let legacyChecksum {
            // Les anciens catalogues fournissent parfois uniquement une empreinte SHA-1.
            guard try await FirmwareInspector.sha1(stageURL) == legacyChecksum else { throw FirmwareTransferError.checksumMismatch }
        } else {
            // Sans empreinte publiée, le manifeste seul ne prouve pas l’intégrité des autres membres.
            let fingerprint = try FileFingerprint.read(stageURL)
            let archive = try await ProcessRunner().run(executable: "/usr/bin/unzip",
                arguments: ["-tqq", stageURL.path], timeout: 600, outputLimit: 1_048_576)
            guard archive.exitCode == 0, try FileFingerprint.read(stageURL) == fingerprint else {
                throw DeviceServiceError.invalidData(L("Le fichier IPSW est endommagé ou incomplet. Le téléchargement a été supprimé."))
            }
        }
        try Task.checkCancellation()
        return try Self.commit(stageURL: stageURL, directory: directory, suggestedName: firmware.url.lastPathComponent)
    }
    static func validateSize(at url: URL, expected: Int64) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.size] as? NSNumber)?.int64Value == expected else { throw FirmwareTransferError.incompleteDownload }
    }
    static func commit(stageURL: URL, directory: URL, suggestedName: String) throws -> URL {
        let raw = URL(fileURLWithPath: suggestedName).deletingPathExtension().lastPathComponent
        let safe = String(raw.unicodeScalars.map { CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789,._-").contains($0) ? Character(String($0)) : "_" }.prefix(160))
        let base = safe.isEmpty || safe == "." || safe == ".." ? "Firmware" : safe
        // RENAME_EXCL makes the final rename atomically refuse replacement, even if another
        // download creates the destination between a filesystem check and this operation.
        for attempt in 0..<10 {
            let suffix = attempt == 0 ? "" : "-" + UUID().uuidString
            let destination = directory.appendingPathComponent(base + suffix + ".ipsw")
            if Darwin.renamex_np(stageURL.path, destination.path, UInt32(RENAME_EXCL)) == 0 { return destination }
            let code = errno
            if code == EEXIST { continue }
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(code), userInfo: [NSFilePathErrorKey: destination.path])
        }
        throw FirmwareTransferError.invalidDestination
    }
}

/// Delegate callbacks are serialized by URLSession. The lock protects cancellation and the continuation.
final class FirmwareDownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private let stageURL: URL
    private let expectedSize: Int64
    private let control: FirmwareDownloadControl
    private let onProgress: @Sendable (FirmwareDownloadProgress) -> Void
    private var task: URLSessionDownloadTask?
    private var continuation: CheckedContinuation<Void, Error>?
    private var failure: Error?
    private var staged = false

    init(stageURL: URL, expectedSize: Int64, control: FirmwareDownloadControl, onProgress: @escaping @Sendable (FirmwareDownloadProgress) -> Void) {
        self.stageURL = stageURL; self.expectedSize = expectedSize; self.control = control; self.onProgress = onProgress
    }
    func start(session: URLSession, request: URLRequest) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            lock.lock()
            if let failure { lock.unlock(); continuation.resume(throwing: failure); return }
            self.continuation = continuation
            let transfer = session.downloadTask(with: request); task = transfer
            lock.unlock()
            control.start(transfer)
        }
    }
    func cancel() { stop(CancellationError()) }
    private func stop(_ error: Error) {
        lock.lock(); if failure == nil { failure = error }; let current = task; lock.unlock()
        current?.cancel()
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let url = request.url, FirmwareDownloader.isAllowedDownloadURL(url) else {
            stop(FirmwareTransferError.untrustedURL); completionHandler(nil); return
        }
        completionHandler(request)
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesWritten > expectedSize { stop(FirmwareTransferError.incompleteDownload); return }
        let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : expectedSize
        onProgress(FirmwareDownloadProgress(bytesWritten: totalBytesWritten, totalBytes: total))
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            guard let response = downloadTask.response as? HTTPURLResponse,
                  let url = response.url, FirmwareDownloader.isAllowedDownloadURL(url) else { throw FirmwareTransferError.untrustedURL }
            guard response.statusCode == 200 else { throw FirmwareTransferError.httpStatus(response.statusCode) }
            try FirmwareDownloader.validateSize(at: location, expected: expectedSize)
            lock.lock(); let cancelled = failure != nil; lock.unlock()
            guard !cancelled else { return }
            // Foundation removes location as soon as this callback returns: retain it in staging now.
            try FileManager.default.moveItem(at: location, to: stageURL)
            lock.lock(); staged = true; lock.unlock()
        } catch { stop(error) }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let resultError = failure ?? error ?? (staged ? nil : FirmwareTransferError.incompleteDownload)
        let continuation = self.continuation; self.continuation = nil
        lock.unlock()
        if let resultError { continuation?.resume(throwing: resultError) }
        else { continuation?.resume(returning: ()) }
    }
}
