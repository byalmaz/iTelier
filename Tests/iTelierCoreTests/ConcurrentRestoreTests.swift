import XCTest
import Foundation
@testable import iTelierCore

final class ConcurrentRestoreTests: XCTestCase {
    func testSameECIDInDecimalAndHexSharesOneLock() throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let decimal = try RestoreHost.deviceLockRoot(ecid: "4660", root: root)
        let hex = try RestoreHost.deviceLockRoot(ecid: "0x1234", root: root)
        XCTAssertEqual(decimal, hex)
        let lock = try HostLock(root: decimal, acquire: true)
        defer { withExtendedLifetime(lock) {} }
        XCTAssertTrue(RestoreHost.isLocked(root: hex))
        XCTAssertThrowsError(try HostLock(root: hex, acquire: true))
        XCTAssertThrowsError(try RestoreHost.deviceLockRoot(ecid: "../../another-device", root: root))
    }

    func testDifferentDevicesCanHoldLocksTogetherAndReleaseIndependently() throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        let first = try RestoreHost.deviceLockRoot(ecid: "4660", root: root)
        let second = try RestoreHost.deviceLockRoot(ecid: "4661", root: root)
        var firstLock: HostLock? = try HostLock(root: first, acquire: true)
        let secondLock = try HostLock(root: second, acquire: true)
        XCTAssertTrue(RestoreHost.isLocked(root: first))
        XCTAssertTrue(RestoreHost.isLocked(root: second))
        withExtendedLifetime(firstLock) {}
        firstLock = nil
        XCTAssertFalse(RestoreHost.isLocked(root: first))
        XCTAssertTrue(RestoreHost.isLocked(root: second))
        withExtendedLifetime(secondLock) {}
    }

    func testSharedRestoreLocksExcludeBackupMigrationAndOldWorkers() throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        var first: HostLock? = try HostLock(root: root, acquire: true, shared: true)
        var second: HostLock? = try HostLock(root: root, acquire: true, shared: true)
        XCTAssertTrue(RestoreHost.isLocked(root: root))
        XCTAssertThrowsError(try HostLock(root: root, acquire: true))
        withExtendedLifetime(first) {}; first = nil
        XCTAssertTrue(RestoreHost.isLocked(root: root))
        withExtendedLifetime(second) {}; second = nil
        XCTAssertFalse(RestoreHost.isLocked(root: root))
        let exclusive = try HostLock(root: root, acquire: true)
        XCTAssertThrowsError(try HostLock(root: root, acquire: true, shared: true))
        withExtendedLifetime(exclusive) {}
    }

    func testMetadataCannotChangeTargetOrModeAndNeverEntersSupportExport() throws {
        let first = DeviceSnapshot(id: String(repeating: "a", count: 40), name: "Téléphone privé", productType: "iPhone17,1", ecid: "4660")
        let firmware = FirmwareInfo(url: URL(fileURLWithPath: "/private/firmware.ipsw"), version: "26.0", build: "23A1",
            supportedProductTypes: [first.productType], sizeBytes: 1, sha256: String(repeating: "a", count: 64))
        let target = try RestoreTarget(device: first, firmware: firmware, mode: .preserveData)
        try target.validate(ecid: "4660", mode: .preserveData)
        XCTAssertThrowsError(try target.validate(ecid: "4661", mode: .preserveData))
        XCTAssertThrowsError(try target.validate(ecid: "4660", mode: .erase))
        XCTAssertTrue(target.matches(DeviceSnapshot(id: "ecid-4660", name: "Recovery", productType: first.productType, ecid: "0x1234", mode: .recovery)))
        XCTAssertFalse(target.matches(DeviceSnapshot(id: first.id, name: first.name, productType: first.productType, ecid: "4661")))
        let context = SupportContext(operation: .restoration, phase: "Installation", deviceModel: target.productType,
            systemVersion: target.systemVersion, firmwareVersion: target.firmwareVersion, firmwareBuild: target.firmwareBuild, restoreMode: target.mode)
        let export = String(decoding: try SupportReport(kind: .error, appVersion: "0.2.0", context: context).json(), as: UTF8.self)
        for privateValue in [first.id, first.name, "4660", firmware.url.path] { XCTAssertFalse(export.contains(privateValue)) }
    }

    func testRecoveryInventoryParsesHexECIDsWithoutAcceptingPathsOrSimilarKeys() {
        XCTAssertEqual(RecoveryUSBInventory.ecid(serial: "CPID:8120 ECID:0000000000001234 SRTG:[iBoot]"), "4660")
        XCTAssertEqual(RecoveryUSBInventory.ecid(serial: "ECID:1235"), "4661")
        XCTAssertNil(RecoveryUSBInventory.ecid(serial: "OTHER_ECID:1234"))
        XCTAssertNil(RecoveryUSBInventory.ecid(serial: "ECID:../../a"))
        XCTAssertNil(RecoveryUSBInventory.ecid(serial: "ECID:0000000000000000"))
    }

    func testSessionInventoryKeepsBothResultsAndIgnoresInvalidRecords() throws {
        let root = temporaryRoot(); defer { try? FileManager.default.removeItem(at: root) }
        for offset in 0..<2 {
            let directory = root.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let state = RestoreHostSnapshot(sessionID: directory.lastPathComponent, phase: "Installation", progress: Double(offset) / 2,
                finished: false, updatedAt: Date(timeIntervalSince1970: Double(offset)), log: ["private-job-\(offset)"])
            try RestoreHost.write(state, to: directory.appendingPathComponent("state.json"))
        }
        let bad = root.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: bad, withIntermediateDirectories: true)
        try Data("broken JSON".utf8).write(to: bad.appendingPathComponent("state.json"))
        let sessions = RestoreHost.sessions(root: root)
        XCTAssertEqual(sessions.count, 2)
        XCTAssertEqual(sessions[0].snapshot.log, ["private-job-1"])
        XCTAssertEqual(sessions[1].snapshot.log, ["private-job-0"])
        XCTAssertNil(sessions[0].snapshot.target)
    }

    private func temporaryRoot() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent("itelier-concurrent-tests-" + UUID().uuidString) }
}
