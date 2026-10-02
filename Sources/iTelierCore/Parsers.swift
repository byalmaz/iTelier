import Foundation
import CoreFoundation

enum DeviceParser {
    static func plist(_ data: Data) throws -> [String: Any] {
        guard let object = try PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] else {
            throw DeviceServiceError.invalidData(L("L’outil n’a pas renvoyé un dictionnaire plist valide."))
        }
        return object
    }

    static func flattened(_ object: [String: Any]) -> [String: String] {
        var values: [String: String] = [:]
        func visit(_ item: Any, path: String) {
            if let dictionary = item as? [String: Any] {
                for key in dictionary.keys.sorted() { visit(dictionary[key]!, path: path.isEmpty ? key : path + "." + key) }
            } else if let array = item as? [Any] {
                for (index, child) in array.enumerated() { visit(child, path: path + ".\(index)") }
            } else if let text = scalar(item) { values[path] = text }
        }
        visit(object, path: "")
        return values
    }

    static func scalar(_ value: Any?) -> String? {
        guard let value else { return nil }
        if let number = value as? NSNumber {
            return CFGetTypeID(number) == CFBooleanGetTypeID() ? (number.boolValue ? "true" : "false") : number.stringValue
        }
        if let string = value as? String { return string.isEmpty ? nil : string }
        if let date = value as? Date { return ISO8601DateFormatter().string(from: date) }
        if let data = value as? Data, !data.isEmpty {
            // Some battery serial numbers are returned as NUL-terminated bytes.
            if let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .controlCharacters),
               !text.isEmpty { return text }
            return data.map { String(format: "%02x", $0) }.joined()
        }
        return nil
    }

    /// ECID arguments always use unambiguous decimal notation after parsing.
    static func normalizedECID(_ text: String?) -> String? {
        guard let original = text?.trimmingCharacters(in: .whitespacesAndNewlines), !original.isEmpty else { return nil }
        let hex = original.lowercased().hasPrefix("0x")
        let digits = hex ? String(original.dropFirst(2)) : original
        let allowed = hex ? CharacterSet(charactersIn: "0123456789abcdefABCDEF") : .decimalDigits
        guard !digits.isEmpty, digits.unicodeScalars.allSatisfy({ allowed.contains($0) }),
              let value = UInt64(digits, radix: hex ? 16 : 10), value > 0 else { return nil }
        return String(value)
    }

    static func validUDID(_ text: String) -> Bool {
        text.range(of: "^[A-Za-z0-9-]{6,128}$", options: .regularExpression) != nil
    }

    static func normalDevice(id: String, data: Data, enclosureColor: String? = nil) throws -> DeviceSnapshot {
        guard validUDID(id) else { throw DeviceServiceError.invalidData(L("Identifiant USB non valide.")) }
        let plist = try plist(data)
        guard let product = scalar(plist["ProductType"]), !product.isEmpty else {
            throw DeviceServiceError.invalidData(L("Le modèle de l’appareil n’a pas pu être lu. Déverrouillez-le et autorisez cet ordinateur."))
        }
        var values = flattened(plist)
        if values["DeviceEnclosureColor"] == nil, let color = enclosureColor?.trimmingCharacters(in: .whitespacesAndNewlines),
           !color.isEmpty, color.utf8.count <= 32,
           color.unicodeScalars.allSatisfy({ CharacterSet.alphanumerics.contains($0) }) {
            values["DeviceEnclosureColor"] = color
        }
        return DeviceSnapshot(id: id, name: scalar(plist["DeviceName"]) ?? product, productType: product,
                              osVersion: scalar(plist["ProductVersion"]), buildVersion: scalar(plist["BuildVersion"]),
                              serialNumber: scalar(plist["SerialNumber"]), ecid: normalizedECID(scalar(plist["UniqueChipID"])),
                              hardwareModel: scalar(plist["HardwareModel"]), mode: .normal, values: values)
    }

    static func recoveryDevice(_ text: String) throws -> DeviceSnapshot {
        var fields: [String: String] = [:]
        for line in text.split(whereSeparator: \.isNewline) {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else { continue }
            fields[String(parts[0]).trimmingCharacters(in: .whitespaces)] = String(parts[1]).trimmingCharacters(in: .whitespaces)
        }
        guard let ecid = normalizedECID(fields["ECID"]), let product = fields["PRODUCT"],
              let modeString = fields["MODE"]?.lowercased(),
              modeString.contains("recovery") || modeString.contains("dfu") else {
            throw DeviceServiceError.invalidData(L("Les informations Recovery/DFU sont incomplètes. Mettez à jour libirecovery."))
        }
        return DeviceSnapshot(id: "ecid-" + ecid, name: fields["NAME"] ?? product,
                              productType: product, ecid: ecid, hardwareModel: fields["MODEL"],
                              mode: modeString.contains("dfu") ? .dfu : .recovery, values: fields)
    }
}

