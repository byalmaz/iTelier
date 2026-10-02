import Foundation

public extension DeviceSnapshot {
    var carrierDescription: String? {
        if let name = nonempty(values["CarrierName"]) { return name }
        let prefixes = Set(values.keys.compactMap { key -> String? in
            let parts = key.split(separator: ".")
            guard parts.count == 3, parts[0] == "CarrierBundleInfoArray", Int(parts[1]) != nil else { return nil }
            return parts.prefix(2).joined(separator: ".")
        }).sorted()
        let descriptions = prefixes.compactMap { prefix -> String? in
            var name = nonempty(values[prefix + ".CarrierName"])
            if name == nil, let bundle = nonempty(values[prefix + ".CFBundleIdentifier"]), bundle.hasPrefix("com.apple.") {
                let components = bundle.dropFirst(10).split(separator: "_").map(String.init)
                name = components.enumerated().map { index, value in index == components.count - 1 && value.count == 2 ? value.uppercased() : value }.joined(separator: " ")
            }
            guard let name else { return nil }
            return name + (nonempty(values[prefix + ".CFBundleVersion"]).map { " (\($0))" } ?? "")
        }
        return descriptions.isEmpty ? nil : descriptions.joined(separator: " · ")
    }
    /// iOS supplies an intentionally masked Find My account. Never imply this is the complete address.
    var maskedAppleAccount: String? {
        guard let text = nonempty(values["NonVolatileRAM.fm-account-masked"]), text.count <= 320,
              text.contains("@"), !text.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else { return nil }
        return text
    }
    private func nonempty(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else { return nil }
        return text
    }
}
