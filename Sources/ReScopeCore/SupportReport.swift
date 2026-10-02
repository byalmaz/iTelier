import Foundation

public enum TrackedOperation: String, Codable, Sendable {
    case idle, deviceCheck, firmwareInspection, firmwareDownload, restoration, backup, backupRestore
}

public struct SupportContext: Codable, Sendable {
    public var operation: TrackedOperation = .idle
    public var phase: String = L("Application ouverte")
    public var deviceModel: String?
    public var systemVersion: String?
    public var firmwareVersion: String?
    public var firmwareBuild: String?
    public var restoreMode: String?

    public init(operation: TrackedOperation = .idle, phase: String = L("Application ouverte"),
                deviceModel: String? = nil, systemVersion: String? = nil,
                firmwareVersion: String? = nil, firmwareBuild: String? = nil, restoreMode: RestoreMode? = nil) {
        self.operation = operation; self.phase = String(phase.prefix(150))
        self.deviceModel = Self.filtered(deviceModel, pattern: "^(iPhone|iPad)[0-9]+,[0-9]+$")
        self.systemVersion = Self.filtered(systemVersion, pattern: "^[0-9.]{1,24}$")
        self.firmwareVersion = Self.filtered(firmwareVersion, pattern: "^[0-9.]{1,24}$")
        self.firmwareBuild = Self.filtered(firmwareBuild, pattern: "^[A-Za-z0-9]{1,32}$")
        self.restoreMode = restoreMode?.rawValue
    }
    private static func filtered(_ value: String?, pattern: String) -> String? {
        guard let value, value.range(of: pattern, options: .regularExpression) != nil else { return nil }
        return value
    }
}

public struct SupportReport: Codable, Identifiable, Sendable {
    public enum Kind: String, Codable, Sendable { case unexpectedExit, error, userFeedback }
    public let id: UUID
    public let createdAt: Date
    public let kind: Kind
    public let appVersion: String
    public let macOSVersion: String
    public let architecture: String
    public let context: SupportContext
    public let errorCode: Int?
    public let errorCategory: String?
    public let userDescription: String

    public init(kind: Kind, appVersion: String, context: SupportContext, errorCode: Int? = nil, errorCategory: String? = nil, userDescription: String = "") {
        id = UUID(); createdAt = Date(); self.kind = kind; self.appVersion = appVersion
        let os = ProcessInfo.processInfo.operatingSystemVersion
        macOSVersion = "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        #if arch(arm64)
        architecture = "arm64"
        #else
        architecture = "x86_64"
        #endif
        self.context = context; self.errorCode = errorCode; self.errorCategory = errorCategory
        self.userDescription = String(userDescription.prefix(4_000))
    }

    public func json(description: String = "") throws -> Data {
        // Explicit schema: no DeviceSnapshot, local URL, ECID, serial, device name or raw log.
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(self)) as! [String: Any]
        object["schemaVersion"] = 1
        object["userDescription"] = String(description.prefix(4_000))
        object["createdAt"] = ISO8601DateFormatter().string(from: createdAt)
        return try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }
}

private struct SafetySession: Codable {
    let startedAt: Date
    var closedNormally: Bool
    var context: SupportContext
    var restorationNeedsReview: Bool? = false
}

/// Atomic, private, bounded records. A crash is detected next launch from an unclosed session;
/// no unsafe signal handler attempts Foundation I/O during a fatal crash.
public final class SafetyJournal {
    private let directory: URL
    private let appVersion: String
    private var session: SafetySession
    public private(set) var previousInterruption: SupportReport?
    public private(set) var latestReport: SupportReport?
    public var requiresRecovery: Bool { session.restorationNeedsReview == true }

    public init(directory: URL, appVersion: String) throws {
        self.directory = directory; self.appVersion = appVersion
        session = SafetySession(startedAt: Date(), closedNormally: false, context: SupportContext())
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let sessionURL = directory.appendingPathComponent("session.json")
        if FileManager.default.fileExists(atPath: sessionURL.path) {
            let previous = try JSONDecoder().decode(SafetySession.self, from: Self.readBounded(sessionURL))
            session.restorationNeedsReview = previous.restorationNeedsReview == true
                || (!previous.closedNormally && [.restoration, .backupRestore].contains(previous.context.operation))
            if !previous.closedNormally {
                previousInterruption = SupportReport(kind: .unexpectedExit, appVersion: appVersion, context: previous.context)
            }
        }
        if let data = try? Self.readBounded(directory.appendingPathComponent("latest-report.json")) {
            latestReport = try? JSONDecoder().decode(SupportReport.self, from: data)
        }
        if let previousInterruption { try saveReport(previousInterruption) }
        try saveSession()
    }

    public func update(_ context: SupportContext) throws {
        session.context = context
        if [.restoration, .backupRestore].contains(context.operation) { session.restorationNeedsReview = true }
        try saveSession()
    }
    public func acknowledgeRecovery() throws { session.restorationNeedsReview = false; try saveSession() }
    public func completeOperation() throws {
        session.context.operation = .idle; session.context.phase = L("Application au repos")
        try saveSession()
    }
    public func closeNormally() throws { session.closedNormally = true; try saveSession() }
    @discardableResult public func recordFailure(code: Int?, category: String? = nil) throws -> SupportReport {
        let report = SupportReport(kind: .error, appVersion: appVersion, context: session.context, errorCode: code, errorCategory: category)
        try saveReport(report); return report
    }
    private func saveReport(_ report: SupportReport) throws {
        try RestoreHost.write(report, to: directory.appendingPathComponent("latest-report.json")); latestReport = report
    }
    private func saveSession() throws { try RestoreHost.write(session, to: directory.appendingPathComponent("session.json")) }
    private static func readBounded(_ url: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        let data = try handle.read(upToCount: 32_769) ?? Data()
        guard data.count <= 32_768 else { throw DeviceServiceError.invalidData(L("Le journal de sécurité est trop volumineux.")) }
        return data
    }
}
