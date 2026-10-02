import Foundation

/// Read-only overview values. Missing fields stay missing; storage categories
/// and battery health cannot be inferred from charge or overall disk capacity.
public struct DeviceInformation: Sendable {
    public let device: DeviceSnapshot
    public let battery: [String: String]
    public let metrics: BatteryMetrics
    public let hasBatteryDetails: Bool
    public let storageHardware: StorageHardware
    public let hasStorageDetails: Bool
    public let disk: [String: String]
    public let date: Date
    public let warnings: [String]
    public init(device: DeviceSnapshot, battery: [String: String] = [:], disk: [String: String] = [:], warnings: [String] = [], gauge: [String: String] = [:], registry: [String: String] = [:], hasBatteryDetails: Bool = false, storageHardware: StorageHardware = StorageHardware(), hasStorageDetails: Bool = false, date: Date = Date()) {
        self.storageHardware = storageHardware; self.hasStorageDetails = hasStorageDetails
        self.metrics = BatteryMetrics(domain: battery, gauge: gauge, registry: registry); self.hasBatteryDetails = hasBatteryDetails
        self.device = device; self.battery = battery; self.disk = disk; self.warnings = warnings; self.date = date
    }
    public var batteryPercent: Int? {
        guard let raw = battery["BatteryCurrentCapacity"], let value = Double(raw), value.isFinite, (0...100).contains(value) else { return nil }
        return Int(value)
    }
    public var isCharging: Bool? {
        switch battery["BatteryIsCharging"]?.lowercased() { case "true", "1", "yes": return true; case "false", "0", "no": return false; default: return nil }
    }
    public var storageTotal: Int64? {
        if systemUsed != nil, let data = positive(disk["TotalDataCapacity"]), let system = positive(disk["TotalSystemCapacity"]), data <= Int64.max - system { return data + system }
        return positive(disk["TotalDataCapacity"]) ?? positive(disk["TotalDiskCapacity"])
    }
    public var storageFree: Int64? {
        // Only pair the available data partition bytes with the same partition's total.
        guard let total = positive(disk["TotalDataCapacity"]), let raw = disk["AmountDataAvailable"] ?? disk["TotalDataAvailable"],
              let free = Int64(raw), free >= 0, free <= total else { return nil }
        return free + (systemUsed != nil ? (disk["TotalSystemAvailable"].flatMap(Int64.init) ?? 0) : 0)
    }
    public var systemUsed: Int64? {
        guard hasStorageDetails, let total = positive(disk["TotalSystemCapacity"]), let data = positive(disk["TotalDataCapacity"]), data <= Int64.max - total,
              let free = disk["TotalSystemAvailable"].flatMap(Int64.init), free >= 0, free <= total else { return nil }
        return total - free
    }
    public var storageUsed: Int64? {
        guard let total = storageTotal, let free = storageFree else { return nil }
        return total - free
    }
    private func positive(_ value: String?) -> Int64? { value.flatMap(Int64.init).flatMap { $0 > 0 ? $0 : nil } }
}

public enum BatteryPowerState: Sendable, Equatable {
    case charging, full, pluggedNotCharging, onBattery
}

public extension DeviceInformation {
    /// Charge state declared by the lockdown battery domain. A missing key never becomes a state.
    var powerState: BatteryPowerState? {
        func flag(_ key: String) -> Bool? {
            switch battery[key]?.lowercased() { case "true", "1", "yes": return true; case "false", "0", "no": return false; default: return nil }
        }
        if isCharging == true { return .charging }
        switch flag("ExternalConnected") {
        case true?: return flag("FullyCharged") == true ? .full : .pluggedNotCharging
        case false?: return .onBattery
        case nil: return isCharging == false ? .onBattery : nil
        }
    }
}
