import Foundation
import XCTest
@testable import iTelierCore

final class LegacyAppMigrationTests: XCTestCase {
    private let previousName = String(decoding: [82, 101, 83, 99, 111, 112, 101], as: UTF8.self)
    private var previousDomain: String { "com." + previousName.lowercased() + ".app" }

    private func fixture(_ body: (URL, URL, URL, UserDefaults, String) throws -> Void) throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("itelier-migration-" + UUID().uuidString)
        let domain = "test.itelier.migration." + UUID().uuidString
        let defaults = UserDefaults(suiteName: domain)!
        defer {
            defaults.removePersistentDomain(forName: domain)
            try? FileManager.default.removeItem(at: root)
        }
        let support = root.appendingPathComponent("Application Support")
        let downloads = root.appendingPathComponent("Downloads")
        let preferences = root.appendingPathComponent("Preferences")
        for directory in [support, downloads, preferences] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try body(support, downloads, preferences, defaults, domain)
    }

    private func directory(_ root: URL, _ suffix: String = "") throws -> URL {
        let path = root.appendingPathComponent(previousName).appendingPathComponent(suffix)
        try FileManager.default.createDirectory(at: path, withIntermediateDirectories: true)
        return path
    }

    func testMovesDataAndRetainsPreferencesWithoutOverwritingCurrentChoices() throws {
        try fixture { support, downloads, preferences, defaults, domain in
            let backup = try directory(support, "Backups/TEST")
            let firmware = try directory(downloads)
            try Data("backup".utf8).write(to: backup.appendingPathComponent("fixture"))
            try Data("firmware".utf8).write(to: firmware.appendingPathComponent("test.ipsw"))
            let values: [String: Any] = ["backupEncrypt": false, "appearance": "dark",
                "backupDirectory": backup.path, "imports": [backup.path], "firmware": firmware.path]
            let data = try PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0)
            try data.write(to: preferences.appendingPathComponent(previousDomain + ".plist"))
            defaults.setPersistentDomain(["appearance": "light"], forName: domain)
            try LegacyAppMigration.prepare(support: support, downloads: downloads, preferences: preferences, defaults: defaults, domain: domain)
            let newBackup = support.appendingPathComponent("iTelier/Backups/TEST")
            XCTAssertEqual(try Data(contentsOf: newBackup.appendingPathComponent("fixture")), Data("backup".utf8))
            XCTAssertTrue(FileManager.default.fileExists(atPath: downloads.appendingPathComponent("iTelier/test.ipsw").path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: backup.path))
            let migrated = defaults.persistentDomain(forName: domain)!
            XCTAssertEqual(migrated["backupEncrypt"] as? Bool, false)
            XCTAssertEqual(migrated["appearance"] as? String, "light")
            XCTAssertEqual(migrated["backupDirectory"] as? String, newBackup.path)
            XCTAssertEqual(migrated["imports"] as? [String], [newBackup.path])
            XCTAssertEqual(migrated["firmware"] as? String, downloads.appendingPathComponent("iTelier").path)
            try LegacyAppMigration.prepare(support: support, downloads: downloads, preferences: preferences, defaults: defaults, domain: domain)
            XCTAssertEqual(defaults.persistentDomain(forName: domain)?["backupDirectory"] as? String, newBackup.path)
        }
    }

    func testConflictInSecondDirectoryDoesNotMoveFirstDirectory() throws {
        try fixture { support, downloads, preferences, defaults, domain in
            let first = try directory(support)
            _ = try directory(downloads)
            try FileManager.default.createDirectory(at: downloads.appendingPathComponent("iTelier"), withIntermediateDirectories: true)
            XCTAssertThrowsError(try LegacyAppMigration.prepare(support: support, downloads: downloads, preferences: preferences, defaults: defaults, domain: domain))
            XCTAssertTrue(FileManager.default.fileExists(atPath: first.path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: support.appendingPathComponent("iTelier").path))
        }
    }

    func testSymlinkAndActiveOperationsBlockMigration() throws {
        try fixture { support, downloads, preferences, defaults, domain in
            let outside = support.appendingPathComponent("outside")
            try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
            let source = support.appendingPathComponent(previousName)
            try FileManager.default.createSymbolicLink(at: source, withDestinationURL: outside)
            XCTAssertThrowsError(try LegacyAppMigration.prepare(support: support, downloads: downloads, preferences: preferences, defaults: defaults, domain: domain))
            try FileManager.default.removeItem(at: source)
            let operations = try directory(support, "USBOperation")
            let active = try HostLock(root: operations, acquire: true)
            defer { withExtendedLifetime(active) {} }
            XCTAssertThrowsError(try LegacyAppMigration.prepare(support: support, downloads: downloads, preferences: preferences, defaults: defaults, domain: domain))
            XCTAssertTrue(FileManager.default.fileExists(atPath: operations.path))
        }
    }

    func testSymlinkLockIsNotFollowed() throws {
        try fixture { support, downloads, preferences, defaults, domain in
            let operations = try directory(support, "USBOperation")
            let outside = support.appendingPathComponent("outside-lock")
            try Data("unchanged".utf8).write(to: outside)
            try FileManager.default.createSymbolicLink(at: operations.appendingPathComponent("engine.lock"), withDestinationURL: outside)
            XCTAssertThrowsError(try LegacyAppMigration.prepare(support: support, downloads: downloads, preferences: preferences, defaults: defaults, domain: domain))
            XCTAssertEqual(try Data(contentsOf: outside), Data("unchanged".utf8))
        }
    }

    func testIncompleteBackupMarkerAndStoredOperationPathsMigrate() throws {
        try fixture { support, downloads, preferences, defaults, domain in
            let backup = try directory(support, "Backups/TEST")
            let marker = backup.appendingPathComponent(previousName.lowercased() + "-incomplete")
            try Data().write(to: marker)
            XCTAssertTrue(LegacyAppMigration.hasIncompleteMarker(in: backup))
            let operation = try directory(support, "BackupOperations/" + UUID().uuidString)
            let state: [String: Any] = ["destination": backup.path, "arguments": ["backup", backup.path], "sha256": "TEST-HASH"]
            try JSONSerialization.data(withJSONObject: state).write(to: operation.appendingPathComponent("request.json"))
            try LegacyAppMigration.prepare(support: support, downloads: downloads, preferences: preferences, defaults: defaults, domain: domain)
            let newBackup = support.appendingPathComponent("iTelier/Backups/TEST")
            XCTAssertTrue(LegacyAppMigration.hasIncompleteMarker(in: newBackup))
            XCTAssertTrue(FileManager.default.fileExists(atPath: newBackup.appendingPathComponent("itelier-incomplete").path))
            let request = support.appendingPathComponent("iTelier/BackupOperations/" + operation.lastPathComponent + "/request.json")
            let migrated = try JSONSerialization.jsonObject(with: Data(contentsOf: request)) as! [String: Any]
            XCTAssertEqual(migrated["destination"] as? String, newBackup.path)
            XCTAssertEqual(migrated["arguments"] as? [String], ["backup", newBackup.path])
            XCTAssertEqual(migrated["sha256"] as? String, "TEST-HASH")
            XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: request.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        }
    }

    func testInvalidPreferencesDoNotMoveData() throws {
        try fixture { support, downloads, preferences, defaults, domain in
            let source = try directory(support)
            try Data("invalid plist".utf8).write(to: preferences.appendingPathComponent(previousDomain + ".plist"))
            XCTAssertThrowsError(try LegacyAppMigration.prepare(support: support, downloads: downloads, preferences: preferences, defaults: defaults, domain: domain))
            XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
        }
    }

    func testCurrentOperationStateIsNeverRewrittenOnOrdinaryLaunch() throws {
        try fixture { support, downloads, preferences, defaults, domain in
            let operation = support.appendingPathComponent("iTelier/Restores/" + UUID().uuidString)
            try FileManager.default.createDirectory(at: operation, withIntermediateDirectories: true)
            let file = operation.appendingPathComponent("state.json")
            let data = Data("{\"phase\": \"active\"}".utf8)
            try data.write(to: file)
            try LegacyAppMigration.prepare(support: support, downloads: downloads, preferences: preferences, defaults: defaults, domain: domain)
            XCTAssertEqual(try Data(contentsOf: file), data)
        }
    }
}