struct FirmwareManifest: Sendable {
    let version: String
    let build: String
    let supportedProductTypes: [String]
    let eraseHardwareModels: [String]
    let updateVariants: [String: String]
    var updateHardwareModels: [String] { updateVariants.keys.sorted() }

    static func parse(_ data: Data) throws -> FirmwareManifest {
        let dictionary = try DeviceParser.plist(data)
        guard let version = dictionary["ProductVersion"] as? String, !version.isEmpty,
              let build = dictionary["ProductBuildVersion"] as? String, !build.isEmpty,
              let products = dictionary["SupportedProductTypes"] as? [String], !products.isEmpty,
              let identities = dictionary["BuildIdentities"] as? [[String: Any]], !identities.isEmpty else {
            throw DeviceServiceError.invalidData(L("BuildManifest.plist est incomplet : version, modèles ou identités manquants."))
        }
        func boards(for mode: RestoreMode) -> [(board: String, variant: String)] {
            identities.compactMap { identity -> (String, String)? in
                guard let info = identity["Info"] as? [String: Any],
                      let board = info["DeviceClass"] as? String, !board.isEmpty,
                      info["RestoreBehavior"] as? String == (mode == .erase ? "Erase" : "Update"),
                      let variant = info["Variant"] as? String,
                      (mode == .erase ? ["Customer Erase Install (IPSW)", "Developer Erase Install (IPSW)"] : RestoreMode.allowedUpgradeVariants).contains(variant),
                      let components = identity["Manifest"] as? [String: Any],
                      (mode == .erase ? ["OS", "iBSS", "iBEC"] : ["OS", "iBSS", "iBEC", "RestoreRamDisk"]).allSatisfy({ name in
                          guard let component = components[name] as? [String: Any],
                                let componentInfo = component["Info"] as? [String: Any],
                                let path = componentInfo["Path"] as? String else { return false }
                          let segments = path.split(separator: "/", omittingEmptySubsequences: false)
                          return !path.isEmpty && !path.hasPrefix("/") && path.utf8.count <= 1_024 &&
                              !path.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) &&
                              segments.allSatisfy { !$0.isEmpty && $0 != "." && $0 != ".." }
                      }) else { return nil }
                return (board.lowercased(), variant)
            }
        }
        let eraseBoards = boards(for: .erase), updateBoards = boards(for: .preserveData)
        guard !eraseBoards.isEmpty || !updateBoards.isEmpty else {
            throw DeviceServiceError.invalidData(L("Ce firmware ne contient aucune identité complète de restauration ou de mise à jour."))
        }
        return FirmwareManifest(version: version, build: build,
                                supportedProductTypes: Array(Set(products)).sorted(),
                                eraseHardwareModels: Array(Set(eraseBoards.map(\.board))).sorted(),
                                updateVariants: Dictionary(updateBoards.map { ($0.board, $0.variant) }, uniquingKeysWith: { first, _ in first }))
    }
}

