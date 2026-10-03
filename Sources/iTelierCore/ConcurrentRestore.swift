import Foundation
import IOKit

/// Identité privée et immuable du suivi ; jamais incluse dans un rapport d’incident.
public struct RestoreTarget: Codable, Sendable {
    public let ecid: String
    public let deviceID: String?
    public let name: String
    public let productType: String
    public let systemVersion: String?
    public let firmwareVersion: String
    public let firmwareBuild: String
    public let modeName: String
    public var mode: RestoreMode? { RestoreMode(rawValue: modeName) }

    public init(device: DeviceSnapshot, firmware: FirmwareInfo, mode: RestoreMode) throws {
        guard let ecid = DeviceParser.normalizedECID(device.ecid) else {
            throw DeviceServiceError.unsafeRestore(L("Restauration bloquée : l’ECID de l’appareil ne peut pas être vérifié."))
        }
        self.ecid = ecid; deviceID = device.id; name = String(device.name.prefix(200)); productType = device.productType
        systemVersion = device.osVersion; firmwareVersion = firmware.version; firmwareBuild = firmware.build
        modeName = mode.rawValue
    }

    func validate(ecid: String, mode: RestoreMode) throws {
        guard self.ecid == ecid, self.mode == mode, name.utf8.count <= 800,
              deviceID.map({ DeviceParser.validUDID($0) || $0 == "ecid-" + ecid }) != false,
              productType.range(of: "^(iPhone|iPad)[0-9]+,[0-9]+$", options: .regularExpression) != nil,
              firmwareVersion.utf8.count <= 100, firmwareBuild.utf8.count <= 100,
              (systemVersion?.utf8.count ?? 0) <= 100 else {
            throw DeviceServiceError.unsafeRestore(L("Le suivi ne correspond pas à l’appareil confirmé."))
        }
    }

    public func matches(_ device: DeviceSnapshot) -> Bool {
        DeviceParser.normalizedECID(device.ecid) == ecid && device.productType == productType
    }
}

/// Les ECID de récupération sont lus sur le Mac, puis interrogés individuellement.
/// Aucun appel sans cible ne doit sélectionner au hasard un appareil en restauration.
enum RecoveryUSBInventory {
    static func ecid(serial: String) -> String? {
        guard let range = serial.range(of: "(?:^|\\s)ECID:([0-9A-Fa-f]{1,16})(?=\\s|$)", options: .regularExpression) else { return nil }
        let field = serial[range].trimmingCharacters(in: .whitespaces)
        return DeviceParser.normalizedECID("0x" + field.dropFirst(5))
    }

    static func ecids() -> Set<String> {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOUSBHostDevice"), &iterator) == KERN_SUCCESS else { return [] }
        defer { IOObjectRelease(iterator) }
        var result = Set<String>()
        while true {
            let device = IOIteratorNext(iterator)
            guard device != 0 else { break }
            defer { IOObjectRelease(device) }
            let vendor = IORegistryEntryCreateCFProperty(device, "idVendor" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber
            guard vendor?.intValue == 0x05ac,
                  let serial = IORegistryEntryCreateCFProperty(device, "USB Serial Number" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String,
                  let ecid = ecid(serial: serial) else { continue }
            result.insert(ecid)
        }
        return result
    }
}
