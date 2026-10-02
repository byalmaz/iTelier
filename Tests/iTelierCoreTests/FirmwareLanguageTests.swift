import XCTest
@testable import iTelierCore

final class FirmwareLanguageTests: XCTestCase {
    func testCachedBetaUsesTheCurrentLanguage() {
        let value = release("27.2 beta 2")
        XCTAssertEqual(value.displayVersion(language: "fr"), "27.2 bêta 2")
        XCTAssertEqual(value.displayVersion(language: "en"), "27.2 beta 2")
        XCTAssertEqual(value.displayVersion(language: "fr"), "27.2 bêta 2")
    }

    func testPreviouslyLocalisedBetaTitleCanSwitchToEnglish() {
        XCTAssertEqual(release("27.2 bêta 2").displayVersion(language: "en"), "27.2 beta 2")
        XCTAssertEqual(release("27.2 beta").displayVersion(language: "fr"), "27.2 bêta")
    }

    func testPublicAndOtherPrereleaseTitlesRemainUnchanged() {
        XCTAssertEqual(release(nil).displayVersion(language: "en"), "27.2")
        XCTAssertEqual(release("27.2 RC").displayVersion(language: "fr"), "27.2 RC")
        XCTAssertEqual(release("Autre beta de test").displayVersion(language: "en"), "Autre beta de test")
    }

    private func release(_ title: String?) -> FirmwareRelease {
        FirmwareRelease(identifier: "iPhone18,1", version: "27.2", buildID: "TEST",
                        url: URL(string: "https://updates.cdn-apple.com/fixture.ipsw")!, fileSize: 3,
                        signed: true, prereleaseTitle: title)
    }
}
