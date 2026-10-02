import Foundation
import IOKit

/// Describes a failed connection without storing USB serials or raw command output.
public enum DeviceConnectionIssue: String, Sendable {
    case noUSB, usbVisible, trustRequired, locked, toolsMissing, serviceUnavailable, unknown

    public var title: String {
        switch self {
        case .noUSB: return L("Connectez votre appareil Apple")
        case .usbVisible: return L("Votre appareil est presque prêt")
        case .trustRequired: return L("Faites confiance à ce Mac")
        case .locked: return L("Déverrouillez votre appareil")
        case .toolsMissing: return L("iTelier a besoin d’être réinstallé")
        case .serviceUnavailable: return L("La connexion a été interrompue")
        case .unknown: return L("Connexion à vérifier")
        }
    }

    public var message: String {
        switch self {
        case .noUSB:
            return L("Reliez votre appareil à ce Mac et déverrouillez-le. Si un message apparaît, autorisez la connexion pour continuer.")
        case .usbVisible:
            return L("Déverrouillez votre appareil et acceptez « Faire confiance » si ce message apparaît. iTelier se connectera automatiquement.")
        case .trustRequired:
            return L("Sur votre appareil, touchez « Faire confiance », puis saisissez votre code. iTelier s’occupe de la suite.")
        case .locked:
            return L("Déverrouillez votre appareil pour permettre à iTelier de s’y connecter.")
        case .toolsMissing:
            return L("Un élément nécessaire à la connexion est manquant. Réinstallez iTelier, puis réessayez.")
        case .serviceUnavailable:
            return L("Débranchez votre appareil, puis reconnectez-le à ce Mac. Si le problème persiste, consultez l’aide dans Configuration.")
        case .unknown:
            return L("Vérifiez que votre appareil est connecté et déverrouillé, puis réessayez. Vous pouvez aussi essayer un autre câble ou un autre port.")
        }
    }

    public static func inspect(error: Error? = nil) -> Self {
        classify(presence: USBDevicePresence.read(), error: error)
    }

    static func classify(presence: USBDevicePresence, error: Error?) -> Self {
        if let error = error as? DeviceServiceError {
            switch error {
            case .missingTool: return .toolsMissing
            case .commandFailed(let tool, _, let output):
                let text = output.lowercased()
                if text.contains("passwordprotected") || text.contains("device is locked") { return .locked }
                if ["pairingdialogresponsepending", "userdeniedpairing", "invalidhostid", "trust dialog", "not paired"].contains(where: text.contains) {
                    return .trustRequired
                }
                if tool == "idevice_id" { return .serviceUnavailable }
            case .timedOut: return .serviceUnavailable
            default: break
            }
        }
        switch presence {
        case .present: return .usbVisible
        case .absent: return .noUSB
        case .unknown: return .unknown
        }
    }
}

enum USBDevicePresence {
    case present, absent, unknown

    static func isMobileDevice(vendor: Int?, name: String) -> Bool {
        guard vendor == 0x05ac else { return false }
        let name = name.lowercased()
        return ["iphone", "ipad", "ipod", "vision", "realitydevice", "apple mobile", "recovery", "dfu"].contains(where: name.contains)
    }

    static func read() -> Self {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOUSBHostDevice"), &iterator) == KERN_SUCCESS else { return .unknown }
        defer { IOObjectRelease(iterator) }
        while true {
            let device = IOIteratorNext(iterator)
            guard device != 0 else { break }
            defer { IOObjectRelease(device) }
            let vendor = IORegistryEntryCreateCFProperty(device, "idVendor" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? NSNumber
            let name = IORegistryEntryCreateCFProperty(device, "USB Product Name" as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? String
            if isMobileDevice(vendor: vendor?.intValue, name: name ?? "") { return .present }
        }
        return .absent
    }
}
