import XCTest
import Foundation
@testable import ReScopeCore

final class FaceIDTestTests: XCTestCase {
    private var device: DeviceSnapshot { .init(id: "FACE-ID-DEVICE", name: "Test", productType: "iPhone18,1", ecid: "1234") }

    func testSerialsNeverCreateFunctionalSuccess() {
        let report = DiagnosticReport(device: device, items: [
            .init(id: "ir-camera-serial", title: "IR", category: .components, actual: "IR123456", status: .read, detail: ""),
            .init(id: "projector-serial", title: "Projecteur", category: .components, actual: "DOT123456", status: .verified, detail: "")
        ])
        let test = FaceIDTest(report: report)
        XCTAssertNil(test.result)
        XCTAssertEqual(test.components.map(\.status), [.read, .read, .unavailable])
        XCTAssertEqual(test.components[0].identifier, "IR123456")
        XCTAssertNil(test.components[2].identifier)
    }

    func testOnlyExplicitObservationCompletesStartedTest() {
        var test = FaceIDTest(report: .init(device: device, items: []))
        XCTAssertFalse(test.confirm(.unlocked, on: device))
        XCTAssertTrue(test.begin(on: device))
        XCTAssertNil(test.result)
        XCTAssertTrue(test.confirm(.unlocked, on: device))
        XCTAssertEqual(test.result, .unlocked)
        XCTAssertEqual(test.phase, .completed)
        XCTAssertTrue(test.begin(on: device))
        XCTAssertNil(test.result)
        XCTAssertTrue(test.confirm(.failed, on: device))
        XCTAssertEqual(test.result, .failed)
    }

    func testDisconnectedChangedAndRecoveryDevicesCannotConfirm() {
        var test = FaceIDTest(report: .init(device: device, items: []))
        XCTAssertTrue(test.begin(on: device))
        XCTAssertFalse(test.confirm(.unlocked, on: nil))
        XCTAssertFalse(test.confirm(.unlocked, on: .init(id: "OTHER", name: "Test", productType: device.productType, ecid: "1234")))
        XCTAssertFalse(test.confirm(.unlocked, on: .init(id: device.id, name: "Test", productType: device.productType, ecid: "4321")))
        XCTAssertFalse(test.confirm(.unlocked, on: .init(id: device.id, name: "Test", productType: device.productType, ecid: "1234", mode: .recovery)))
        XCTAssertNil(test.result)
        XCTAssertFalse(FaceIDTest.supportsGuidedTest(.init(id: "VISION", name: "Vision", productType: "RealityDevice14,1")))
    }

    func testConflictingFailedAndInvalidComponentReadingsStayUnverified() {
        let report = DiagnosticReport(device: device, items: [
            .init(id: "ir-camera-serial", title: "IR", category: .components, actual: "IR111111", status: .read, detail: ""),
            .init(id: "ir-camera-serial", title: "IR", category: .components, actual: "IR222222", status: .read, detail: ""),
            .init(id: "projector-serial", title: "Projecteur", category: .components, actual: "DOT123456", status: .readFailed, detail: ""),
            .init(id: "proximity-sensor-serial", title: "Capteur", category: .components, actual: "00000000", status: .read, detail: "")
        ])
        let test = FaceIDTest(report: report)
        XCTAssertEqual(test.components.map(\.status), [.attention, .readFailed, .unavailable])
        XCTAssertTrue(test.components.allSatisfy { $0.identifier == nil })
        XCTAssertNil(test.result)
    }
}