enum RestoreValidator {
    static func validateApproval(device: DeviceSnapshot, firmware: FirmwareInfo, approval: RestoreApproval) throws -> String {
        guard !device.isVisionPro else {
            throw DeviceServiceError.unsafeRestore(L("Pour Vision Pro, utilisez Apple Configurator avec un Developer Strap compatible."))
        }
        guard approval.mode == .erase ? approval.acknowledgedDataLoss : approval.acknowledgedPreservationRisk else {
            throw DeviceServiceError.unsafeRestore(L("Vous devez confirmer le mode de restauration et ses conséquences."))
        }
        if approval.mode == .preserveData, let issue = firmware.preservationIssue(for: device) {
            throw DeviceServiceError.unsafeRestore(issue)
        }
        guard approval.deviceID == device.id, approval.firmwareSHA256 == firmware.sha256,
              firmware.sha256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil else {
            throw DeviceServiceError.unsafeRestore(L("La confirmation ne correspond plus à l’appareil ou au fichier sélectionné."))
        }
        guard let ecid = DeviceParser.normalizedECID(device.ecid) else {
            throw DeviceServiceError.unsafeRestore(L("Restauration bloquée : l’ECID de l’appareil ne peut pas être vérifié."))
        }
        guard firmware.supports(device, mode: approval.mode) else {
            throw DeviceServiceError.unsafeRestore(L("Le firmware ne correspond pas au modèle et à la carte matérielle de cet appareil."))
        }
        return ecid
    }

    static func reconnectedDevice(original: DeviceSnapshot, ecid: String, candidates: [DeviceSnapshot]) throws -> DeviceSnapshot {
        let matches = candidates.filter { DeviceParser.normalizedECID($0.ecid) == ecid }
        guard matches.count == 1, let connected = matches.first else {
            throw DeviceServiceError.unsafeRestore(L("L’appareil confirmé doit être connecté et identifiable par un ECID unique. Rebranchez-le et recommencez."))
        }
        guard connected.productType == original.productType,
              let originalBoard = original.hardwareModel?.lowercased(),
              connected.hardwareModel?.lowercased() == originalBoard else {
            throw DeviceServiceError.unsafeRestore(L("Les informations matérielles de l’appareil ont changé depuis la confirmation."))
        }
        return connected
    }

    static func arguments(ecid: String, url: URL, mode: RestoreMode = .erase, upgradeVariant: String? = nil) throws -> [String] {
        guard let canonical = DeviceParser.normalizedECID(ecid), url.isFileURL,
              url.path.hasPrefix("/"), url.pathExtension.lowercased() == "ipsw" else {
            throw DeviceServiceError.unsafeRestore(L("Cible ou chemin IPSW non valide."))
        }
        if mode == .preserveData, !RestoreMode.allowedUpgradeVariants.contains(upgradeVariant ?? "") {
            throw DeviceServiceError.unsafeRestore(L("La variante de mise à jour n’est pas vérifiée pour cet appareil."))
        }
        let modeArguments = mode == .erase ? ["-e"] : ["--variant", upgradeVariant!]
        return modeArguments + ["-y", "-P", "-i", canonical, url.path]
    }

    /// Reject unknown versions and downgrades, including beta-to-older-beta on the same OS version.
    static func canUpdate(fromVersion current: String, build currentBuild: String, toVersion target: String, build targetBuild: String) -> Bool {
        guard [current, target].allSatisfy({ $0.range(of: "^[0-9]+(?:\\.[0-9]+)*$", options: .regularExpression) != nil }) else { return false }
        let comparison = target.compare(current, options: .numeric)
        if comparison != .orderedSame { return comparison == .orderedDescending }
        let pattern = "^[0-9]+[A-Z][0-9]+[a-z]?$"
        guard [currentBuild, targetBuild].allSatisfy({ $0.range(of: pattern, options: .regularExpression) != nil }) else { return false }
        if targetBuild == currentBuild { return true }
        let currentBeta = currentBuild.last?.isLowercase == true
        let targetBeta = targetBuild.last?.isLowercase == true
        if currentBeta != targetBeta { return !targetBeta }
        return targetBuild.compare(currentBuild, options: .numeric) == .orderedDescending
    }

    static func progressEvent(_ line: String) -> (phase: String, progress: Double)? {
        let parts = line.split(whereSeparator: \.isWhitespace)
        guard parts.count == 3, parts[0] == "progress:", let step = Int(parts[1]), step >= 0,
              let value = Double(parts[2]), value.isFinite, (0...1).contains(value) else { return nil }
        // Each upstream step has its own fraction; avoid inventing an overall ETA/progress.
        let phases = [L("Détection de l’appareil"), L("Préparation du firmware"), L("Envoi du système de fichiers"),
                      L("Vérification du système de fichiers"), L("Installation du firmware"), L("Installation du modem"),
                      L("Mise à jour des composants"), L("Envoi des images de restauration")]
        return (step < phases.count ? phases[step] : L("Étape de restauration \(step)"), value)
    }
}
