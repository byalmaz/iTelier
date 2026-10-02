import Foundation

/// Observation du déverrouillage, confirmée sur l’appareil par son utilisateur.
/// Aucun résultat fonctionnel n’est déduit des identifiants des composants.
public enum FaceIDTestResult: String, Sendable {
    case unlocked, failed, notConfigured
}

public struct FaceIDComponentReading: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let identifier: String?
    public let status: CheckStatus
    public let source: String?
}

/// Session locale au panneau de test ; elle ne modifie pas le rapport diagnostique.
public struct FaceIDTest: Sendable {
    public enum Phase: Sendable { case ready, testing, completed }

    public let device: DeviceSnapshot
    public let components: [FaceIDComponentReading]
    public private(set) var phase: Phase = .ready
    public private(set) var result: FaceIDTestResult?

    public init(report: DiagnosticReport) {
        device = report.device
        components = [
            ("ir-camera-serial", "Caméra infrarouge"),
            ("projector-serial", "Projecteur de points"),
            ("proximity-sensor-serial", "Capteur de proximité")
        ].map { id, title in
            let items = report.items.filter { $0.id == id }
            let identifiers = Set(items.compactMap { item -> String? in
                guard item.status == .read || item.status == .verified else { return nil }
                return DiagnosticReading.serial(item.actual)
            })
            let conflicted = identifiers.count > 1 || items.contains { $0.status == .attention }
            let identifier = conflicted ? nil : identifiers.first
            let status: CheckStatus
            if conflicted { status = .attention }
            else if identifier != nil { status = .read }
            else if items.contains(where: { $0.status == .readFailed }) { status = .readFailed }
            else if !items.isEmpty && items.allSatisfy({ $0.status == .unsupported }) { status = .unsupported }
            else { status = .unavailable }
            return FaceIDComponentReading(id: id, title: title, identifier: identifier, status: status,
                source: items.compactMap(\.source).filter { !$0.isEmpty }.joined(separator: " · "))
        }
    }

    public static func supportsGuidedTest(_ device: DeviceSnapshot) -> Bool {
        device.mode == .normal && (device.productType.hasPrefix("iPhone") || device.productType.hasPrefix("iPad"))
    }

    /// Un changement d’appareil, de mode ou d’identité invalide la session en cours.
    public func matches(_ current: DeviceSnapshot?) -> Bool {
        guard let current, Self.supportsGuidedTest(current), current.id == device.id,
              current.productType == device.productType else { return false }
        if let expectedECID = DeviceParser.normalizedECID(device.ecid) {
            return DeviceParser.normalizedECID(current.ecid) == expectedECID
        }
        return true
    }

    @discardableResult public mutating func begin(on current: DeviceSnapshot?) -> Bool {
        guard matches(current) else { return false }
        result = nil
        phase = .testing
        return true
    }

    @discardableResult public mutating func confirm(_ observation: FaceIDTestResult, on current: DeviceSnapshot?) -> Bool {
        guard phase == .testing, matches(current) else { return false }
        result = observation
        phase = .completed
        return true
    }
}
