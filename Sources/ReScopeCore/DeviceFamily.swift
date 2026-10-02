import Foundation

public enum DeviceFamily: String, Sendable {
    case iPhone, iPad, visionPro, unknown
    public init(identifier: String) {
        if identifier.hasPrefix("iPhone") { self = .iPhone }
        else if identifier.hasPrefix("iPad") { self = .iPad }
        else if identifier.hasPrefix("RealityDevice") { self = .visionPro }
        else { self = .unknown }
    }
    public var systemName: String {
        switch self { case .iPhone: return "iOS"; case .iPad: return "iPadOS"; case .visionPro: return "visionOS"; case .unknown: return "OS" }
    }
    public var symbol: String {
        switch self { case .iPad: return "ipad"; case .visionPro: return "visionpro"; default: return "iphone" }
    }
    public var supportsLocalBackup: Bool { self == .iPhone || self == .iPad }
}
public extension DeviceSnapshot {
    var family: DeviceFamily { DeviceFamily(identifier: productType) }
    var isVisionPro: Bool { family == .visionPro }
    var symbolName: String { family.symbol }
}
