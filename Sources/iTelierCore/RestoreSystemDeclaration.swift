import Foundation

/// Version indiquée par l’utilisateur lorsque l’appareil ne peut plus la communiquer.
/// Cette déclaration reste distincte d’une lecture de l’appareil et liée à sa cible.
public struct RestoreSystemDeclaration: Sendable, Equatable {
    public let version: String
    public let build: String
    private let ecid: String
    private let productType: String
    private let hardwareModel: String

    public init?(device: DeviceSnapshot, version: String, build: String) {
        let version = version.trimmingCharacters(in: .whitespacesAndNewlines)
        let build = build.trimmingCharacters(in: .whitespacesAndNewlines)
        guard device.mode != .normal,
              let ecid = DeviceParser.normalizedECID(device.ecid),
              device.productType.range(of: "^(iPhone|iPad)[0-9]+,[0-9]+$", options: .regularExpression) != nil,
              let hardwareModel = device.hardwareModel?.lowercased(),
              hardwareModel.range(of: "^[a-z0-9]{1,64}$", options: .regularExpression) != nil,
              version.utf8.count <= 50, build.utf8.count <= 50,
              version.range(of: "^[0-9]+(?:\\.[0-9]+)*$", options: .regularExpression) != nil,
              build.range(of: "^[0-9]+[A-Z][0-9]+[a-z]?$", options: .regularExpression) != nil else { return nil }
        self.version = version; self.build = build
        self.ecid = ecid; productType = device.productType; self.hardwareModel = hardwareModel
    }

    public func matches(_ device: DeviceSnapshot) -> Bool {
        DeviceParser.normalizedECID(device.ecid) == ecid
            && device.productType == productType && device.hardwareModel?.lowercased() == hardwareModel
    }
}
