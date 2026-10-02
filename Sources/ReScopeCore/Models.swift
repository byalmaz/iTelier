import Foundation

public enum DeviceMode: String, Codable, Sendable {
    case normal, recovery, dfu
}

public struct DeviceSnapshot: Identifiable, Codable, Sendable {
    public let id: String
    public let name: String
    public let productType: String
    public let osVersion: String?
    public let buildVersion: String?
    public let serialNumber: String?
    public let ecid: String?
    public let hardwareModel: String?
    public let mode: DeviceMode
    public let values: [String: String]

    public init(id: String, name: String, productType: String, osVersion: String? = nil,
                buildVersion: String? = nil, serialNumber: String? = nil, ecid: String? = nil,
                hardwareModel: String? = nil, mode: DeviceMode = .normal, values: [String: String] = [:]) {
        self.id = id; self.name = name; self.productType = productType
        self.osVersion = osVersion; self.buildVersion = buildVersion
        self.serialNumber = serialNumber; self.ecid = ecid; self.hardwareModel = hardwareModel
        self.mode = mode; self.values = values
    }
}

public struct ToolStatus: Identifiable, Sendable {
    public let id: String
    public let name: String
    public let path: String?
    public var isInstalled: Bool { path != nil }

    public init(id: String, name: String, path: String? = nil) {
        self.id = id; self.name = name; self.path = path
    }
}

public enum CheckStatus: String, Codable, Sendable {
    case read, verified, attention, unavailable, unsupported, readFailed, manual
}

public enum CheckCategory: String, Codable, Sendable {
    case identity, battery, components, security, connectivity
}

public enum ReferenceMatch: String, Codable, Sendable {
    case same, different, unreadable, initial
}

public struct CheckItem: Identifiable, Codable, Sendable {
    public let id: String
    public let title: String
    public let category: CheckCategory
    public let expected: String?
    public let actual: String?
    public let status: CheckStatus
    public let detail: String
    public let sensitive: Bool
    public let source: String?
    public let referenceMatch: ReferenceMatch?

    public init(id: String, title: String, category: CheckCategory, expected: String? = nil,
                actual: String? = nil, status: CheckStatus, detail: String, sensitive: Bool = false, source: String? = nil,
                referenceMatch: ReferenceMatch? = nil) {
        self.id = id; self.title = title; self.category = category; self.expected = expected
        self.actual = actual; self.status = status; self.detail = detail; self.sensitive = sensitive; self.source = source
        self.referenceMatch = referenceMatch
    }
}

public struct DiagnosticReport: Codable, Sendable {
    public let date: Date
    public let device: DeviceSnapshot
    public let items: [CheckItem]
    public let sources: [DiagnosticSourceSummary]?

    public init(date: Date = Date(), device: DeviceSnapshot, items: [CheckItem], sources: [DiagnosticSourceSummary]? = nil) {
        self.date = date; self.device = device; self.items = items; self.sources = sources
    }
}

public enum RestoreMode: String, Sendable, CaseIterable {
    case erase, preserveData
    public var title: String { self == .preserveData ? L("Conserver les données") : L("Tout effacer") }
    public static let upgradeVariant = "Customer Upgrade Install (IPSW)"
    public static let allowedUpgradeVariants = [upgradeVariant, "Developer Upgrade Install (IPSW)"]
}

public struct FirmwareInfo: Sendable {
    public let url: URL
    public let version: String
    public let build: String
    public let supportedProductTypes: [String]
    public let sizeBytes: Int64
    public let sha256: String
    /// Hardware boards for which the BuildManifest contains an explicit Erase identity.
    public let eraseHardwareModels: [String]
    public let updateVariants: [String: String]
    public var updateHardwareModels: [String] { updateVariants.keys.sorted() }

    public init(url: URL, version: String, build: String, supportedProductTypes: [String],
                sizeBytes: Int64, sha256: String, eraseHardwareModels: [String] = [], updateVariants: [String: String] = [:]) {
        self.url = url; self.version = version; self.build = build
        self.supportedProductTypes = supportedProductTypes
        self.sizeBytes = sizeBytes; self.sha256 = sha256; self.eraseHardwareModels = eraseHardwareModels
        self.updateVariants = updateVariants
    }

    public func supports(_ device: DeviceSnapshot, mode: RestoreMode = .erase) -> Bool {
        guard supportedProductTypes.contains(device.productType),
              let board = device.hardwareModel?.lowercased(), !board.isEmpty else { return false }
        let boards = mode == .erase ? eraseHardwareModels : updateHardwareModels
        return boards.contains { $0.lowercased() == board } && (mode == .erase || upgradeVariant(for: device) != nil)
    }

    public func upgradeVariant(for device: DeviceSnapshot) -> String? {
        guard let board = device.hardwareModel?.lowercased(),
              let variant = updateVariants[board], RestoreMode.allowedUpgradeVariants.contains(variant) else { return nil }
        return variant
    }

    public func preservationIssue(for device: DeviceSnapshot) -> String? {
        guard supports(device, mode: .preserveData) else { return L("Cet IPSW ne permet pas de conserver les données de cet appareil.") }
        guard device.mode == .normal, let currentVersion = device.osVersion, let currentBuild = device.buildVersion else {
            return L("Déverrouillez l’appareil en mode normal pour vérifier sa version avant de conserver les données.")
        }
        guard RestoreValidator.canUpdate(fromVersion: currentVersion, build: currentBuild, toVersion: version, build: build) else {
            return L("La conservation des données exige la même version ou une version plus récente. Un retour en arrière est bloqué.")
        }
        return nil
    }
}

public struct RestoreApproval: Sendable {
    public let deviceID: String
    public let firmwareSHA256: String
    public let acknowledgedDataLoss: Bool
    public let mode: RestoreMode
    public let acknowledgedPreservationRisk: Bool

    public init(deviceID: String, firmwareSHA256: String, acknowledgedDataLoss: Bool,
                mode: RestoreMode = .erase, acknowledgedPreservationRisk: Bool = false) {
        self.deviceID = deviceID; self.firmwareSHA256 = firmwareSHA256
        self.acknowledgedDataLoss = acknowledgedDataLoss
        self.mode = mode; self.acknowledgedPreservationRisk = acknowledgedPreservationRisk
    }
}

public enum RestoreEvent: Sendable {
    case log(String), phase(String), progress(Double), finished
}

public enum DeviceServiceError: LocalizedError, Sendable {
    case missingTool(String)
    case commandFailed(String, Int32, String)
    case timedOut(String)
    case outputTooLarge(String)
    case invalidData(String)
    case unsafeRestore(String)

    public var errorDescription: String? {
        switch self {
        case .missingTool(let name): return L("L’outil \(name) est introuvable. Consultez les instructions d’installation.")
        case .commandFailed(let name, let code, let message):
            return L("\(name) a échoué (\(code)). \(message)")
        case .timedOut(let name): return L("\(name) n’a pas répondu dans le délai prévu.")
        case .outputTooLarge(let name): return L("La sortie de \(name) dépasse la limite autorisée.")
        case .invalidData(let message), .unsafeRestore(let message): return message
        }
    }
}
