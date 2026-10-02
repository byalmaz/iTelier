import Foundation

public struct DiagnosticSourceSummary: Codable, Identifiable, Sendable {
    public let id: String
    public let title: String
    public let status: CheckStatus
    public let detail: String
}

struct DiagnosticReading: Sendable {
    let id: String
    let title: String
    let values: [String: String]
    let status: CheckStatus
    let detail: String
    var summary: DiagnosticSourceSummary { .init(id: id, title: title, status: status, detail: detail) }

    static func decode(id: String, title: String, data: Data) throws -> Self {
        let object = try DeviceParser.plist(data)
        var values = DeviceParser.flattened(object)
        func filterBinary(_ value: Any, path: String) {
            if let dict = value as? [String: Any] {
                for (key, child) in dict { filterBinary(child, path: path.isEmpty ? key : path + "." + key) }
            } else if let list = value as? [Any] {
                for (index, child) in list.enumerated() { filterBinary(child, path: path + ".\(index)") }
            } else if let data = value as? Data {
                if let text = String(data: data, encoding: .utf8), let serial = Self.serial(text) { values[path] = serial }
                else { values.removeValue(forKey: path) }
            }
        }
        filterBinary(object, path: "")
        // An exit code of zero does not mean the requested diagnostic was supported.
        let statusPaths: [String]
        switch id {
        case "gestalt": statusPaths = ["Status", "MobileGestalt.Status"]
        case "gauge": statusPaths = ["Status", "GasGauge.Status"]
        default: statusPaths = ["Status", "IORegistry.Status"]
        }
        for path in statusPaths {
            guard let state = values[path], state != "Success" else { continue }
            let unsupported = ["MobileGestaltDeprecated", "UnknownRequest", "Unsupported", "NotSupported"].contains(state)
            return Self(id: id, title: title, values: [:], status: unsupported ? .unsupported : .readFailed,
                detail: state == "MobileGestaltDeprecated"
                    ? L("L’iPhone indique que la lecture MobileGestalt a été retirée. Les autres sources restent utilisées.")
                    : unsupported ? L("L’appareil indique que cette requête n’est pas prise en charge.")
                    : L("Le service a refusé ou échoué à exécuter la requête. Déverrouillez l’appareil et relancez le Check."))
        }
        return Self(id: id, title: title, values: values, status: .read,
                    detail: L("Réponse reçue. Chaque champ est validé séparément ; une clé absente reste non exposée."))
    }

    static func failure(id: String, title: String, error: Error) -> Self {
        let detail: String
        switch error {
        case DeviceServiceError.timedOut: detail = "Délai de lecture dépassé. Vérifiez le câble, déverrouillez l’appareil et relancez le Check."
        case DeviceServiceError.missingTool: detail = "L’outil de lecture est absent du bundle. Réinstallez iTelier."
        case DeviceServiceError.commandFailed(_, let code, _): detail = "La commande de lecture a échoué (code \(code)). Vérifiez la connexion et l’autorisation Faire confiance."
        case DeviceServiceError.outputTooLarge: detail = "La réponse dépasse la limite de lecture autorisée."
        default: detail = L("La réponse de cette source n’a pas pu être interprétée. Relancez le Check.")
        }
        return Self(id: id, title: title, values: [:], status: .readFailed, detail: detail)
    }

    /// Only textual serials are accepted. Binary blobs are not turned into plausible serials.
    static func serial(_ text: String?) -> String? {
        guard let text else { return nil }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
        guard (4...512).contains(value.utf8.count),
              value.unicodeScalars.allSatisfy({ (32...126).contains($0.value) }),
              value.contains(where: { $0.isLetter || $0.isNumber }),
              !["unknown", "unavailable", "null", "none", "n/a"].contains(value.lowercased()),
              !value.allSatisfy({ $0 == "0" || $0 == " " }) else { return nil }
        return value
    }

    static func cameraEntries(_ data: Data) throws -> [String] {
        let object = try DeviceParser.plist(data)
        var names = Set<String>()
        func visit(_ value: Any) {
            if let dict = value as? [String: Any] {
                if let name = dict["name"] as? String,
                   name.range(of: "^AppleH[0-9]{1,3}CamIn$", options: .regularExpression) != nil { names.insert(name) }
                for child in dict.values where child is [String: Any] || child is [Any] { visit(child) }
            } else if let array = value as? [Any] { array.forEach(visit) }
        }
        visit(object)
        return Array(names.sorted().prefix(4))
    }
}
