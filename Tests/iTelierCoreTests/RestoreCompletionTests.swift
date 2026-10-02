import XCTest
import Foundation
@testable import iTelierCore

final class RestoreCompletionTests: XCTestCase {
    func testYonkersFailureWithZeroExitAndDoneIsRejected() {
        var tracker = RestoreCompletionTracker()
        for line in ["Unable to fetch Yonkers ticket", "Unable to send FirmwareUpdater data",
                     "Unable to successfully restore device", "DONE", "progress: 4 1"] {
            tracker.append(line)
        }
        XCTAssertEqual(tracker.completion(exitCode: 0), .failed)
    }

    func testDoneAndFullProgressDoNotConfirmInstallation() {
        var tracker = RestoreCompletionTracker()
        tracker.append("progress: 4 1")
        tracker.append("DONE")
        tracker.append("Sending component named Status: Restore Finished")
        XCTAssertEqual(tracker.completion(exitCode: 0), .unconfirmed)
    }

    func testDeviceFinalStatusAndExitZeroAreBothRequired() {
        var tracker = RestoreCompletionTracker()
        tracker.append("  Status: Restore Finished\r")
        XCTAssertEqual(tracker.completion(exitCode: 0), .confirmed)
        XCTAssertEqual(tracker.completion(exitCode: 1), .failed)
        tracker.append("ERROR: Unable to successfully restore device")
        XCTAssertEqual(tracker.completion(exitCode: 0), .failed)
    }

    func testFatalDeviceStatusSurvivesLaterOutputButRecoverableWarningsDoNotFail() {
        var tracker = RestoreCompletionTracker()
        tracker.append("Unable to connect, retrying")
        tracker.append("Unknown operation (79)")
        tracker.append("Status: Restore Finished")
        XCTAssertEqual(tracker.completion(exitCode: 0), .confirmed)
        tracker.append("Status: Failed to load SEP Firmware.")
        for _ in 0..<200 { tracker.append("Sending subsequent log output") }
        XCTAssertEqual(tracker.completion(exitCode: 0), .failed)
    }

    func testLegacySnapshotsReclassifyFalseSuccessAndPersistedStatusSurvivesLogTrimming() throws {
        let legacy: [String: Any] = ["sessionID": UUID().uuidString, "phase": "Restauration terminée",
            "progress": 1, "finished": true, "exitCode": 0, "updatedAt": 123,
            "log": ["Unable to successfully restore device", "DONE"]]
        let snapshot = try JSONDecoder().decode(RestoreHostSnapshot.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertNil(snapshot.engineCompletion)
        XCTAssertEqual(snapshot.completion, .failed)
        var current = snapshot
        current.log = ["DONE"]
        current.engineCompletion = .confirmed
        XCTAssertEqual(current.completion, .confirmed)
        current.finished = false
        XCTAssertEqual(current.completion, .unconfirmed)
        current.finished = true
        current.engineCompletion = nil
        XCTAssertEqual(current.completion, .unconfirmed)
    }
}
