import Foundation

/// Source-language keys and numbered arguments keep localisation separate from
/// device names, identifiers, URLs and engine output. No substring translation.
public struct LocalizedText: ExpressibleByStringLiteral, ExpressibleByStringInterpolation {
    public let key: String
    public let arguments: [String]
    public init(stringLiteral value: String) { key = value; arguments = [] }
    public init(stringInterpolation: StringInterpolation) { key = stringInterpolation.key; arguments = stringInterpolation.arguments }
    public struct StringInterpolation: StringInterpolationProtocol {
        var key = ""
        var arguments: [String] = []
        public init(literalCapacity: Int, interpolationCount: Int) { key.reserveCapacity(literalCapacity); arguments.reserveCapacity(interpolationCount) }
        public mutating func appendLiteral(_ literal: String) { key += literal }
        public mutating func appendInterpolation<T>(_ value: T) { key += "{\(arguments.count)}"; arguments.append(String(describing: value)) }
    }
}
public enum AppLocalization {
    public static var language: String { ProcessInfo.processInfo.environment["RESCOPE_LANGUAGE"] ?? UserDefaults.standard.string(forKey: "appLanguage") ?? "fr" }
    public static func render(_ text: LocalizedText, language: String) -> String {
        let format = language == "en" ? EnglishStrings.values[text.key] ?? text.key : text.key
        // Resolve placeholders once. An argument containing {1}, e.g. a device
        // name, must never be interpreted as another formatting instruction.
        var output = "", index = format.startIndex
        while index < format.endIndex {
            if format[index] == "{", let end = format[index...].firstIndex(of: "}"),
               let number = Int(format[format.index(after: index)..<end]), text.arguments.indices.contains(number) {
                output += text.arguments[number]; index = format.index(after: end)
            } else { output.append(format[index]); index = format.index(after: index) }
        }
        return output
    }
}
public func L(_ text: LocalizedText) -> String { AppLocalization.render(text, language: AppLocalization.language) }

public extension AppLocalization {
    static var locale: Locale { Locale(identifier: language == "en" ? "en_GB" : "fr_FR") }
    /// Relabel stored UI copy when changing language; never use on device identifiers.
    static func label(_ value: String) -> String {
        if language == "en" { return EnglishStrings.values[value] ?? value }
        return EnglishStrings.values.first(where: { $0.value == value })?.key ?? value
    }
}
public extension Date {
    func uiFormatted(date: Date.FormatStyle.DateStyle, time: Date.FormatStyle.TimeStyle) -> String {
        formatted(Date.FormatStyle(date: date, time: time).locale(AppLocalization.locale))
    }
}
public func localizedByteCount(_ bytes: Int64) -> String {
    bytes.formatted(.byteCount(style: .file).locale(AppLocalization.locale))
}
