import XCTest
@testable import iTelierCore

final class BatteryPresentationTests: XCTestCase {
    private func information(_ battery: [String: String]) -> DeviceInformation {
        DeviceInformation(device: DeviceSnapshot(id: "TEST-DEVICE-0001", name: "Test", productType: "iPhone14,2"), battery: battery)
    }

    func testPowerStateComesOnlyFromDeclaredKeys() {
        XCTAssertEqual(information(["BatteryIsCharging": "true"]).powerState, .charging)
        XCTAssertEqual(information(["BatteryIsCharging": "false", "ExternalConnected": "true", "FullyCharged": "true"]).powerState, .full)
        XCTAssertEqual(information(["BatteryIsCharging": "false", "ExternalConnected": "true", "FullyCharged": "false"]).powerState, .pluggedNotCharging)
        XCTAssertEqual(information(["BatteryIsCharging": "false", "ExternalConnected": "false"]).powerState, .onBattery)
        XCTAssertEqual(information(["BatteryIsCharging": "false"]).powerState, .onBattery)
        XCTAssertNil(information([:]).powerState)
        XCTAssertNil(information(["ExternalConnected": "maybe"]).powerState)
    }

    func testEstimatedHealthCanExceedOneHundredWithoutDeclaredHealth() {
        // A new battery can hold slightly more than its design capacity.
        let metrics = BatteryMetrics(gauge: ["GasGauge.DesignCapacity": "3544", "GasGauge.NominalChargeCapacity": "3628"])
        XCTAssertEqual(metrics.estimatedHealth.map { Int($0.rounded()) }, 102)
        XCTAssertNil(metrics.declaredHealth)
    }
}
