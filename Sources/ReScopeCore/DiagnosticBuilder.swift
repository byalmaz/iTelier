import Foundation

enum DiagnosticBuilder {
    static func report(device: DeviceSnapshot, battery legacyBattery: [String: String] = [:],
                       disk legacyDisk: [String: String] = [:], gauge legacyGauge: [String: String] = [:],
                       registry legacyRegistry: [String: String] = [:], readings: [DiagnosticReading] = []) -> DiagnosticReport {
        let base = device.values
        let battery = readings.first { $0.id == "battery" }?.values ?? legacyBattery
        let disk = readings.first { $0.id == "disk" }?.values ?? legacyDisk
        let gauge = readings.first { $0.id == "gauge" }?.values ?? legacyGauge
        let registry = readings.first { $0.id == "registry" }?.values ?? legacyRegistry
        let baseReading = DiagnosticReading(id: "base", title: L("Informations générales · lockdown"), values: base, status: .read,
            detail: L("Identité relue sur l’appareil sélectionné."))
        let allReadings = [baseReading] + readings
        func relevant(_ id: String) -> [DiagnosticReading] {
            if id == "storage" { return readings.filter { $0.id == "disk" } }
            if id.hasPrefix("battery-") { return readings.filter { ["battery", "gauge", "registry"].contains($0.id) } }
            return [baseReading]
        }
        func missing(_ candidates: [DiagnosticReading]) -> (CheckStatus, String) {
            if candidates.contains(where: { $0.status == .readFailed }) {
                return (.readFailed, L("Au moins une source nécessaire a échoué. Vérifiez la connexion, déverrouillez l’appareil et relancez le Check. ") + candidates.filter { $0.status == .readFailed }.map { $0.title + " : " + $0.detail }.joined(separator: " "))
            }
            if !candidates.isEmpty && candidates.allSatisfy({ $0.status == .unsupported }) {
                return (.unsupported, candidates.map { $0.title + " : " + $0.detail }.joined(separator: " "))
            }
            let unsupported = candidates.filter { $0.status == .unsupported }.map { $0.title + " : " + $0.detail }.joined(separator: " ")
            return (.unavailable, L("Les sources consultées n’exposent pas ce champ. Cela ne constitue pas un défaut de la pièce. ") + unsupported)
        }
        let batterySources = [gauge, registry, battery]
        func lookup(_ keys: [String], sources: [[String: String]]) -> String? {
            for source in sources {
                for key in keys {
                    if let value = source[key] { return value }
                    // Diagnostics nest values under GasGauge/IORegistry. Match a complete terminal key.
                    if let match = source.keys.sorted().first(where: { $0.hasSuffix("." + key) }),
                       let value = source[match] { return value }
                }
            }
            return nil
        }
        var items: [CheckItem] = []
        func read(_ id: String, _ title: String, _ category: CheckCategory, _ value: String?,
                  detail: String = L("Valeur lue sur l’appareil. Aucune référence d’usine indépendante n’est disponible."),
                  sensitive: Bool = false, status: CheckStatus? = nil) {
            let sources = relevant(id)
            let absent = missing(sources)
            items.append(CheckItem(id: id, title: title, category: category, actual: value,
                                   status: value == nil ? absent.0 : (status ?? .read),
                                   detail: value == nil ? absent.1 : detail,
                                   sensitive: sensitive, source: sources.map(\.title).joined(separator: " · ")))
        }
        func serial(_ id: String, _ title: String, _ category: CheckCategory, mappings: [(String, [String])], note: String = "") {
            var candidates: [DiagnosticReading] = []
            var matches: [(String, String)] = []
            for (sourceID, keys) in mappings {
                for source in allReadings where source.id == sourceID || (sourceID == "camera" && source.id.hasPrefix("camera-")) {
                    candidates.append(source)
                    guard source.status == .read else { continue }
                    for key in keys {
                        if let value = DiagnosticReading.serial(source.values[key]) {
                            matches.append((value, source.title + " → " + key)); break
                        }
                    }
                }
            }
            let unique = Set(matches.map { $0.0 })
            if unique.count > 1 {
                items.append(CheckItem(id: id, title: title, category: category, status: .attention,
                    detail: L("Les sources renvoient des identifiants différents. Aucune valeur n’est retenue automatiquement ; cela ne prouve pas un remplacement."),
                    sensitive: true, source: matches.map { $0.1 }.joined(separator: " · ")))
            } else if let match = matches.first {
                items.append(CheckItem(id: id, title: title, category: category, actual: match.0, status: .read,
                    detail: L("Identifiant déclaré par l’appareil. Aucune référence d’usine indépendante n’est disponible. ") + note,
                    sensitive: true, source: match.1))
            } else {
                let absent = missing(candidates)
                items.append(CheckItem(id: id, title: title, category: category, status: absent.0, detail: absent.1,
                    sensitive: true, source: candidates.map(\.title).joined(separator: " · ")))
            }
        }

        func manual(_ id: String, _ title: String, _ category: CheckCategory, _ detail: String) {
            items.append(CheckItem(id: id, title: title, category: category, status: .manual, detail: detail))
        }

        read("model", L("Modèle"), .identity, device.productType)
        read("hardware", L("Carte matérielle"), .identity, device.hardwareModel)
        read("os", L("Version iOS / iPadOS"), .identity, device.osVersion)
        read("build", L("Build du système"), .identity, device.buildVersion)
        read("serial", L("Numéro de série"), .identity, device.serialNumber, sensitive: true)
        read("ecid", "ECID", .identity, device.ecid, sensitive: true)
        read("model-number", L("Référence commerciale"), .identity, lookup(["ModelNumber"], sources: [base]))
        read("region", L("Région commerciale"), .identity, lookup(["RegionInfo"], sources: [base]))
        read("color", L("Couleur déclarée"), .identity, lookup(["DeviceColor", "DeviceEnclosureColor"], sources: [base]))
        let total = lookup(["TotalDiskCapacity"], sources: [disk])
        let totalBytes = total.flatMap(Int64.init)
        read("storage", L("Capacité de stockage"), .identity,
             totalBytes.flatMap { $0 > 0 ? ByteCountFormatter.string(fromByteCount: $0, countStyle: .decimal) : nil },
             detail: L("Capacité lue dans le domaine com.apple.disk_usage ; elle peut différer de la capacité commerciale."))

        let charge = lookup(["BatteryCurrentCapacity", "CurrentCapacity", "RelativeSOC"], sources: [battery, gauge, registry])
        let chargePercent = charge.flatMap(Double.init).flatMap { (0...100).contains($0) ? "\(Int($0)) %" : nil }
        read("battery-charge", L("Charge actuelle"), .battery, chargePercent,
             detail: L("Niveau de charge instantané. Une charge à 0 % n’indique pas une capacité maximale à 0 %."))
        read("battery-cycles", L("Cycles de charge"), .battery,
             lookup(["CycleCount", "BatteryCycleCount"], sources: batterySources),
             detail: L("Compteur déclaré par la batterie lorsqu’il est exposé ; il ne prouve pas son authenticité."))
        serial("battery-serial", L("Série de la batterie"), .battery, mappings: [
            ("registry", ["IORegistry.Serial", "IORegistry.BatterySerialNumber", "IORegistry.SerialNumber", "IORegistry.BatteryData.Serial"]),
            ("gauge", ["GasGauge.BatterySerialNumber", "GasGauge.SerialNumber"]),
            ("battery", ["BatterySerialNumber"]), ("gestalt", ["MobileGestalt.BatterySerialNumber"])
        ])

        let nominal = lookup(["NominalChargeCapacity", "AppleRawMaxCapacity", "FullChargeCapacity"], sources: [gauge, registry]).flatMap(Double.init)
        let design = lookup(["DesignCapacity"], sources: [gauge, registry]).flatMap(Double.init)
        let officialPercent = lookup(["MaximumCapacityPercent"], sources: batterySources).flatMap(Double.init)
        if let officialPercent, (1...100).contains(officialPercent) {
            read("battery-health", L("Capacité maximale déclarée"), .battery, "\(Int(officialPercent)) %",
                 detail: L("Pourcentage déclaré par l’interface de diagnostic. À comparer avec Réglages > Batterie sur l’appareil.") +
                    (officialPercent < 80 ? L(" Sous le seuil indicatif de 80 %, faites examiner la batterie. Ce signal n’est pas une certification de son état.") : ""),
                 status: officialPercent < 80 ? .attention : .read)
        } else if let nominal, let design, nominal.isFinite, design.isFinite,
                  nominal > 0, design > 0, nominal / design <= 1.5 {
            let percent = nominal / design * 100
            read("battery-health", L("Capacité maximale estimée"), .battery,
                 "\(Int(percent.rounded(.down))) %",
                 detail: L("Estimation à partir de NominalChargeCapacity / DesignCapacity. Ce calcul ne remplace pas l’état de santé affiché par iOS.") +
                    (percent < 80 ? L(" Sous le seuil indicatif de 80 %, comparez la valeur sur l’appareil et faites examiner la batterie.") : ""),
                 status: percent < 80 ? .attention : .read)
        } else {
            read("battery-health", L("Capacité maximale"), .battery, nil)
        }
        read("battery-charging", L("Batterie en charge"), .battery,
             lookup(["BatteryIsCharging", "IsCharging"], sources: batterySources),
             detail: L("État de charge déclaré lors de la lecture."))

        serial("logic-board-serial", L("Série de la carte logique"), .components, mappings: [
            ("base", ["MLBSerialNumber", "LogicBoardSerialNumber"]), ("gestalt", ["MobileGestalt.MLBSerialNumber"])])
        serial("front-camera-serial", L("Série de la caméra avant"), .components, mappings: [
            ("camera", ["IORegistry.FrontCameraModuleSerialNumString"]),
            ("gestalt", ["MobileGestalt.FrontFacingCameraModuleSerialNumber"]), ("base", ["FrontCameraSerialNumber"])])
        serial("rear-camera-serial", L("Série de la caméra arrière"), .components, mappings: [
            ("camera", ["IORegistry.BackCameraModuleSerialNumString", "IORegistry.BackCameraSNUM"]),
            ("gestalt", ["MobileGestalt.BackFacingCameraModuleSerialNumber"]), ("base", ["RearCameraSerialNumber"])])
        serial("ultrawide-camera-serial", L("Série de l’ultra grand-angle"), .components, mappings: [
            ("camera", ["IORegistry.BackSuperWideCameraModuleSerialNumString", "IORegistry.BackSuperWideCameraSNUM"])])
        serial("telephoto-camera-serial", L("Série du téléobjectif"), .components, mappings: [
            ("camera", ["IORegistry.BackTeleCameraModuleSerialNumString", "IORegistry.BackTeleCameraSNUM"])])
        serial("screen-serial", L("Identifiant de la dalle (brut)"), .components, mappings: [
            ("product", ["IORegistry.raw-panel-serial-number"])],
            note: L("Cette donnée brute peut regrouper plusieurs champs séparés par +. Elle est conservée entière, sans en déduire arbitrairement un numéro de série court."))
        serial("screen-module-serial", L("Série d’écran déclarée"), .components, mappings: [
            ("base", ["ScreenSerialNumber", "DisplaySerialNumber"]), ("gestalt", ["MobileGestalt.ScreenSerialNumber"])])
        serial("coverglass-serial", L("Identifiant de la vitre"), .components, mappings: [
            ("product", ["IORegistry.coverglass-serial-number"])])
        serial("ir-camera-serial", L("Série de la caméra infrarouge"), .components, mappings: [
            ("camera", ["IORegistry.FrontIRCameraModuleSerialNumString"]), ("gestalt", ["MobileGestalt.FrontFacingIRCameraModuleSerialNumber"])])
        serial("projector-serial", L("Série du projecteur de points"), .components, mappings: [
            ("camera", ["IORegistry.FrontIRStructuredLightProjectorSerialNumString"]),
            ("gestalt", ["MobileGestalt.FrontFacingIRStructuredLightProjectorModuleSerialNumber"])])
        serial("lidar-serial", L("Série du LiDAR"), .components, mappings: [("camera", ["IORegistry.JasperSNUM"])])
        serial("ambient-light-serial", L("Série du capteur de lumière"), .components, mappings: [
            ("product", ["IORegistry.ambient-light-sensor-serial-num"])])
        manual("parts-authenticity", L("Authenticité des pièces"), .components,
               L("La lecture d’un numéro de série ne certifie pas une pièce d’origine. Consultez Réglages > Général > Informations > Historique des pièces et des réparations, lorsque disponible."))
        manual("face-id", L("Face ID / Touch ID"), .components,
               L("Testez le déverrouillage biométrique sur l’appareil. Les protocoles publics utilisés ici ne permettent pas de certifier le fonctionnement des capteurs."))
        read("activation-state", L("État d’activation"), .security, lookup(["ActivationState"], sources: [base]),
             detail: L("État d’activation lu dans lockdown. Il ne renseigne pas le verrouillage d’activation iCloud."))
        manual("activation-lock", L("Verrouillage d’activation"), .security,
               L("Vérifiez Localiser et le compte Apple sur l’appareil. L’app ne peut pas certifier cet état ni supprimer ce verrouillage."))
        manual("jailbreak", L("Intégrité du système"), .security,
               L("L’absence de jailbreak ne peut pas être certifiée à partir de ces lectures publiques."))
        manual("carrier-lock", L("Verrouillage opérateur"), .connectivity,
               L("Vérifiez Réglages > Général > Informations > Verrouillage de l’opérateur, puis testez une SIM si nécessaire."))
        read("wifi", L("Adresse Wi-Fi"), .connectivity, lookup(["WiFiAddress"], sources: [base]), sensitive: true)
        read("bluetooth", L("Adresse Bluetooth"), .connectivity, lookup(["BluetoothAddress"], sources: [base]), sensitive: true)
        read("imei", "IMEI", .connectivity, lookup(["InternationalMobileEquipmentIdentity"], sources: [base]), sensitive: true)
        return DiagnosticReport(device: device, items: items, sources: allReadings.map(\.summary))
    }
}
