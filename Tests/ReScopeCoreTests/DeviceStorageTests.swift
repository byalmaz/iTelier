import XCTest
import Foundation
@testable import ReScopeCore

final class DeviceStorageTests: XCTestCase {
    private var device: DeviceSnapshot { DeviceSnapshot(id: "STORAGE-TEST", name: "Test", productType: "iPhone18,1", osVersion: "27.2") }

    func testPhotoAliasesAreNeverCountedTwiceAndSystemUsesItsOwnPartition() {
        let info = DeviceInformation(device: device, disk: ["TotalDataCapacity": "1000", "AmountDataAvailable": "400",
            "TotalSystemCapacity": "100", "TotalSystemAvailable": "10", "PhotoUsage": "200", "CameraUsage": "200",
            "MobileApplicationUsage": "100", "ApplicationDocumentsUsage": "50"], hasStorageDetails: true)
        XCTAssertEqual(info.storageTotal, 1100)
        XCTAssertEqual(info.storageFree, 410)
        XCTAssertEqual(info.systemUsed, 90)
        XCTAssertEqual(info.storageSegments.map(\.id), ["system", "PhotoUsage", "MobileApplicationUsage", "ApplicationDocumentsUsage", "used", "free"])
        XCTAssertEqual(info.storageSegments.map(\.bytes), [90, 200, 100, 50, 250, 410])
        XCTAssertEqual(info.storageSegments.reduce(Int64(0)) { $0 + $1.bytes }, 1100)
    }

    func testFlashPropertiesUseExactControllerFields() {
        let hardware = StorageHardware(values: ["IORegistry.Controller Characteristics.vendor-name": "Hynix   ",
            "IORegistry.Model Number": "APPLE SSD TEST", "IORegistry.Controller Characteristics.nand-marketing-name": "tlc_3d_test",
            "IORegistry.Controller Characteristics.firmware-version": "1.2.3", "IORegistry.Serial Number": "TEST-NAND-123",
            "IORegistry.IOMaximumSegmentByteCountRead": "4096"])
        XCTAssertEqual(hardware.vendor, "Hynix")
        XCTAssertEqual(hardware.cellType, "TLC")
        XCTAssertEqual(hardware.model, "APPLE SSD TEST")
        XCTAssertEqual(hardware.firmware, "1.2.3")
        XCTAssertEqual(hardware.number("IOMaximumSegmentByteCountRead"), 4096)
        XCTAssertEqual(hardware.serial, "TEST-NAND-123")
        XCTAssertNil(StorageHardware(values: ["IORegistry.Controller Characteristics.nand-marketing-name": "unknown", "IORegistry.Child.Serial Number": "DECOY"]).serial)
        XCTAssertNil(StorageHardware(values: ["IORegistry.Controller Characteristics.nand-marketing-name": "unknown"]).cellType)
    }

    func testControllerDiscoveryRejectsArgumentsAndUnrelatedNodes() throws {
        let data = try PropertyListSerialization.data(fromPropertyList: ["IORegistry": ["children": [
            ["name": "AppleANS3CGv2Controller"], ["name": "AppleANS2NVMeController"],
            ["name": "AppleSmartBattery"], ["name": "AppleANS;rebootController"], ["name": "--help"]
        ]]], format: .xml, options: 0)
        XCTAssertEqual(try StorageHardware.controllerNames(data), ["AppleANS2NVMeController", "AppleANS3CGv2Controller"])
    }

    func testAppUsageOnlyAcceptsCompleteNonnegativeAggregates() throws {
        let usage = try JSONDecoder().decode(StorageAppUsage.self, from: Data("{\"count\":202,\"applicationBytes\":523000,\"documentBytes\":115000}".utf8))
        XCTAssertEqual(usage.diskValues["MobileApplicationUsage"], "523000")
        let partial = try JSONDecoder().decode(StorageAppUsage.self, from: Data("{\"count\":2,\"applicationBytes\":-1}".utf8))
        XCTAssertTrue(partial.diskValues.isEmpty)
    }
}
