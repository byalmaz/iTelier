import XCTest
import Foundation
@testable import iTelierCore

final class RecoveryPreservationTests: XCTestCase {
    func testRecoveryAndDFUCanUseAnAcknowledgedVersionWithoutEraseArguments() throws {
        let ipsw = firmware()
        for mode in [DeviceMode.recovery, .dfu] {
            let target = device(mode: mode)
            let declaration = try declaration(for: target, version: "27.2", build: "24B5089g")
            let consent = approval(for: target, firmware: ipsw, declaration: declaration, acknowledged: true)
            XCTAssertEqual(try RestoreValidator.validateApproval(device: target, firmware: ipsw, approval: consent), "4660")
            let arguments = try RestoreValidator.arguments(ecid: "4660", url: ipsw.url, mode: .preserveData,
                upgradeVariant: ipsw.upgradeVariant(for: target))
            XCTAssertEqual(arguments, ["--variant", "Developer Upgrade Install (IPSW)", "-y", "-P", "-i", "4660", ipsw.url.path])
            XCTAssertFalse(arguments.contains("-e"))
        }
    }

    func testDeclaredVersionNeedsItsOwnAcknowledgementAndCannotBeOmitted() throws {
        let target = device(), ipsw = firmware()
        let declared = try declaration(for: target, version: "27.2", build: "24B5089g")
        XCTAssertThrowsError(try RestoreValidator.validateApproval(device: target, firmware: ipsw,
            approval: approval(for: target, firmware: ipsw, declaration: declared, acknowledged: false)))
        XCTAssertThrowsError(try RestoreValidator.validateApproval(device: target, firmware: ipsw,
            approval: approval(for: target, firmware: ipsw, declaration: nil, acknowledged: true)))
        XCTAssertTrue(ipsw.preservationIssue(for: target) != nil)
        XCTAssertNil(RestoreSystemDeclaration(device: device(mode: .normal), version: "27.2", build: "24B5089g"))
    }

    func testDeclarationIsBoundToECIDProductAndBoardAcrossRecoveryModes() throws {
        let original = device()
        let declared = try declaration(for: original, version: "27.2", build: "24B5089g")
        XCTAssertTrue(declared.matches(device(mode: .dfu, ecid: "0x1234", board: "D93AP")))
        let otherTargets = [device(ecid: "4661"), device(product: "iPhone17,2"), device(board: "d94ap")]
        for target in otherTargets {
            XCTAssertFalse(declared.matches(target))
            XCTAssertTrue(firmware(product: target.productType, board: target.hardwareModel!).preservationIssue(for: target, declaration: declared) != nil)
            XCTAssertThrowsError(try RestoreValidator.validatePreservation(device: target, firmware: firmware(),
                approval: approval(for: original, firmware: firmware(), declaration: declared, acknowledged: true)))
        }
    }

    func testDeclaredVersionDoesNotPermitDowngradesOrOlderBetas() throws {
        for mode in [DeviceMode.recovery, .dfu] {
            let target = device(mode: mode)
            let declared = try declaration(for: target, version: "27.2", build: "24B5089g")
            for ipsw in [firmware(version: "27.0.1", build: "24A200"), firmware(build: "24B5084k")] {
                XCTAssertThrowsError(try RestoreValidator.validateApproval(device: target, firmware: ipsw,
                    approval: approval(for: target, firmware: ipsw, declaration: declared, acknowledged: true)))
            }
            XCTAssertNil(firmware(build: "24B5089g").preservationIssue(for: target, declaration: declared))
            XCTAssertNil(firmware(build: "24B91").preservationIssue(for: target, declaration: declared))
        }
    }

    func testDeclarationValidatesVersionAndBuildIndependentlyAndTrimsInput() throws {
        let target = device()
        let trimmed = try declaration(for: target, version: " 27.2\n", build: " 24B5089g ")
        XCTAssertEqual(trimmed.version, "27.2")
        XCTAssertEqual(trimmed.build, "24B5089g")
        for version in ["", "unknown", "27.2 beta", "27..2", "27.2;command", String(repeating: "1", count: 51)] {
            XCTAssertNil(RestoreSystemDeclaration(device: target, version: version, build: "24B5089g"))
        }
        // Même une version plus ancienne exige un build valable ; la comparaison seule ne le ferait pas.
        for build in ["", "unknown", "24b5089g", "24B5089gg", "24B50\n89g", String(repeating: "1", count: 51) + "A1"] {
            XCTAssertNil(RestoreSystemDeclaration(device: target, version: "27.0", build: build))
        }
        XCTAssertNil(RestoreSystemDeclaration(device: device(ecid: "../../target"), version: "27.2", build: "24B5089g"))
        XCTAssertNil(RestoreSystemDeclaration(device: device(product: "unknown"), version: "27.2", build: "24B5089g"))
        XCTAssertNil(RestoreSystemDeclaration(device: device(board: "../../board"), version: "27.2", build: "24B5089g"))
    }

