import Foundation

/// Exact battery paths only: adapter and accessory measurements must never become battery data.
public struct BatteryMetrics: Sendable {
    public let domain: [String: String]
    public let gauge: [String: String]
    public let registry: [String: String]
    public init(domain: [String: String] = [:], gauge: [String: String] = [:], registry: [String: String] = [:]) {
        self.domain = domain; self.gauge = gauge; self.registry = registry
    }
    private var sources: [[String: String]] {
        [gauge.reduce(into: [:]) { if $1.key.hasPrefix("GasGauge.") { $0[String($1.key.dropFirst(9))] = $1.value } },
         registry.reduce(into: [:]) { if $1.key.hasPrefix("IORegistry.") { $0[String($1.key.dropFirst(11))] = $1.value } },
         registry.reduce(into: [:]) { if $1.key.hasPrefix("IORegistry.BatteryData.") { $0[String($1.key.dropFirst(23))] = $1.value } }]
    }
    private func number(_ keys: [String], range: ClosedRange<Double>) -> Double? {
        for source in sources {
            for key in keys {
                if let raw = source[key], let value = Double(raw), value.isFinite, range.contains(value) { return value }
            }
        }
        return nil
    }
    public var currentCapacity: Double? { number(["AppleRawCurrentCapacity"], range: 0...100_000) }
    public var designCapacity: Double? { number(["DesignCapacity"], range: 1...100_000) }
    public var fullCapacity: Double? { number(["NominalChargeCapacity", "AppleRawMaxCapacity"], range: 1...100_000) }
    public var cycles: Int? { number(["CycleCount", "BatteryCycleCount"], range: 0...100_000).map(Int.init) }
    public var voltage: Double? { number(["Voltage"], range: 1...30_000) }
    public var amperage: Double? { number(["InstantAmperage", "Amperage"], range: -30_000...30_000) }
    // Same source for both operands: do not combine readings from different services/times.
    public var watts: Double? {
        for source in sources {
            guard let voltage = source["Voltage"].flatMap(Double.init), voltage.isFinite, (1...30_000).contains(voltage),
                  let current = (source["InstantAmperage"] ?? source["Amperage"]).flatMap(Double.init), current.isFinite,
                  (-30_000...30_000).contains(current) else { continue }
            return voltage * current / 1_000_000
        }
        return nil
    }
    public var declaredHealth: Double? {
        for source in [domain] + sources {
            if let value = source["MaximumCapacityPercent"].flatMap(Double.init), value.isFinite, (1...100).contains(value) { return value }
        }
        return nil
    }
    public var estimatedHealth: Double? {
        for source in sources {
            guard let design = source["DesignCapacity"].flatMap(Double.init), design.isFinite, (1...100_000).contains(design),
                  let full = (source["NominalChargeCapacity"] ?? source["AppleRawMaxCapacity"]).flatMap(Double.init),
                  full.isFinite, (1...100_000).contains(full), full / design <= 1.5 else { continue }
            return full / design * 100
        }
        return nil
    }
    public var serial: String? {
        for key in ["IORegistry.Serial", "IORegistry.BatterySerialNumber", "IORegistry.SerialNumber", "IORegistry.BatteryData.Serial"] {
            if let value = DiagnosticReading.serial(registry[key]) { return value }
        }
        for key in ["GasGauge.BatterySerialNumber", "GasGauge.SerialNumber"] {
            if let value = DiagnosticReading.serial(gauge[key]) { return value }
        }
        return DiagnosticReading.serial(domain["BatterySerialNumber"])
    }
    public var isCritical: Bool? {
        for source in [domain] + sources {
            switch (source["BatteryAtCriticalLevel"] ?? source["AtCriticalLevel"])?.lowercased() {
            case "true", "1": return true
            case "false", "0": return false
            default: continue
            }
        }
        return nil
    }
}
