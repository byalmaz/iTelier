import XCTest
@testable import iTelierCore

final class FirmwareModelOrderTests: XCTestCase {
    func testModelsUseNumericGenerationsRatherThanAlphabeticalNames() throws {
        let data = Data("""
        [{"identifier":"iPhone9,2","name":"iPhone 7 Plus"},
         {"identifier":"iPhone18,1","name":"iPhone 17 Pro"},
         {"identifier":"iPhone1,1","name":"iPhone 2G"},
         {"identifier":"iPhone17,5","name":"iPhone 16e"},
         {"identifier":"iPad8,12","name":"iPad Pro"},
         {"identifier":"iPad16,6","name":"iPad Pro"},
         {"identifier":"iPhone18,1","name":"Doublon"}]
        """.utf8)
        let devices = try FirmwareCatalog.decodeDevices(data)
        XCTAssertEqual(devices.filter { $0.identifier.hasPrefix("iPhone") }.map(\.identifier),
                       ["iPhone18,1", "iPhone17,5", "iPhone9,2", "iPhone1,1"])
        XCTAssertEqual(devices.filter { $0.identifier.hasPrefix("iPad") }.map(\.identifier),
                       ["iPad16,6", "iPad8,12"])
    }
}
