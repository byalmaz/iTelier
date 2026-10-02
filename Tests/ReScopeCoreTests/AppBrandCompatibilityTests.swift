import XCTest
import Foundation
@testable import ReScopeCore

final class AppBrandCompatibilityTests: XCTestCase {
    private var report: DiagnosticReport {
        let device = DeviceSnapshot(id: "TEST-DEVICE", name: "Appareil de test", productType: "iPhone17,1",
                                    ecid: "123456789", hardwareModel: "d93ap", mode: .normal)
        return DiagnosticReport(date: Date(timeIntervalSince1970: 1_700_000_000), device: device, items: [
            .init(id: "serial", title: "Numéro de série", category: .identity,
                  actual: "TEST-SERIAL-1234", status: .read, detail: "Lecture", sensitive: true)
        ])
    }

    private func export(application: String, schema: Int = 3) -> [String: Any] {
        ["application": application, "schemaVersion": schema, "demo": false, "identifiersIncluded": true,
         "date": ISO8601DateFormatter().string(from: report.date),
         "device": ["productType": report.device.productType, "ecid": "123456789"],
         "checks": [["id": "serial", "element": "Numéro de série", "status": "read", "value": "TEST-SERIAL-1234"]]]
    }

    func testNewAndLegacyNamesImportBothReportSchemas() throws {
        for application in ["iTelier", "ReWork", "ReScope"] {
            for schema in [2, 3] {
                let data = try JSONSerialization.data(withJSONObject: export(application: application, schema: schema))
                let reference = try CheckReference.importReport(data, for: report, demo: false)
                XCTAssertEqual(reference.values.first?.id, "serial")
                XCTAssertEqual(reference.values.first?.value, "TEST-SERIAL-1234")
                XCTAssertEqual(reference.origin, .importedReport)
            }
        }
    }

    func testNewBrandRetainsIdentityAndRedactionChecks() throws {
        var wrong = export(application: "iTelier")
        wrong["device"] = ["productType": report.device.productType, "ecid": "999999"]
        XCTAssertThrowsError(try CheckReference.importReport(JSONSerialization.data(withJSONObject: wrong), for: report, demo: false))
        var masked = export(application: "iTelier")
        masked["identifiersIncluded"] = false
        XCTAssertThrowsError(try CheckReference.importReport(JSONSerialization.data(withJSONObject: masked), for: report, demo: false))
        XCTAssertThrowsError(try CheckReference.importReport(JSONSerialization.data(withJSONObject: export(application: "OtherApp")), for: report, demo: false))
    }
}
