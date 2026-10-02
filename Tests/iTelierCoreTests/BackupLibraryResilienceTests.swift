import XCTest
import Foundation
@testable import iTelierCore

final class BackupLibraryResilienceTests: XCTestCase {
    func testUnreadableSessionDoesNotHideReadableBackup() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let session = root.appendingPathComponent(UUID().uuidString)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: session.path)
            try? FileManager.default.removeItem(at: root)
        }
        let readable = root.appendingPathComponent("TEST-IPHONE")
        try fixture(readable)
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: false)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: session.path)
        XCTAssertThrowsError(try FileManager.default.contentsOfDirectory(at: session, includingPropertiesForKeys: nil))
        let backups = try BackupLibrary.scan(root)
        XCTAssertEqual(backups.map(\.directory), [readable.standardizedFileURL.resolvingSymlinksInPath()])
        XCTAssertTrue(backups.first?.complete == true)
    }

    func testUnreadableLibraryRootStillReportsFailure() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
            try? FileManager.default.removeItem(at: root)
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: root.path)
        XCTAssertThrowsError(try BackupLibrary.scan(root))
    }

    func testMissingLibraryReturnsAnEmptyList() throws {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        XCTAssertTrue(try BackupLibrary.scan(missing).isEmpty)
    }

    private func fixture(_ folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        let files: [String: [String: Any]] = [
            "Info.plist": ["Device Name": "Appareil de test", "Product Type": "iPhone14,2", "Product Version": "26.1"],
            "Manifest.plist": ["IsEncrypted": false],
            "Status.plist": ["SnapshotState": "finished"]
        ]
        for (name, value) in files {
            try PropertyListSerialization.data(fromPropertyList: value, format: .binary, options: 0)
                .write(to: folder.appendingPathComponent(name))
        }
        try Data("Base factice pour la validation des métadonnées".utf8).write(to: folder.appendingPathComponent("Manifest.db"))
    }
}