    func testFreshNormalVersionAlwaysOverridesTheDeclarationAtPreflight() throws {
        let original = device()
        let lowerDeclaration = try declaration(for: original, version: "27.0", build: "24A100")
        let oldFirmware = firmware(version: "27.0.1", build: "24A200")
        let consent = approval(for: original, firmware: oldFirmware, declaration: lowerDeclaration, acknowledged: true)
        let fresh = device(mode: .normal, version: "27.2", build: "24B5089g")
        XCTAssertThrowsError(try RestoreValidator.validatePreservation(device: fresh, firmware: oldFirmware, approval: consent))
        XCTAssertTrue(oldFirmware.preservationIssue(for: fresh, declaration: lowerDeclaration) != nil)

        let higherDeclaration = try declaration(for: original, version: "27.9", build: "24Z100")
        let currentFirmware = firmware()
        let freshOlder = device(mode: .normal, version: "27.0", build: "24A100")
        try RestoreValidator.validatePreservation(device: freshOlder, firmware: currentFirmware,
            approval: approval(for: original, firmware: currentFirmware, declaration: higherDeclaration, acknowledged: false))
        XCTAssertNil(currentFirmware.preservationIssue(for: freshOlder, declaration: higherDeclaration))
        XCTAssertThrowsError(try RestoreValidator.validatePreservation(device: device(mode: .normal), firmware: currentFirmware,
            approval: approval(for: original, firmware: currentFirmware, declaration: lowerDeclaration, acknowledged: true)))
    }

    func testPreflightRechecksDeclarationAndAcknowledgementAfterModeChange() throws {
        let original = device(), connected = device(mode: .dfu), ipsw = firmware()
        let declared = try declaration(for: original, version: "27.2", build: "24B5089g")
        let consent = approval(for: original, firmware: ipsw, declaration: declared, acknowledged: true)
        try RestoreValidator.validatePreservation(device: connected, firmware: ipsw, approval: consent)
        XCTAssertThrowsError(try RestoreValidator.validatePreservation(device: connected, firmware: ipsw,
            approval: approval(for: original, firmware: ipsw, declaration: declared, acknowledged: false)))
        XCTAssertThrowsError(try RestoreValidator.validatePreservation(device: connected, firmware: ipsw,
            approval: approval(for: original, firmware: ipsw, declaration: nil, acknowledged: true)))
    }

    func testEraseStillRequiresDataLossConsentAndNoSystemDeclaration() throws {
        let target = device(mode: .dfu), ipsw = firmware()
        let consent = RestoreApproval(deviceID: target.id, firmwareSHA256: ipsw.sha256, acknowledgedDataLoss: true)
        XCTAssertEqual(try RestoreValidator.validateApproval(device: target, firmware: ipsw, approval: consent), "4660")
        XCTAssertThrowsError(try RestoreValidator.validateApproval(device: target, firmware: ipsw,
            approval: RestoreApproval(deviceID: target.id, firmwareSHA256: ipsw.sha256, acknowledgedDataLoss: false)))
    }

    func testDeclarationCannotReplaceFirmwareIdentityOrPreservationRiskConsent() throws {
        let target = device(), ipsw = firmware()
        let declared = try declaration(for: target, version: "27.2", build: "24B5089g")
        XCTAssertThrowsError(try RestoreValidator.validateApproval(device: target, firmware: ipsw,
            approval: RestoreApproval(deviceID: target.id, firmwareSHA256: String(repeating: "b", count: 64),
                acknowledgedDataLoss: false, mode: .preserveData, acknowledgedPreservationRisk: true,
                systemDeclaration: declared, acknowledgedDeclaredSystem: true)))
        XCTAssertThrowsError(try RestoreValidator.validateApproval(device: target, firmware: ipsw,
            approval: RestoreApproval(deviceID: target.id, firmwareSHA256: ipsw.sha256,
                acknowledgedDataLoss: true, mode: .preserveData, acknowledgedPreservationRisk: false,
                systemDeclaration: declared, acknowledgedDeclaredSystem: true)))
        XCTAssertThrowsError(try RestoreValidator.validateApproval(device: target, firmware: firmware(updateVariant: "Customer Erase Install (IPSW)"),
            approval: approval(for: target, firmware: ipsw, declaration: declared, acknowledged: true)))
    }

    private func device(mode: DeviceMode = .recovery, ecid: String = "4660", product: String = "iPhone17,1",
                        board: String = "d93ap", version: String? = nil, build: String? = nil) -> DeviceSnapshot {
        DeviceSnapshot(id: mode == .normal ? String(repeating: "a", count: 40) : "ecid-" + ecid,
            name: "Appareil de test", productType: product, osVersion: version, buildVersion: build,
            ecid: ecid, hardwareModel: board, mode: mode)
    }

    private func firmware(version: String = "27.2", build: String = "24B5099f", product: String = "iPhone17,1",
                          board: String = "d93ap", updateVariant: String = "Developer Upgrade Install (IPSW)") -> FirmwareInfo {
        FirmwareInfo(url: URL(fileURLWithPath: "/private/firmware.ipsw"), version: version, build: build,
            supportedProductTypes: [product], sizeBytes: 1, sha256: String(repeating: "a", count: 64),
            eraseHardwareModels: [board], updateVariants: [board: updateVariant])
    }

    private func declaration(for device: DeviceSnapshot, version: String, build: String) throws -> RestoreSystemDeclaration {
        guard let result = RestoreSystemDeclaration(device: device, version: version, build: build) else {
            XCTFail("La déclaration de test devrait être valable.")
            throw NSError(domain: "RecoveryPreservationTests", code: 1)
        }
        return result
    }

    private func approval(for device: DeviceSnapshot, firmware: FirmwareInfo, declaration: RestoreSystemDeclaration?,
                          acknowledged: Bool) -> RestoreApproval {
        RestoreApproval(deviceID: device.id, firmwareSHA256: firmware.sha256, acknowledgedDataLoss: false,
            mode: .preserveData, acknowledgedPreservationRisk: true, systemDeclaration: declaration,
            acknowledgedDeclaredSystem: acknowledged)
    }
}
