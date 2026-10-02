import XCTest
import Foundation
@testable import ReScopeCore

final class CoreValidationTests: XCTestCase {
    func testIdentityUsesCarrierProfilesAndMaskedAccount() throws {
        let data = try PropertyListSerialization.data(fromPropertyList: [
            "ProductType": "iPhone17,1", "DeviceName": "Test",
            "CarrierBundleInfoArray": [["CFBundleIdentifier": "com.apple.Example_be", "CFBundleVersion": "72.1"]],
            "NonVolatileRAM": ["fm-account-masked": Data("t•••@e•••.com".utf8)]
        ], format: .xml, options: 0)
        let snapshot = try DeviceParser.normalDevice(id: "TEST-DEVICE", data: data)
        XCTAssertEqual(snapshot.carrierDescription, "Example BE (72.1)")
        XCTAssertEqual(snapshot.maskedAppleAccount, "t•••@e•••.com")
        XCTAssertNil(device().maskedAppleAccount)
        XCTAssertNil(device().carrierDescription)
    }

    func testModernBatteryNestedValuesAndUsableStorage() {
        let metrics = BatteryMetrics(gauge: ["GasGauge.FullChargeCapacity": "100"], registry: [
            "IORegistry.BatteryData.DesignCapacity": "3945", "IORegistry.BatteryData.NominalChargeCapacity": "3677", "IORegistry.BatteryData.AppleRawCurrentCapacity": "1970"])
        XCTAssertEqual(metrics.designCapacity, 3945)
        XCTAssertEqual(metrics.fullCapacity, 3677)
        XCTAssertEqual(metrics.currentCapacity, 1970)
        XCTAssertTrue(metrics.estimatedHealth != nil)
        XCTAssertNil(BatteryMetrics(gauge: ["GasGauge.FullChargeCapacity": "100"]).fullCapacity)
        let info = DeviceInformation(device: device(), disk: ["TotalDataCapacity": "1000", "TotalDataAvailable": "930", "AmountDataAvailable": "690"])
        XCTAssertEqual(info.storageFree, 690)
        XCTAssertEqual(info.storageUsed, 310)
    }

    func testBatteryMetricsValidateUnitsAndSources() {
        let metrics = BatteryMetrics(domain: ["BatteryCurrentCapacity": "38"],
            gauge: ["GasGauge.DesignCapacity": "3500", "GasGauge.NominalChargeCapacity": "3150", "GasGauge.CycleCount": "310"],
            registry: ["IORegistry.AppleRawCurrentCapacity": "1200", "IORegistry.Voltage": "4200", "IORegistry.InstantAmperage": "-200", "IORegistry.AtCriticalLevel": "false", "IORegistry.Serial": "BATTERY-TEST"])
        XCTAssertEqual(metrics.currentCapacity, 1200)
        XCTAssertEqual(metrics.estimatedHealth, 90)
        XCTAssertNil(metrics.declaredHealth)
        XCTAssertEqual(metrics.cycles, 310)
        XCTAssertEqual(metrics.watts, -0.84)
        XCTAssertEqual(metrics.serial, "BATTERY-TEST")
        XCTAssertEqual(metrics.isCritical, false)
        let decoy = BatteryMetrics(domain: ["BatteryCurrentCapacity": "38"], registry: ["IORegistry.CurrentCapacity": "38", "IORegistry.AdapterDetails.Serial": "CHARGER-TEST", "IORegistry.AdapterDetails.Voltage": "9000"])
        XCTAssertNil(decoy.currentCapacity)
        XCTAssertNil(decoy.serial)
        XCTAssertNil(decoy.voltage)
        XCTAssertNil(decoy.estimatedHealth)
        let mixed = BatteryMetrics(gauge: ["GasGauge.DesignCapacity": "3500", "GasGauge.Voltage": "4200"], registry: ["IORegistry.NominalChargeCapacity": "3150", "IORegistry.InstantAmperage": "-200"])
        XCTAssertNil(mixed.estimatedHealth)
        XCTAssertNil(mixed.watts)
        for invalid in ["nan", "inf", "-1", "18446744073709551439"] {
            let bad = BatteryMetrics(gauge: ["GasGauge.CycleCount": invalid, "GasGauge.DesignCapacity": invalid, "GasGauge.MaximumCapacityPercent": invalid])
            XCTAssertNil(bad.cycles)
            XCTAssertNil(bad.designCapacity)
            XCTAssertNil(bad.declaredHealth)
        }
        XCTAssertEqual(BatteryMetrics(domain: ["MaximumCapacityPercent": "92"]).declaredHealth, 92)
    }

    func testStorageBreakdownNeverInventsOrOverflowsCategoryTotals() {
        let info = DeviceInformation(device: device(), disk: ["TotalDataCapacity": "1000", "TotalDataAvailable": "400", "PhotoUsage": "100", "MobileApplicationUsage": "200"])
        XCTAssertEqual(info.storageSegments.map(\.id), ["PhotoUsage", "MobileApplicationUsage", "used", "free"])
        XCTAssertEqual(info.storageSegments.map(\.bytes), [100, 200, 300, 400])
        let inconsistent = DeviceInformation(device: device(), disk: ["TotalDataCapacity": "1000", "TotalDataAvailable": "400", "PhotoUsage": "500", "MobileApplicationUsage": "500"])
        XCTAssertEqual(inconsistent.storageSegments.map(\.id), ["used", "free"])
        XCTAssertEqual(inconsistent.storageSegments.map(\.bytes), [600, 400])
        let missing = DeviceInformation(device: device(), disk: ["TotalDiskCapacity": "1000", "PhotoUsage": "100"])
        XCTAssertTrue(missing.storageSegments.isEmpty)
        let free = DeviceInformation(device: device(), disk: ["TotalDataCapacity": "1000", "TotalDataAvailable": "1000"])
        XCTAssertEqual(free.storageSegments.map(\.bytes), [1000])
    }

    func testLocalisationKeepsInterpolatedDeviceValuesLiteral() {
        let name = "My {1} device · 日本語"
        let text: LocalizedText = "Modèles : \(name)"
        XCTAssertEqual(AppLocalization.render(text, language: "en"), "Models: " + name)
        XCTAssertEqual(AppLocalization.render(text, language: "fr"), "Modèles : " + name)
        XCTAssertEqual(AppLocalization.render("Unknown key", language: "en"), "Unknown key")
        let multiple: LocalizedText = "Le serveur a répondu avec le code HTTP \(503). Réessayez plus tard."
        XCTAssertEqual(AppLocalization.render(multiple, language: "en"), "The server returned HTTP 503. Try again later.")
        for (source, translation) in EnglishStrings.values {
            let pattern = #"\{[0-9]+\}"#
            let regex = try! NSRegularExpression(pattern: pattern)
            func arguments(_ value: String) -> [String] {
                regex.matches(in: value, range: NSRange(value.startIndex..., in: value)).map { (value as NSString).substring(with: $0.range) }.sorted()
            }
            XCTAssertEqual(arguments(source), arguments(translation), source)
        }
    }

    func testVisionCatalogAndNativeRestoreBoundary() throws {
        let identifier = "RealityDevice14,1"
        XCTAssertTrue(FirmwareCatalog.isSupportedIdentifier(identifier))
        XCTAssertTrue(FirmwareCatalog.isSupportedIdentifier("RealityDevice17,1"))
        XCTAssertFalse(FirmwareCatalog.isSupportedIdentifier("RealityDevice14,1/../../"))
        let device = device(board: "n301ap", product: identifier)
        XCTAssertTrue(device.isVisionPro)
        XCTAssertEqual(device.family.systemName, "visionOS")
        XCTAssertFalse(device.family.supportsLocalBackup)
        let ipsw = FirmwareInfo(url: URL(fileURLWithPath: "/tmp/vision.ipsw"), version: "26.0", build: "23M1",
            supportedProductTypes: [identifier], sizeBytes: 1000, sha256: firmwareHash, eraseHardwareModels: ["n301ap"])
        let consent = RestoreApproval(deviceID: device.id, firmwareSHA256: firmwareHash, acknowledgedDataLoss: true)
        XCTAssertThrowsError(try RestoreValidator.validateApproval(device: device, firmware: ipsw, approval: consent))
        let json = Data("""
        [{"identifier":"RealityDevice14,1","name":"Apple Vision Pro"},{"identifier":"Mac14,2","name":"Mac"}]
        """.utf8)
        XCTAssertEqual(try FirmwareCatalog.decodeDevices(json).map(\.identifier), [identifier])
        let releases = Data("""
        [{"osStr":"visionOS","version":"26.0 beta 2","beta":true,"build":"23M1","deviceMap":["RealityDevice14,1"],"sources":[{"type":"ipsw","deviceMap":["RealityDevice14,1"],"size":1000,"links":[{"url":"https://updates.cdn-apple.com/vision.ipsw","active":true}]}]}]
        """.utf8)
        XCTAssertEqual(try AppleDBCatalog.decode(releases, identifier: identifier).count, 1)
        XCTAssertTrue(try AppleDBCatalog.decode(releases, identifier: "RealityDevice17,1").isEmpty)
        XCTAssertTrue(USBDevicePresence.isMobileDevice(vendor: 0x05ac, name: "Apple Vision Pro"))
    }

    func testDeviceInformationUsesMatchingStoragePartitionAndChargeOnly() {
        let info = DeviceInformation(device: device(), battery: ["BatteryCurrentCapacity": "83", "BatteryIsCharging": "true"],
            disk: ["TotalDiskCapacity": "1100", "TotalDataCapacity": "1000", "TotalDataAvailable": "400"])
        XCTAssertEqual(info.storageTotal, 1000)
        XCTAssertEqual(info.storageUsed, 600)
        XCTAssertEqual(info.storageFree, 400)
        XCTAssertEqual(info.batteryPercent, 83)
        XCTAssertEqual(info.isCharging, true)
        let unmatched = DeviceInformation(device: device(), disk: ["TotalDiskCapacity": "1100", "TotalDataAvailable": "400"])
        XCTAssertEqual(unmatched.storageTotal, 1100)
        XCTAssertNil(unmatched.storageUsed)
        XCTAssertNil(unmatched.storageFree)
        for value in ["-1", "101", "nan", "inf", "3200"] {
            XCTAssertNil(DeviceInformation(device: device(), battery: ["BatteryCurrentCapacity": value]).batteryPercent)
        }
        for value in ["-1", "1100", "NaN"] {
            XCTAssertNil(DeviceInformation(device: device(), disk: ["TotalDataCapacity": "1000", "TotalDataAvailable": value]).storageUsed)
        }
        XCTAssertEqual(DeviceInformation(device: device(), disk: ["TotalDataCapacity": "1000", "TotalDataAvailable": "0"]).storageUsed, 1000)
        XCTAssertNil(DeviceInformation(device: device()).batteryPercent)
    }

    private let firmwareHash = String(repeating: "a", count: 64)

    private func backupFixture(_ folder: URL, state: String = "finished", encrypted: Bool = false) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let files: [String: [String: Any]] = [
            "Info.plist": ["Device Name": "Appareil de test", "Product Type": "iPhone14,2", "Product Version": "26.1", "Last Backup Date": Date()],
            "Manifest.plist": ["IsEncrypted": encrypted], "Status.plist": ["SnapshotState": state]
        ]
        for (name, values) in files {
            try PropertyListSerialization.data(fromPropertyList: values, format: .binary, options: 0).write(to: folder.appendingPathComponent(name))
        }
        try Data("fake database for metadata tests".utf8).write(to: folder.appendingPathComponent("Manifest.db"))
    }

    func testBackupMetadataBlocksIncompleteNewerSystemAndWrongFamily() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent(device().id)
        try backupFixture(folder, encrypted: true)
        let backup = try LocalBackup.read(folder)
        XCTAssertTrue(backup.complete); XCTAssertTrue(backup.encrypted)
        XCTAssertNil(backup.restorationIssue(for: device(version: "27.2")))
        XCTAssertNil(backup.restorationIssue(for: device(version: "26.1.0")))
        XCTAssertTrue(backup.restorationIssue(for: device(version: "26.0.9")) != nil)
        XCTAssertTrue(backup.restorationIssue(for: device(product: "iPad8,1", version: "27.2")) != nil)
        XCTAssertTrue(backup.restorationIssue(for: device(mode: .recovery, version: "27.2")) != nil)
        try Data().write(to: root.appendingPathComponent("rescope-incomplete"))
        XCTAssertFalse(try LocalBackup.read(folder).complete)
        try FileManager.default.removeItem(at: root.appendingPathComponent("rescope-incomplete"))
        try backupFixture(folder, state: "inprogress")
        XCTAssertFalse(try LocalBackup.read(folder).complete)
    }

    func testBackupLibraryScansSessionsAndRejectsSymlinkMetadata() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent(UUID().uuidString).appendingPathComponent(device().id)
        try backupFixture(folder)
        XCTAssertEqual(try BackupLibrary.scan(root).count, 1)
        try FileManager.default.moveItem(at: folder.appendingPathComponent("Info.plist"), to: root.appendingPathComponent("external.plist"))
        try FileManager.default.createSymbolicLink(at: folder.appendingPathComponent("Info.plist"), withDestinationURL: root.appendingPathComponent("external.plist"))
        XCTAssertThrowsError(try LocalBackup.read(folder))
        XCTAssertEqual(try BackupLibrary.scan(root).count, 0)
    }

    func testBackupRestoreArgumentsAreTargetedAndNeverEraseOrExposePassword() throws {
        let directory = URL(fileURLWithPath: "/private/tmp").resolvingSymlinksInPath()
        let request = BackupRequest(operation: .restore, target: device(version: "27.2"), directory: directory,
                                    source: device().id, fingerprint: "test", enableEncryption: false)
        let args = try request.arguments()
        XCTAssertEqual(Array(args.prefix(5)), ["-u", device().id, "-s", device().id, "restore"])
        XCTAssertFalse(args.contains("--remove")); XCTAssertFalse(args.contains("--password")); XCTAssertFalse(args.contains("--erase"))
        let unsafe = BackupRequest(operation: .restore, target: device(), directory: directory, source: "../outside", fingerprint: nil, enableEncryption: false)
        XCTAssertThrowsError(try unsafe.arguments())
        let wrongTarget = BackupRequest(operation: .backup, target: device(id: "-bad"), directory: directory, source: nil, fingerprint: nil, enableEncryption: false)
        XCTAssertThrowsError(try wrongTarget.arguments())
    }

    func testBackupWorkerConfirmsCompletionAndCannotReplay() async throws {
        try await runBackupWorkerFixture(engineOutput: "Backup Successful.", expectedCode: 0)
    }
    func testBackupWorkerNeverAcceptsExitZeroWithoutSuccess() async throws {
        try await runBackupWorkerFixture(engineOutput: "ERROR: device refused", expectedCode: 1)
    }
    func testBackupWorkerRejectsChangedTargetBeforeInvokingEngine() async throws {
        try await runBackupWorkerFixture(engineOutput: "Backup Successful.", expectedCode: 1, changedTarget: true)
    }
    func testBackupWorkerRestoresOnlyACompletedUnchangedSnapshot() async throws {
        try await runBackupWorkerFixture(engineOutput: "Restore Successful.", expectedCode: 0, restoring: true)
    }
    func testBackupWorkerRefusesEncryptedRestoreWithoutPassword() async throws {
        try await runBackupWorkerFixture(engineOutput: "Restore Successful.", expectedCode: 1, restoring: true, encrypted: true)
    }
    func testBackupWorkerCancellationKeepsPartialCopyUnrestorable() async throws {
        try await runBackupWorkerFixture(engineOutput: "Backup Successful.", expectedCode: 130, cancel: true)
    }
    private func runBackupWorkerFixture(engineOutput: String, expectedCode: Int32, changedTarget: Bool = false,
                                       restoring: Bool = false, encrypted: Bool = false, cancel: Bool = false) async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: root) }
        let session = root.appendingPathComponent(UUID().uuidString)
        let dataDirectory = root.appendingPathComponent("data")
        try FileManager.default.createDirectory(at: session, withIntermediateDirectories: true)
        try backupFixture(dataDirectory.appendingPathComponent(device().id), encrypted: encrypted)
        if !restoring { try Data().write(to: dataDirectory.appendingPathComponent("rescope-incomplete")) }
        if cancel { try Data().write(to: session.appendingPathComponent("cancel")) }
        let fixture = try LocalBackup.read(dataDirectory.appendingPathComponent(device().id))
        let request = BackupRequest(operation: restoring ? .restore : .backup, target: device(version: "27.2"), directory: dataDirectory,
                                    source: restoring ? fixture.source : nil, fingerprint: restoring ? fixture.fingerprint : nil, enableEncryption: false)
        try RestoreHost.write(request, to: session.appendingPathComponent("request.json"))
        let info = root.appendingPathComponent("info"), engine = root.appendingPathComponent("engine")
        let values: [String: Any] = ["ProductType": "iPhone14,2", "ProductVersion": "27.2", "UniqueChipID": changedTarget ? 987654321 : 123456789]
        let xml = String(decoding: try PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0), as: UTF8.self)
        try Data(("#!/bin/sh\ncat <<'PLIST'\n" + xml + "\nPLIST\n").utf8).write(to: info)
        try Data(("#!/bin/sh\n" + (cancel ? "sleep 2\n" : "") + "printf '%s\\n' '" + engineOutput + "'\ntouch '" + root.appendingPathComponent("invoked").path + "'\n").utf8).write(to: engine)
        for url in [info, engine] { try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path) }
        let code = await BackupHost.runWorker(sessionPath: session.path, root: root, engine: engine, infoTool: info)
        XCTAssertEqual(code, expectedCode)
        XCTAssertEqual(BackupHost.read(session)?.exitCode, expectedCode)
        XCTAssertEqual(try LocalBackup.read(dataDirectory.appendingPathComponent(device().id)).complete, restoring || expectedCode == 0)
        if changedTarget || (restoring && encrypted) { XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("invoked").path)) }
        let second = await BackupHost.runWorker(sessionPath: session.path, root: root, engine: engine, infoTool: info)
        XCTAssertEqual(second, 3)
    }

    func testBackupPasswordEnvironmentIsExplicitAndErrorMessagesPrivate() async throws {
        let result = try await ProcessRunner().run(executable: "/bin/sh", arguments: ["-c", "test \"$BACKUP_PASSWORD\" = 'test-only-secret'"], environmentOverrides: ["BACKUP_PASSWORD": "test-only-secret"])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertTrue(result.stdout.isEmpty); XCTAssertTrue(result.stderr.isEmpty)
        let message = BackupHost.failureMessage("ERROR /Users/private/contacts.vcf SERIAL-123 test-only-secret")
        XCTAssertFalse(message.contains("SERIAL")); XCTAssertFalse(message.contains("secret")); XCTAssertFalse(message.contains("contacts"))
    }

    func testBackupRestoreInterruptionRequiresRecoveryAndPrivateReport() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let journal = try SafetyJournal(directory: root, appVersion: "test")
        try journal.update(SupportContext(operation: .backupRestore, phase: "Restauration des données"))
        let reopened = try SafetyJournal(directory: root, appVersion: "test")
        XCTAssertTrue(reopened.requiresRecovery)
        XCTAssertEqual(reopened.previousInterruption?.context.operation, .backupRestore)
    }


    func testWallpaperFollowsMajorVersionAndDeviceFamily() {
        func resource(_ product: String, _ version: String?) -> String? {
            DeviceWallpaper.resource(for: DeviceSnapshot(id: "example", name: "Exemple", productType: product, osVersion: version))
        }
        XCTAssertNil(resource("iPhone17,1", "27.2 beta 2"))
        XCTAssertEqual(resource("iPhone17,1", "26.0.1"), "iOS26")
        XCTAssertNil(resource("iPad8,1", "27.0"))
        XCTAssertEqual(resource("iPad8,1", "26.5"), "iPadOS26")
        XCTAssertNil(resource("iPhone17,1", nil))
        XCTAssertNil(resource("iPhone17,1", "28.0"))
        XCTAssertEqual(resource("iPhone16,1", "18.7"), "iOS18")
        XCTAssertEqual(resource("iPhone16,1", "17.7.2"), "iOS17")
        XCTAssertEqual(resource("iPhone15,2", "16.7.12"), "iOS16")
        for major in [16, 17, 18, 26] {
            XCTAssertEqual(resource("iPad8,1", "\(major).1"), "iPadOS\(major)")
        }
        XCTAssertNil(resource("iPhone17,1", "15.8.3"))
        XCTAssertNil(resource("Mac16,1", "27.0"))
    }

    func testWallpaperMaskPreservesCameraCutoutAndExterior() {
        let size = 20
        var rgba = [UInt8](repeating: 0, count: size * size * 4)
        func blue(_ x: Int, _ y: Int) {
            let i = (y * size + x) * 4
            rgba[i] = 60; rgba[i + 1] = 140; rgba[i + 2] = 220; rgba[i + 3] = 255
        }
        for y in 2..<18 { for x in 5..<15 { blue(x, y) } }
        for y in 3..<5 { for x in 8..<12 { rgba[(y * size + x) * 4 + 2] = 0 } }
        blue(1, 1) // An unrelated blue reflection must not enter the screen mask.
        let mask = DeviceScreenMask.detect(rgba: rgba, width: size, height: size)
        XCTAssertEqual(mask?.minX, 5)
        XCTAssertEqual(mask?.minY, 2)
        XCTAssertEqual(mask?.width, 10)
        XCTAssertEqual(mask?.height, 16)
        XCTAssertEqual(mask?.alpha[3 * size + 9], 0)
        XCTAssertEqual(mask?.alpha[10 * size + 10], 255)
        XCTAssertEqual(mask?.alpha[size + 1], 0)
        XCTAssertNil(DeviceScreenMask.detect(rgba: [0], width: 20, height: 20))
        XCTAssertNil(DeviceScreenMask.detect(rgba: [UInt8](repeating: 0, count: 1600), width: 20, height: 20))
    }

    private func artworkCatalog() throws -> DeviceArtworkCatalog {
        let entries: [[String: Any]] = [
            ["UTTypeIdentifier": "com.apple.iphone-example-1", "UTTypeDescription": "iPhone exemple",
             "UTTypeTagSpecification": ["com.apple.device-model-code": ["iPhone17,1", "D93AP"]]],
            ["UTTypeIdentifier": "com.apple.iphone-example-4", "UTTypeDescription": "iPhone exemple",
             "UTTypeTagSpecification": ["com.apple.device-model-code": ["iPhone17,1", "D93AP"]]],
            ["UTTypeIdentifier": "com.apple.iphone-other-4", "UTTypeDescription": "Autre modèle",
             "UTTypeTagSpecification": ["com.apple.device-model-code": ["iPhone18,1"]]]
        ]
        return try DeviceArtworkCatalog(data: PropertyListSerialization.data(fromPropertyList: ["UTExportedTypeDeclarations": entries], format: .xml, options: 0))
    }

    func testArtworkUsesExactModelAndEnclosureInsteadOfFrontColor() throws {
        let catalog = try artworkCatalog()
        let phone = DeviceSnapshot(id: "test-device", name: "Exemple", productType: "iPhone17,1",
                                   values: ["DeviceColor": "1", "DeviceEnclosureColor": "4"])
        let match = catalog.match(for: phone)
        XCTAssertEqual(match?.typeIdentifier, "com.apple.iphone-example-4")
        XCTAssertEqual(match?.matchesFinish, true)
        XCTAssertEqual(match?.modelName, "iPhone exemple")
    }

    func testArtworkNeverInventsFinishOrNearestModel() throws {
        let catalog = try artworkCatalog()
        for values in [["DeviceColor": "1"], ["DeviceEnclosureColor": "14"], ["DeviceEnclosureColor": "ERROR: unavailable"], [:]] {
            let phone = DeviceSnapshot(id: "test-device", name: "Exemple", productType: "iPhone17,1", values: values)
            XCTAssertEqual(catalog.match(for: phone)?.matchesFinish, false)
        }
        XCTAssertNil(catalog.match(for: DeviceSnapshot(id: "test-device", name: "Inconnu", productType: "iPhone99,1", values: ["DeviceEnclosureColor": "4"])))
    }

    func testTargetedEnclosureReadIsOptionalValidatedAndPreservesBulkValue() throws {
        let base: [String: Any] = ["ProductType": "iPhone17,1", "DeviceColor": "1"]
        let data = try PropertyListSerialization.data(fromPropertyList: base, format: .xml, options: 0)
        let enriched = try DeviceParser.normalDevice(id: "test-device", data: data, enclosureColor: "4\n")
        XCTAssertEqual(enriched.values["DeviceEnclosureColor"], "4")
        XCTAssertEqual(enriched.values["DeviceColor"], "1")
        XCTAssertNil(try DeviceParser.normalDevice(id: "test-device", data: data, enclosureColor: "ERROR: missing").values["DeviceEnclosureColor"])
        XCTAssertNil(try DeviceParser.normalDevice(id: "test-device", data: data).values["DeviceEnclosureColor"])
        var complete = base; complete["DeviceEnclosureColor"] = "2"
        let existing = try PropertyListSerialization.data(fromPropertyList: complete, format: .xml, options: 0)
        XCTAssertEqual(try DeviceParser.normalDevice(id: "test-device", data: existing, enclosureColor: "4").values["DeviceEnclosureColor"], "2")
    }

    private func referenceReport(date: Date = Date(timeIntervalSince1970: 1_700_000_000), camera: String? = "CAMERA-TEST-1234") -> DiagnosticReport {
        DiagnosticReport(date: date, device: device(), items: [
            .init(id: "serial", title: "Numéro de série", category: .identity, actual: "TEST-SERIAL-1234", status: .read, detail: "Lecture", sensitive: true),
            .init(id: "ecid", title: "ECID", category: .identity, actual: "123456789", status: .read, detail: "Lecture", sensitive: true),
            .init(id: "front-camera-serial", title: "Série de la caméra avant", category: .components, actual: camera,
                  status: camera == nil ? .readFailed : .read, detail: "Lecture", sensitive: true, source: "IORegistry.cam"),
            .init(id: "battery-charge", title: "Charge", category: .battery, actual: "55 %", status: .read, detail: "Évolutif"),
            .init(id: "parts-authenticity", title: "Authenticité", category: .components, status: .manual, detail: "Manuel")
        ])
    }

    private func referenceExport(schema: Int = 3) -> [String: Any] {
        let report = referenceReport()
        return ["application": "ReScope", "schemaVersion": schema, "demo": false, "identifiersIncluded": true,
                "date": ISO8601DateFormatter().string(from: report.date),
                "device": ["productType": report.device.productType, "ecid": "123456789"],
                "checks": report.items.map { ["id": $0.id, "element": $0.title, "status": $0.status.rawValue,
                                               "value": $0.actual ?? NSNull() as Any] }]
    }

    func testReferenceSeparatesInitialReadingFromLaterMatchesAndDifferences() throws {
        let first = referenceReport()
        let reference = try CheckReference.capture(first, demo: false)
        let initial = try reference.applying(to: first, demo: false)
        XCTAssertEqual(initial.items.first?.referenceMatch, .initial)
        XCTAssertTrue(initial.items.allSatisfy { $0.status != .verified })
        let later = referenceReport(date: first.date.addingTimeInterval(60), camera: "CHANGED-TEST-1234")
        let compared = try reference.applying(to: later, demo: false)
        XCTAssertEqual(compared.items.first?.referenceMatch, .same)
        let camera = compared.items.first { $0.id == "front-camera-serial" }
        XCTAssertEqual(camera?.referenceMatch, .different)
        XCTAssertEqual(camera?.expected, "CAMERA-TEST-1234")
        let absent = DiagnosticReport(device: device(), items: [
            .init(id: "front-camera-serial", title: "Caméra", category: .components, status: .unavailable, detail: "Absent", sensitive: false)
        ])
        XCTAssertTrue(try reference.applying(to: absent, demo: false).items[0].sensitive,
                      "A stored serial must remain masked even when the new row has no sensitive value")
        XCTAssertEqual(camera?.actual, "CHANGED-TEST-1234")
        XCTAssertEqual(camera?.status, .read, "Comparison must not rewrite diagnostic status")
    }

    func testReferenceRetainsReadFailuresAndExcludesVolatileAndManualFields() throws {
        let reference = try CheckReference.capture(referenceReport(), demo: false)
        XCTAssertFalse(reference.values.contains { $0.id == "battery-charge" || $0.id == "parts-authenticity" })
        let compared = try reference.applying(to: referenceReport(camera: nil), demo: false)
        let camera = compared.items.first { $0.id == "front-camera-serial" }
        XCTAssertEqual(camera?.referenceMatch, .unreadable)
        XCTAssertEqual(camera?.status, .readFailed)
        XCTAssertNil(camera?.actual)
        XCTAssertEqual(camera?.expected, "CAMERA-TEST-1234")
        let partial = try CheckReference.capture(referenceReport(camera: nil), demo: false)
        XCTAssertFalse(partial.values.contains { $0.id == "front-camera-serial" })
    }

    func testReferenceRejectsOtherDevicesAndDemoMixing() throws {
        let reference = try CheckReference.capture(referenceReport(), demo: false)
        XCTAssertThrowsError(try reference.validate(for: device(ecid: "999999"), demo: false))
        XCTAssertThrowsError(try reference.validate(for: device(), demo: true))
        let missingIdentity = DiagnosticReport(device: device(ecid: nil), items: referenceReport().items)
        XCTAssertThrowsError(try CheckReference.capture(missingIdentity, demo: false))
    }

    func testReferenceImportsVersionTwoAndThreeWithoutTrustingExistingExpectedValues() throws {
        for schema in [2, 3] {
            var json = referenceExport(schema: schema)
            var rows = json["checks"] as! [[String: Any]]
            rows[0]["reference"] = "UNTRUSTED-FACTORY-CLAIM"
            if schema == 2 { for index in rows.indices { rows[index].removeValue(forKey: "id") } }
            json["checks"] = rows
            let imported = try CheckReference.importReport(JSONSerialization.data(withJSONObject: json), for: referenceReport(), demo: false)
            XCTAssertEqual(imported.origin, .importedReport)
            XCTAssertEqual(imported.values.first?.value, "TEST-SERIAL-1234")
            XCTAssertFalse(imported.values.contains { $0.value == "UNTRUSTED-FACTORY-CLAIM" })
        }
    }

    func testReferenceImportRejectsMaskedDuplicateOversizedAndMismatchedReports() throws {
        var masked = referenceExport(); masked["identifiersIncluded"] = false
        XCTAssertThrowsError(try CheckReference.importReport(JSONSerialization.data(withJSONObject: masked), for: referenceReport(), demo: false))
        var duplicate = referenceExport()
        var rows = duplicate["checks"] as! [[String: Any]]; rows.append(rows[0]); duplicate["checks"] = rows
        XCTAssertThrowsError(try CheckReference.importReport(JSONSerialization.data(withJSONObject: duplicate), for: referenceReport(), demo: false))
        var wrong = referenceExport(); wrong["device"] = ["productType": device().productType, "ecid": "99999"]
        XCTAssertThrowsError(try CheckReference.importReport(JSONSerialization.data(withJSONObject: wrong), for: referenceReport(), demo: false))
        XCTAssertThrowsError(try CheckReference.importReport(Data(repeating: 32, count: 1_048_577), for: referenceReport(), demo: false))
        var unsupported = referenceExport(); unsupported["schemaVersion"] = 99
        XCTAssertThrowsError(try CheckReference.importReport(JSONSerialization.data(withJSONObject: unsupported), for: referenceReport(), demo: false))
    }

    func testReferenceStorePersistsPrivateDeviceBoundDataAndPreviousReference() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = CheckReferenceStore(directory: directory)
        XCTAssertNil(try store.load(for: device(), demo: false))
        let reference = try CheckReference.capture(referenceReport(), demo: false)
        try store.save(reference, for: device(), demo: false)
        XCTAssertEqual(try store.load(for: device(), demo: false)?.values.count, 3)
        XCTAssertNil(try store.load(for: device(ecid: "99999"), demo: false))
        let replacement = try CheckReference.capture(referenceReport(camera: "OTHER-1234"), demo: false)
        try store.save(replacement, for: device(), demo: false)
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 2)
        XCTAssertTrue(files.contains { $0.lastPathComponent.hasSuffix(".previous.json") })
        for file in files {
            XCTAssertFalse(file.lastPathComponent.contains("123456789"))
            let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
            XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        }
    }

    func testUSBPresenceExcludesOtherAppleAccessories() {
        XCTAssertTrue(USBDevicePresence.isMobileDevice(vendor: 0x05ac, name: "iPhone"))
        XCTAssertTrue(USBDevicePresence.isMobileDevice(vendor: 0x05ac, name: "Apple Mobile Device (Recovery Mode)"))
        XCTAssertFalse(USBDevicePresence.isMobileDevice(vendor: 0x05ac, name: "Magic Keyboard"))
        XCTAssertFalse(USBDevicePresence.isMobileDevice(vendor: 123, name: "iPhone"))
        XCTAssertFalse(USBDevicePresence.isMobileDevice(vendor: nil, name: "iPhone"))
    }

    func testConnectionDiagnosisSeparatesAbsentUSBFromAuthorizationAndServiceFailures() {
        XCTAssertEqual(DeviceConnectionIssue.classify(presence: .absent, error: nil), .noUSB)
        XCTAssertEqual(DeviceConnectionIssue.classify(presence: .present, error: nil), .usbVisible)
        XCTAssertEqual(DeviceConnectionIssue.classify(presence: .unknown, error: nil), .unknown)
        XCTAssertEqual(DeviceConnectionIssue.classify(presence: .present,
            error: DeviceServiceError.commandFailed("ideviceinfo", -1, "PairingDialogResponsePending PRIVATE-UDID")), .trustRequired)
        XCTAssertEqual(DeviceConnectionIssue.classify(presence: .present,
            error: DeviceServiceError.commandFailed("ideviceinfo", -1, "PasswordProtected")), .locked)
        XCTAssertEqual(DeviceConnectionIssue.classify(presence: .absent,
            error: DeviceServiceError.commandFailed("idevice_id", -1, "usbmuxd connection failed PRIVATE-UDID")), .serviceUnavailable)
        XCTAssertEqual(DeviceConnectionIssue.classify(presence: .absent,
            error: DeviceServiceError.missingTool("ideviceinfo")), .toolsMissing)
        let issue = DeviceConnectionIssue.classify(presence: .present,
            error: DeviceServiceError.commandFailed("ideviceinfo", -1, "PRIVATE-UDID /Users/private/path"))
        XCTAssertFalse(issue.message.contains("PRIVATE"))
        XCTAssertFalse(issue.message.contains("/Users"))
    }

    private func diagnostic(_ id: String, _ object: [String: Any]) throws -> DiagnosticReading {
        try DiagnosticReading.decode(id: id, title: id, data: PropertyListSerialization.data(fromPropertyList: object, format: .xml, options: 0))
    }

    func testComponentSerialsFromTargetedRegistryHaveExactProvenance() throws {
        let camera = try diagnostic("camera-AppleH16CamIn", ["IORegistry": [
            "FrontCameraModuleSerialNumString": "FRONT-TEST-1234", "BackCameraModuleSerialNumString": "REAR-TEST-1234",
            "BackSuperWideCameraModuleSerialNumString": "WIDE-TEST-1234", "BackTeleCameraModuleSerialNumString": "TELE-TEST-1234",
            "FrontIRCameraModuleSerialNumString": "IR-TEST-1234", "FrontIRStructuredLightProjectorSerialNumString": "DOT-TEST-1234",
            "JasperSNUM": "LIDAR-TEST-1234"]])
        let product = try diagnostic("product", ["IORegistry": ["raw-panel-serial-number": Data("PANEL-TEST-1234+RAW+FIELDS\0".utf8),
            "coverglass-serial-number": Data("GLASS-TEST-1234\0".utf8), "ambient-light-sensor-serial-num": Data("LIGHT-1234\0".utf8)]])
        let report = DiagnosticBuilder.report(device: device(), readings: [camera, product])
        for id in ["front-camera-serial", "rear-camera-serial", "ultrawide-camera-serial", "telephoto-camera-serial", "ir-camera-serial", "projector-serial", "lidar-serial", "screen-serial", "coverglass-serial", "ambient-light-serial"] {
            let row = report.items.first { $0.id == id }
            XCTAssertEqual(row?.status, .read, id)
            XCTAssertTrue(row?.sensitive == true, id)
            XCTAssertTrue(row?.source?.contains("IORegistry.") == true, id)
            XCTAssertNil(row?.expected, "A read serial is not a factory reference")
        }
        XCTAssertEqual(report.items.first { $0.id == "screen-serial" }?.actual, "PANEL-TEST-1234+RAW+FIELDS")
    }

    func testBatterySerialDoesNotUseChargerSerialOrUnrelatedNestedSerial() throws {
        let decoy = try diagnostic("registry", ["IORegistry": ["AdapterDetails": ["SerialNumber": "CHARGER-1234", "Serial": "CHARGER-9999"]]])
        let absent = DiagnosticBuilder.report(device: device(), readings: [decoy])
        XCTAssertNil(absent.items.first { $0.id == "battery-serial" }?.actual)
        let battery = try diagnostic("registry", ["IORegistry": ["Serial": "BATTERY-1234", "AdapterDetails": ["SerialNumber": "CHARGER-1234"]]])
        let report = DiagnosticBuilder.report(device: device(), readings: [battery])
        XCTAssertEqual(report.items.first { $0.id == "battery-serial" }?.actual, "BATTERY-1234")
        XCTAssertEqual(report.items.first { $0.id == "battery-serial" }?.source, "registry → IORegistry.Serial")
    }

    func testDiagnosticStatusSeparatesDeprecatedFailedAndMissingFields() throws {
        let deprecated = try diagnostic("gestalt", ["MobileGestalt": ["Status": "MobileGestaltDeprecated", "BatterySerialNumber": "MUST-NOT-READ"]])
        XCTAssertEqual(deprecated.status, .unsupported)
        XCTAssertTrue(deprecated.values.isEmpty)
        let failed = try diagnostic("registry", ["Status": "Failure"])
        XCTAssertEqual(failed.status, .readFailed)
        let empty = try diagnostic("registry", ["IORegistry": [:]])
        XCTAssertEqual(empty.status, .read)
        let failureReport = DiagnosticBuilder.report(device: device(), readings: [deprecated, failed])
        XCTAssertEqual(failureReport.items.first { $0.id == "battery-serial" }?.status, .readFailed)
        let emptyReport = DiagnosticBuilder.report(device: device(), readings: [deprecated, empty])
        XCTAssertEqual(emptyReport.items.first { $0.id == "battery-serial" }?.status, .unavailable)
        let legacyReport = DiagnosticBuilder.report(device: device(), readings: [deprecated])
        XCTAssertEqual(legacyReport.items.first { $0.id == "battery-serial" }?.status, .unsupported)
    }

    func testDiagnosticSerialRejectsBinaryPlaceholdersAndConflictingSources() throws {
        let binary = try diagnostic("product", ["IORegistry": ["raw-panel-serial-number": Data([255, 0, 1, 2, 3, 128])]])
        XCTAssertNil(binary.values["IORegistry.raw-panel-serial-number"])
        for invalid in ["", "00000000", "Unknown", "N/A", "ab\u{1}cd", String(repeating: "x", count: 600)] {
            XCTAssertNil(DiagnosticReading.serial(invalid))
        }
        let first = try diagnostic("camera-AppleH16CamIn", ["IORegistry": ["FrontCameraModuleSerialNumString": "FIRST-1234"]])
        let second = try diagnostic("camera-AppleH13CamIn", ["IORegistry": ["FrontCameraModuleSerialNumString": "OTHER-1234"]])
        let row = DiagnosticBuilder.report(device: device(), readings: [first, second]).items.first { $0.id == "front-camera-serial" }
        XCTAssertEqual(row?.status, .attention)
        XCTAssertNil(row?.actual)
    }

    func testCameraDiscoveryOnlyAcceptsDriverNamesAndLimitsRequests() throws {
        let tree: [String: Any] = ["IORegistry": ["children": [
            ["name": "AppleH16CamIn"], ["name": "AppleH16CamIn"], ["name": "AppleH13CamIn"],
            ["name": "AppleH16CamInUserClient"], ["name": "../../bin/sh"], ["name": "AppleH16CamIn;exit"]]]]
        let data = try PropertyListSerialization.data(fromPropertyList: tree, format: .xml, options: 0)
        XCTAssertEqual(try DiagnosticReading.cameraEntries(data), ["AppleH13CamIn", "AppleH16CamIn"])
    }

    func testDiagnosticErrorSummaryDoesNotLeakRawOutputOrDeviceIdentifiers() {
        let reading = DiagnosticReading.failure(id: "camera-test", title: "Caméra", error: DeviceServiceError.commandFailed("outil", 7, "PRIVATE-UDID /Users/private/path"))
        XCTAssertEqual(reading.status, .readFailed)
        XCTAssertTrue(reading.detail.contains("7"))
        XCTAssertFalse(reading.detail.contains("PRIVATE"))
        XCTAssertFalse(reading.detail.contains("/Users"))
    }

    func testUncleanRestorePersistsRecoveryUntilExplicitAcknowledgement() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = try SafetyJournal(directory: directory, appVersion: "test")
        try first.update(SupportContext(operation: .restoration, phase: "Installation du firmware", restoreMode: .preserveData))
        let restarted = try SafetyJournal(directory: directory, appVersion: "test")
        XCTAssertEqual(restarted.previousInterruption?.kind, .unexpectedExit)
        XCTAssertEqual(restarted.previousInterruption?.context.operation, .restoration)
        XCTAssertTrue(restarted.requiresRecovery)
        try restarted.completeOperation()
        try restarted.closeNormally()
        let third = try SafetyJournal(directory: directory, appVersion: "test")
        XCTAssertNil(third.previousInterruption)
        XCTAssertTrue(third.requiresRecovery, "Closing the app must not clear an unresolved restore")
        try third.acknowledgeRecovery()
        try third.closeNormally()
        let fourth = try SafetyJournal(directory: directory, appVersion: "test")
        XCTAssertFalse(fourth.requiresRecovery)
    }

    func testSupportReportUsesFilteredFieldsAndBoundedDescription() throws {
        let context = SupportContext(operation: .firmwareDownload, deviceModel: "iPhone18,1", systemVersion: "27.2",
            firmwareVersion: "/Users/private/file.ipsw", firmwareBuild: "secret serial", restoreMode: .preserveData)
        let report = SupportReport(kind: .error, appVersion: "test", context: context, errorCode: 42)
        let object = try JSONSerialization.jsonObject(with: report.json(description: String(repeating: "x", count: 5_000))) as! [String: Any]
        let values = object["context"] as! [String: Any]
        XCTAssertEqual(values["deviceModel"] as? String, "iPhone18,1")
        XCTAssertNil(values["firmwareVersion"])
        XCTAssertNil(values["firmwareBuild"])
        XCTAssertEqual((object["userDescription"] as? String)?.count, 4_000)
        XCTAssertEqual(object["errorCode"] as? Int, 42)
        for key in ["serialNumber", "ecid", "udid", "deviceName", "log", "path"] {
            XCTAssertNil(object[key]); XCTAssertNil(values[key])
        }
    }

    func testJournalRecordsFailureBeforeClearingOperationAndRejectsCorruption() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let journal = try SafetyJournal(directory: directory, appVersion: "test")
        try journal.update(SupportContext(operation: .firmwareInspection, phase: "Vérification du firmware"))
        let report = try journal.recordFailure(code: 7)
        try journal.completeOperation(); try journal.closeNormally()
        let restarted = try SafetyJournal(directory: directory, appVersion: "test")
        XCTAssertEqual(restarted.latestReport?.id, report.id)
        XCTAssertEqual(restarted.latestReport?.context.operation, .firmwareInspection)
        XCTAssertFalse(restarted.requiresRecovery)
        let session = directory.appendingPathComponent("session.json")
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: session.path)[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        try Data(repeating: 65, count: 40_000).write(to: session)
        XCTAssertThrowsError(try SafetyJournal(directory: directory, appVersion: "test"))
    }

    func testRestoreHostRefusesUnapprovedArgumentsAndCrossSessionState() throws {
        let url = URL(fileURLWithPath: "/tmp/firmware.ipsw")
        let update = try RestoreValidator.arguments(ecid: "1234", url: url, mode: .preserveData, upgradeVariant: RestoreMode.upgradeVariant)
        XCTAssertEqual(try RestoreHost.validateArguments(update).mode, .preserveData)
        XCTAssertEqual(try RestoreHost.validateArguments(RestoreValidator.arguments(ecid: "1234", url: url, mode: .erase)).mode, .erase)
        for args in [[], ["-e"], update + ["--erase"], ["--variant", "Customer Erase Install (IPSW)"] + Array(update.dropFirst(2))] {
            XCTAssertThrowsError(try RestoreHost.validateArguments(args))
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let state = RestoreHostSnapshot(sessionID: UUID().uuidString, phase: "Test", finished: true, exitCode: 0, updatedAt: Date(), log: [])
        try RestoreHost.write(state, to: directory.appendingPathComponent("state.json"))
        XCTAssertNil(RestoreHost.read(directory))
    }

    func testRestoreHostLockPreventsConcurrentWritesAndReleases() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        XCTAssertFalse(RestoreHost.isLocked(root: root))
        var owner: HostLock? = try HostLock(root: root, acquire: true)
        XCTAssertTrue(RestoreHost.isLocked(root: root))
        XCTAssertThrowsError(try HostLock(root: root, acquire: true))
        withExtendedLifetime(owner) {}
        owner = nil
        XCTAssertFalse(RestoreHost.isLocked(root: root))
    }

    func testBundledUSBToolsWorkWithoutHomebrewAndIgnoreUnknownNames() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let bundle = root.appendingPathComponent("ReScope.app")
        let helpers = bundle.appendingPathComponent("Contents/Helpers")
        try FileManager.default.createDirectory(at: helpers, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let tool = helpers.appendingPathComponent("idevice_id")
        try Data("#!/bin/sh\nexit 0\n".utf8).write(to: tool)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: tool.path)
        XCTAssertEqual(ToolResolver.resolve("idevice_id", bundleURL: bundle, environment: ["PATH": "relative:."]), tool.path)
        XCTAssertNil(ToolResolver.resolve("../idevice_id", bundleURL: bundle, environment: [:]))
        XCTAssertNil(ToolResolver.resolve("unknown_tool", bundleURL: bundle, environment: [:]))
    }

    private func device(id: String = "00008110-001234567890001E", ecid: String? = "123456789",
                        board: String? = "d63ap", product: String = "iPhone14,2",
                        mode: DeviceMode = .normal, version: String? = nil, build: String? = nil) -> DeviceSnapshot {
        DeviceSnapshot(id: id, name: "iPhone de test", productType: product, osVersion: version, buildVersion: build, ecid: ecid,
                       hardwareModel: board, mode: mode)
    }

    private func firmware(boards: [String] = ["d63ap"], updateBoards: [String] = []) -> FirmwareInfo {
        FirmwareInfo(url: URL(fileURLWithPath: "/tmp/firmware.ipsw"), version: "18.0", build: "22A3354",
                     supportedProductTypes: ["iPhone14,2"], sizeBytes: 1_000, sha256: firmwareHash,
                     eraseHardwareModels: boards, updateVariants: Dictionary(uniqueKeysWithValues: updateBoards.map { ($0, RestoreMode.upgradeVariant) }))
    }

    private func approval(acknowledged: Bool = true) -> RestoreApproval {
        RestoreApproval(deviceID: device().id, firmwareSHA256: firmwareHash, acknowledgedDataLoss: acknowledged)
    }

    private func manifest(erase: Bool = true, complete: Bool = true) throws -> Data {
        let components: [String: Any] = [
            "RestoreRamDisk": ["Info": ["Path": "ramdisk.dmg"]],
            "OS": ["Info": ["Path": "filesystem.dmg"]],
            "iBSS": ["Info": ["Path": "Firmware/dfu/iBSS.img4"]],
            "iBEC": ["Info": ["Path": "Firmware/dfu/iBEC.img4"]]
        ]
        let object: [String: Any] = [
            "ProductVersion": "18.0", "ProductBuildVersion": "22A3354",
            "SupportedProductTypes": ["iPhone14,2"],
            "BuildIdentities": [[
                "Info": ["DeviceClass": "D63AP", "RestoreBehavior": erase ? "Erase" : "Update",
                         "Variant": erase ? "Customer Erase Install (IPSW)" : "Customer Upgrade Install (IPSW)"],
                "Manifest": complete ? components : ["OS": [:]]
            ]]
        ]
        return try PropertyListSerialization.data(fromPropertyList: object, format: .xml, options: 0)
    }

    func testECIDCanonicalizationRejectsAmbiguityAndInjection() {
        XCTAssertEqual(DeviceParser.normalizedECID("0x00000000075bcd15"), "123456789")
        XCTAssertEqual(DeviceParser.normalizedECID("000123456789"), "123456789")
        XCTAssertEqual(DeviceParser.normalizedECID("18446744073709551615"), "18446744073709551615")
        for invalid in ["0", "0x0", "-1", "123; rm", "123 456", "123\n-i 999", "18446744073709551616", "abcdef"] {
            XCTAssertNil(DeviceParser.normalizedECID(invalid), invalid)
        }
    }

    func testNormalModeParsesPlistAndPreservesNumericZero() throws {
        let data = try PropertyListSerialization.data(fromPropertyList: [
            "ProductType": "iPhone14,2", "HardwareModel": "D63AP", "UniqueChipID": UInt64(123456789),
            "DeviceName": "Mon iPhone", "BatteryCurrentCapacity": 0, "BatteryIsCharging": false
        ], format: .xml, options: 0)
        let parsed = try DeviceParser.normalDevice(id: device().id, data: data)
        XCTAssertEqual(parsed.ecid, "123456789")
        XCTAssertEqual(parsed.values["BatteryCurrentCapacity"], "0")
        XCTAssertEqual(parsed.values["BatteryIsCharging"], "false")
        XCTAssertThrowsError(try DeviceParser.normalDevice(id: "bad\n-u x", data: data))
        XCTAssertThrowsError(try DeviceParser.normalDevice(id: device().id, data: Data("not plist".utf8)))
    }

    func testRecoveryDeviceRetainsBoardAndNormalizedIdentity() throws {
        let recovery = try DeviceParser.recoveryDevice("ECID: 0x075bcd15\nMODE: Recovery\nPRODUCT: iPhone14,2\nMODEL: d63ap\nNAME: iPhone 13 Pro\n")
        XCTAssertEqual(recovery.mode, .recovery)
        XCTAssertEqual(recovery.id, "ecid-123456789")
        XCTAssertEqual(recovery.hardwareModel, "d63ap")
        let dfu = try DeviceParser.recoveryDevice("ECID: 123456789\nMODE: DFU\nPRODUCT: iPhone14,2\nMODEL: d63ap\n")
        XCTAssertEqual(dfu.mode, .dfu)
        XCTAssertThrowsError(try DeviceParser.recoveryDevice("ECID: 0x1\nMODE: Unknown\nPRODUCT: iPhone14,2"))
    }

    func testFirmwareRequiresModelBoardAndExplicitCompleteEraseIdentity() throws {
        let parsed = try FirmwareManifest.parse(manifest())
        XCTAssertEqual(parsed.eraseHardwareModels, ["d63ap"])
        let update = try FirmwareManifest.parse(manifest(erase: false))
        XCTAssertEqual(update.updateHardwareModels, ["d63ap"])
        XCTAssertTrue(update.eraseHardwareModels.isEmpty)
        XCTAssertThrowsError(try FirmwareManifest.parse(manifest(complete: false)))
        var unsafe = try DeviceParser.plist(manifest())
        var identities = unsafe["BuildIdentities"] as! [[String: Any]]
        var components = identities[0]["Manifest"] as! [String: Any]
        components["OS"] = ["Info": ["Path": "../outside.dmg"]]
        identities[0]["Manifest"] = components
        unsafe["BuildIdentities"] = identities
        let unsafeData = try PropertyListSerialization.data(fromPropertyList: unsafe, format: .xml, options: 0)
        XCTAssertThrowsError(try FirmwareManifest.parse(unsafeData))
        XCTAssertTrue(firmware().supports(device(board: "D63AP")))
        XCTAssertFalse(firmware().supports(device(board: nil)))
        XCTAssertFalse(firmware().supports(device(board: "d64ap")))
        XCTAssertFalse(firmware().supports(device(product: "iPhone14,3")))
        XCTAssertFalse(firmware(boards: []).supports(device()))
    }

    func testRestoreApprovalIsBoundToDeviceFirmwareAndDataLoss() throws {
        XCTAssertEqual(try RestoreValidator.validateApproval(device: device(), firmware: firmware(), approval: approval()), "123456789")
        XCTAssertThrowsError(try RestoreValidator.validateApproval(device: device(), firmware: firmware(), approval: approval(acknowledged: false)))
        XCTAssertThrowsError(try RestoreValidator.validateApproval(device: device(id: "different"), firmware: firmware(), approval: approval()))
        XCTAssertThrowsError(try RestoreValidator.validateApproval(device: device(ecid: nil), firmware: firmware(), approval: approval()))
        XCTAssertThrowsError(try RestoreValidator.validateApproval(device: device(), firmware: firmware(),
            approval: RestoreApproval(deviceID: device().id, firmwareSHA256: String(repeating: "b", count: 64), acknowledgedDataLoss: true)))
    }

    func testReconnectAllowsModeChangeButRejectsDuplicateAndDifferentHardware() throws {
        let connected = device(id: "ecid-123456789", mode: .recovery)
        XCTAssertEqual(try RestoreValidator.reconnectedDevice(original: device(), ecid: "123456789", candidates: [connected]).mode, .recovery)
        XCTAssertThrowsError(try RestoreValidator.reconnectedDevice(original: device(), ecid: "123456789", candidates: []))
        XCTAssertThrowsError(try RestoreValidator.reconnectedDevice(original: device(), ecid: "123456789", candidates: [connected, connected]))
        XCTAssertThrowsError(try RestoreValidator.reconnectedDevice(original: device(), ecid: "123456789", candidates: [device(board: "d64ap")]))
    }

    func testRestoreArgumentsDoNotContainBypassOptionsOrShellInterpolation() throws {
        let url = URL(fileURLWithPath: "/tmp/a file $(touch nope);.ipsw")
        XCTAssertEqual(try RestoreValidator.arguments(ecid: "0x075bcd15", url: url),
                       ["-e", "-y", "-P", "-i", "123456789", url.path])
        XCTAssertThrowsError(try RestoreValidator.arguments(ecid: "0", url: url))
        XCTAssertThrowsError(try RestoreValidator.arguments(ecid: "1", url: URL(string: "https://example.com/file.ipsw")!))
    }

    func testZeroChargeIsNotReportedAsZeroBatteryHealth() {
        let report = DiagnosticBuilder.report(device: device(), battery: ["BatteryCurrentCapacity": "0", "BatteryIsCharging": "false"])
        XCTAssertEqual(report.items.first(where: { $0.id == "battery-charge" })?.actual, "0 %")
        XCTAssertEqual(report.items.first(where: { $0.id == "battery-charge" })?.status, .read)
        XCTAssertNil(report.items.first(where: { $0.id == "battery-health" })?.actual)
        XCTAssertEqual(report.items.first(where: { $0.id == "battery-health" })?.status, .unavailable)
        XCTAssertTrue(report.items.allSatisfy { $0.expected == nil && $0.status != .verified })
        XCTAssertEqual(report.items.first(where: { $0.id == "activation-lock" })?.status, .manual)
    }

    func testHealthEstimateUsesValidIndependentCapacityReadings() {
        let report = DiagnosticBuilder.report(device: device(), gauge: [
            "GasGauge.NominalChargeCapacity": "2700", "GasGauge.DesignCapacity": "3000", "GasGauge.CycleCount": "310"
        ])
        XCTAssertEqual(report.items.first(where: { $0.id == "battery-health" })?.actual, "90 %")
        XCTAssertEqual(report.items.first(where: { $0.id == "battery-cycles" })?.actual, "310")
        let missing = DiagnosticBuilder.report(device: device(), gauge: ["DesignCapacity": "0", "NominalChargeCapacity": "0"])
        XCTAssertNil(missing.items.first(where: { $0.id == "battery-health" })?.actual)
    }

    func testBatteryAttentionThresholdAndPartialReportStayHonest() {
        for (capacity, expected) in [("79", CheckStatus.attention), ("80", .read)] {
            let report = DiagnosticBuilder.report(device: device(), battery: ["MaximumCapacityPercent": capacity])
            let health = report.items.first(where: { $0.id == "battery-health" })
            XCTAssertEqual(health?.status, expected)
            XCTAssertNil(health?.expected)
            XCTAssertEqual(report.items.first(where: { $0.id == "battery-cycles" })?.status, .unavailable)
            if expected == .attention { XCTAssertTrue(health?.detail.contains("indicatif") == true) }
        }
        let estimate = DiagnosticBuilder.report(device: device(), gauge: ["NominalChargeCapacity": "2300", "DesignCapacity": "3000"])
        XCTAssertEqual(estimate.items.first(where: { $0.id == "battery-health" })?.status, .attention)
        let zero = DiagnosticBuilder.report(device: device(), battery: ["MaximumCapacityPercent": "0"])
        XCTAssertEqual(zero.items.first(where: { $0.id == "battery-health" })?.status, .unavailable)
    }

    func testProgressRejectsInvalidFractionsAndTracksUpstreamStep() {
        let event = RestoreValidator.progressEvent("progress: 2 0.42")
        XCTAssertEqual(event?.progress, 0.42)
        XCTAssertEqual(event?.phase, "Envoi du système de fichiers")
        for line in ["progress: 2 nan", "progress: 2 inf", "progress: 2 1.5", "progress: -1 0.5", "text 100%"] {
            XCTAssertNil(RestoreValidator.progressEvent(line))
        }
    }

    func testSHA256StreamingMatchesKnownDigest() async throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".ipsw")
        try Data("abc".utf8).write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }
        let result = try await FirmwareInspector.sha256(url)
        XCTAssertEqual(result, "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }

    func testArchiveInspectionReadsManifestWithoutExtractingFirmware() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let plistURL = directory.appendingPathComponent("BuildManifest.plist")
        try manifest().write(to: plistURL)
        let url = directory.appendingPathComponent("fixture.ipsw")
        let zipped = try await ProcessRunner().run(executable: "/usr/bin/zip", arguments: ["-q", url.path, "BuildManifest.plist"], workingDirectory: directory)
        XCTAssertEqual(zipped.exitCode, 0)
        let inspected = try await DeviceService().inspectIPSW(at: url)
        XCTAssertEqual(inspected.version, "18.0")
        XCTAssertEqual(inspected.build, "22A3354")
        XCTAssertTrue(inspected.supports(device()))
        XCTAssertEqual(inspected.sha256.count, 64)
        XCTAssertGreaterThan(inspected.sizeBytes, 0)
    }

    private func cachedFirmwareFixture(in directory: URL) async throws -> (URL, FirmwareRelease) {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try manifest().write(to: directory.appendingPathComponent("BuildManifest.plist"))
        try Data("CACHE_PAYLOAD_0123456789".utf8).write(to: directory.appendingPathComponent("payload.bin"))
        let file = directory.appendingPathComponent("renamed-local-copy.ipsw")
        let result = try await ProcessRunner().run(executable: "/usr/bin/zip",
            arguments: ["-0q", file.path, "BuildManifest.plist", "payload.bin"], workingDirectory: directory)
        XCTAssertEqual(result.exitCode, 0)
        let info = try await FirmwareInspector.inspect(file, runner: ProcessRunner())
        return (file, FirmwareRelease(identifier: "iPhone14,2", version: "18.0", buildID: "22A3354",
            url: URL(string: "https://updates.cdn-apple.com/original.ipsw")!, fileSize: info.sizeBytes,
            signed: true, sha256: info.sha256))
    }

    func testExistingFirmwareRediscoveredWithoutSessionStateOrOriginalName() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let (file, release) = try await cachedFirmwareFixture(in: directory)
        for _ in 0..<2 {
            let existing = try await FirmwareLibrary.existingFirmware(for: release, in: directory)
            XCTAssertEqual(existing?.url.resolvingSymlinksInPath(), file.resolvingSymlinksInPath())
            XCTAssertEqual(existing?.sha256, release.sha256)
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasSuffix(".ipsw") }.count, 1)
    }

    func testExistingFirmwareRejectsWrongVersionBuildModelSizeAndDigest() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let (_, release) = try await cachedFirmwareFixture(in: directory)
        for mismatch in ["version", "build", "model", "size", "digest"] {
            let wrong = FirmwareRelease(identifier: mismatch == "model" ? "iPad13,1" : release.identifier,
                version: mismatch == "version" ? "18.1" : release.version,
                buildID: mismatch == "build" ? "22A3355" : release.buildID, url: release.url,
                fileSize: release.fileSize + (mismatch == "size" ? 1 : 0), signed: true,
                sha256: mismatch == "digest" ? String(repeating: "0", count: 64) : release.sha256)
            let existing = try await FirmwareLibrary.existingFirmware(for: wrong, in: directory)
            XCTAssertNil(existing, mismatch)
        }
    }

    func testExistingFirmwareChecksSHA1AndEveryArchiveMemberWithoutCatalogueDigest() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let (file, release) = try await cachedFirmwareFixture(in: directory)
        let digest = try await FirmwareInspector.sha1(file)
        for expected in [digest, String(repeating: "0", count: 40)] {
            let legacy = FirmwareRelease(identifier: release.identifier, version: release.version, buildID: release.buildID,
                url: release.url, fileSize: release.fileSize, signed: true, sha1: expected)
            let existing = try await FirmwareLibrary.existingFirmware(for: legacy, in: directory)
            XCTAssertEqual(existing != nil, expected == digest)
        }
        let noDigest = FirmwareRelease(identifier: release.identifier, version: release.version, buildID: release.buildID,
            url: release.url, fileSize: release.fileSize, signed: true)
        let valid = try await FirmwareLibrary.existingFirmware(for: noDigest, in: directory)
        XCTAssertEqual(valid?.url.resolvingSymlinksInPath(), file.resolvingSymlinksInPath())
        var bytes = try Data(contentsOf: file)
        guard let payload = bytes.range(of: Data("CACHE_PAYLOAD_0123456789".utf8)) else { XCTFail("Missing fixture payload"); return }
        bytes[payload.lowerBound] ^= 1 // Same size, intact manifest, damaged member CRC.
        try bytes.write(to: file)
        let damaged = try await FirmwareLibrary.existingFirmware(for: noDigest, in: directory)
        XCTAssertNil(damaged)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))
    }

    func testExistingFirmwareIgnoresPartialFilesAndSymlinksAndHonorsCancellation() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let (file, release) = try await cachedFirmwareFixture(in: directory)
        let partial = directory.appendingPathComponent("unfinished.ipsw.partial")
        try FileManager.default.moveItem(at: file, to: partial)
        try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("link.ipsw"), withDestinationURL: partial)
        let existing = try await FirmwareLibrary.existingFirmware(for: release, in: directory)
        XCTAssertNil(existing)
        let cancelled = Task {
            withUnsafeCurrentTask { $0?.cancel() }
            return try await FirmwareLibrary.existingFirmware(for: release, in: directory)
        }
        do { _ = try await cancelled.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
    }

    func testProcessRunnerPassesLiteralArgumentsAndBoundsOutput() async throws {
        let literal = "$(touch nope); spaces"
        let result = try await ProcessRunner().run(executable: "/usr/bin/printf", arguments: ["%s", literal])
        XCTAssertEqual(String(decoding: result.stdout, as: UTF8.self), literal)
        do {
            _ = try await ProcessRunner().run(executable: "/usr/bin/printf", arguments: ["%s", String(repeating: "a", count: 5000)], outputLimit: 128)
            XCTFail("Expected bounded output failure")
        } catch let error as DeviceServiceError {
            guard case .outputTooLarge = error else { return XCTFail("Unexpected error: \(error)") }
        }
    }

    func testReadProcessHasBoundedTimeoutAndCancellation() async throws {
        do {
            _ = try await ProcessRunner().run(executable: "/bin/sleep", arguments: ["5"], timeout: 0.05)
            XCTFail("Expected timeout")
        } catch let error as DeviceServiceError {
            guard case .timedOut = error else { return XCTFail("Unexpected error: \(error)") }
        }
        let task = Task { try await ProcessRunner().run(executable: "/bin/sleep", arguments: ["5"]) }
        try await Task.sleep(nanoseconds: 50_000_000)
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
    }

    func testCatalogDecodesOnlyIPhoneAndIPadAndDeduplicates() throws {
        let data = Data("""
        [{"identifier":"iPhone14,2","name":"iPhone 13 Pro"},
         {"identifier":"iPad14,3","name":"iPad Pro"},
         {"identifier":"Mac14,2","name":"Mac"},
         {"identifier":"iPhone14,2","name":"Duplicate"}]
        """.utf8)
        let devices = try FirmwareCatalog.decodeDevices(data)
        XCTAssertEqual(devices.count, 2)
        XCTAssertEqual(Set(devices.map(\.identifier)), Set(["iPhone14,2", "iPad14,3"]))
        XCTAssertFalse(FirmwareCatalog.isSupportedIdentifier("iPhone14,2/../../devices"))
    }

    func testCatalogDecodesInt64HashesDatesAndRejectsStaleTarget() throws {
        let data = Data("""
        {"identifier":"iPhone14,2","firmwares":[
          {"identifier":"iPhone14,2","version":"18.0","buildid":"22A3354","filesize":8412876800,
           "url":"https://updates.cdn-apple.com/firmware.ipsw","signed":true,"releasedate":"2024-09-16T17:00:00.123Z",
           "sha256sum":"AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA","sha1sum":"bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"},
          {"identifier":"iPhone14,2","version":"17.0","buildid":"21A329","filesize":8000000000,
           "url":"https://secure-appldnld.apple.com/old.ipsw","signed":false,"releasedate":null} ]}
        """.utf8)
        let releases = try FirmwareCatalog.decodeFirmwares(data, identifier: "iPhone14,2")
        XCTAssertEqual(releases.count, 2)
        XCTAssertEqual(releases[0].fileSize, 8_412_876_800)
        XCTAssertEqual(releases[0].sha256, firmwareHash)
        XCTAssertTrue(releases[0].releaseDate != nil)
        XCTAssertFalse(releases[1].signed)
        XCTAssertNil(releases[1].sha256)
        XCTAssertThrowsError(try FirmwareCatalog.decodeFirmwares(data, identifier: "iPad14,3"))
        let encoded = try JSONEncoder().encode(releases[0])
        XCTAssertEqual(try JSONDecoder().decode(FirmwareRelease.self, from: encoded), releases[0])
    }

    func testAppleDBIncludesBetaIPSWForExactDeviceAndSeparatesDisplayVersion() throws {
        let data = Data("""
        [{"osStr":"iOS","version":"27.2 beta 2","build":"24B5089g","released":"2026-09-21",
          "beta":true,"deviceMap":["iPhone18,1","iPhone18,2"],"signed":["iPhone18,1"],"sources":[
            {"type":"ipsw","deviceMap":["iPhone18,1"],"size":13029948451,
             "links":[{"url":"https://updates.cdn-apple.com/beta.ipsw","active":true,"preferred":true}]},
            {"type":"ota","deviceMap":["iPhone18,1"],"size":2000,
             "links":[{"url":"https://updates.cdn-apple.com/ota.zip"}]},
            {"type":"ipsw","deviceMap":["iPhone18,2"],"size":1000,
             "links":[{"url":"https://updates.cdn-apple.com/other.ipsw"}]}]}]
        """.utf8)
        let values = try AppleDBCatalog.decode(data, identifier: "iPhone18,1")
        XCTAssertEqual(values.count, 1)
        XCTAssertEqual(values[0].version, "27.2") // ProductVersion in BuildManifest has no beta suffix.
        XCTAssertEqual(values[0].displayVersion, "27.2 bêta 2")
        XCTAssertTrue(values[0].signed)
        XCTAssertEqual(values[0].fileSize, 13_029_948_451)
        XCTAssertFalse(try AppleDBCatalog.decode(data, identifier: "iPhone18,2")[0].signed)
        XCTAssertTrue(try AppleDBCatalog.decode(data, identifier: "iPad14,3").isEmpty)
        XCTAssertEqual(try JSONDecoder().decode(FirmwareRelease.self, from: JSONEncoder().encode(values[0])), values[0])
        let unsigned = Data(String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\"signed\":[\"iPhone18,1\"],", with: "").utf8)
        XCTAssertFalse(try AppleDBCatalog.decode(unsigned, identifier: "iPhone18,1")[0].signed)
        let unsafe = Data(String(decoding: data, as: UTF8.self).replacingOccurrences(of: "https://updates.cdn-apple.com/beta.ipsw", with: "https://evil.example/beta.ipsw").utf8)
        XCTAssertTrue(try AppleDBCatalog.decode(unsafe, identifier: "iPhone18,1").isEmpty)
    }

    func testCatalogKeepsWorkingWhenOneSourceFailsAndDeduplicates() throws {
        let release = stubRelease("ok")
        let degraded = try FirmwareCatalog.merge(publicResult: .success([release]), appleDBResult: .failure(FirmwareTransferError.httpStatus(503)))
        XCTAssertEqual(degraded.releases, [release])
        XCTAssertEqual(degraded.warnings.count, 1)
        let merged = try FirmwareCatalog.merge(publicResult: .success([release]), appleDBResult: .success([release]))
        XCTAssertEqual(merged.releases.count, 1)
        XCTAssertThrowsError(try FirmwareCatalog.merge(publicResult: .failure(FirmwareTransferError.invalidMetadata), appleDBResult: .failure(FirmwareTransferError.invalidMetadata)))
    }

    func testPreserveDataRequiresUpdateIdentityVersionAndSeparateApproval() throws {
        let target = device(version: "18.0", build: "22A3354")
        let ipsw = firmware(updateBoards: ["d63ap"])
        let consent = RestoreApproval(deviceID: target.id, firmwareSHA256: firmwareHash, acknowledgedDataLoss: false,
                                      mode: .preserveData, acknowledgedPreservationRisk: true)
        XCTAssertEqual(try RestoreValidator.validateApproval(device: target, firmware: ipsw, approval: consent), "123456789")
        XCTAssertThrowsError(try RestoreValidator.validateApproval(device: target, firmware: firmware(), approval: consent))
        XCTAssertThrowsError(try RestoreValidator.validateApproval(device: device(), firmware: ipsw, approval: consent))
        XCTAssertThrowsError(try RestoreValidator.validateApproval(device: device(mode: .recovery, version: "18.0", build: "22A3354"), firmware: ipsw, approval: consent))
        XCTAssertThrowsError(try RestoreValidator.validateApproval(device: target, firmware: ipsw,
            approval: RestoreApproval(deviceID: target.id, firmwareSHA256: firmwareHash, acknowledgedDataLoss: true, mode: .preserveData)))
        let args = try RestoreValidator.arguments(ecid: "123456789", url: ipsw.url, mode: .preserveData, upgradeVariant: ipsw.upgradeVariant(for: target))
        XCTAssertEqual(args, ["--variant", "Customer Upgrade Install (IPSW)", "-y", "-P", "-i", "123456789", ipsw.url.path])
        XCTAssertFalse(args.contains("-e"))
        XCTAssertThrowsError(try RestoreValidator.arguments(ecid: "123456789", url: ipsw.url, mode: .preserveData))
        XCTAssertThrowsError(try RestoreValidator.arguments(ecid: "123456789", url: ipsw.url, mode: .preserveData, upgradeVariant: "Customer Erase Install (IPSW)"))
    }

    func testBetaManifestsKeepTheExactDeveloperUpgradeVariant() throws {
        let beta = Data(String(decoding: try manifest(erase: false), as: UTF8.self)
            .replacingOccurrences(of: "Customer Upgrade Install", with: "Developer Upgrade Install").utf8)
        let parsed = try FirmwareManifest.parse(beta)
        XCTAssertEqual(parsed.updateVariants["d63ap"], "Developer Upgrade Install (IPSW)")
        let args = try RestoreValidator.arguments(ecid: "123456789", url: firmware().url,
            mode: .preserveData, upgradeVariant: parsed.updateVariants["d63ap"])
        XCTAssertEqual(Array(args.prefix(2)), ["--variant", "Developer Upgrade Install (IPSW)"])
        XCTAssertFalse(args.contains("-e"))
    }

    func testPreservationRejectsDowngradesAndOlderBetas() {
        XCTAssertTrue(RestoreValidator.canUpdate(fromVersion: "27.2", build: "24B5089g", toVersion: "27.2", build: "24B5089g"))
        XCTAssertFalse(RestoreValidator.canUpdate(fromVersion: "27.2", build: "24B5089g", toVersion: "27.1", build: "24A100"))
        XCTAssertFalse(RestoreValidator.canUpdate(fromVersion: "27.2", build: "24B5089g", toVersion: "27.2", build: "24B5084k"))
        XCTAssertTrue(RestoreValidator.canUpdate(fromVersion: "27.2", build: "24B5089g", toVersion: "27.2", build: "24B91"))
        XCTAssertFalse(RestoreValidator.canUpdate(fromVersion: "27.2", build: "24B91", toVersion: "27.2", build: "24B5089g"))
        XCTAssertFalse(RestoreValidator.canUpdate(fromVersion: "unknown", build: "24B91", toVersion: "27.2", build: "24B5089g"))
    }

    func testUpdateManifestNeverAcceptsEraseOrIncompleteRamdiskAsUpgrade() throws {
        var plist = try DeviceParser.plist(manifest(erase: false))
        var identities = plist["BuildIdentities"] as! [[String: Any]]
        var info = identities[0]["Info"] as! [String: Any]
        info["Variant"] = "Customer Erase Install (IPSW)"
        identities[0]["Info"] = info; plist["BuildIdentities"] = identities
        XCTAssertThrowsError(try FirmwareManifest.parse(PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)))
        plist = try DeviceParser.plist(manifest(erase: false))
        identities = plist["BuildIdentities"] as! [[String: Any]]
        var components = identities[0]["Manifest"] as! [String: Any]
        components.removeValue(forKey: "RestoreRamDisk")
        identities[0]["Manifest"] = components; plist["BuildIdentities"] = identities
        XCTAssertThrowsError(try FirmwareManifest.parse(PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)))
    }

    func testAppleDownloadURLPolicyRejectsHostTricksCredentialsAndHTTP() {
        for url in ["https://updates.cdn-apple.com/file.ipsw", "https://secure-appldnld.apple.com/file.ipsw", "https://apple.com:443/file.ipsw"] {
            XCTAssertTrue(FirmwareDownloader.isAllowedDownloadURL(URL(string: url)!))
        }
        for url in ["http://updates.cdn-apple.com/a.ipsw", "https://cdn-apple.com.evil.example/a.ipsw",
                    "https://evilapple.com/a.ipsw", "https://apple.com@evil.example/a.ipsw",
                    "https://evil@apple.com/a.ipsw", "https://apple.com:8443/a.ipsw", "file:///tmp/a.ipsw"] {
            XCTAssertFalse(FirmwareDownloader.isAllowedDownloadURL(URL(string: url)!), url)
        }
    }

    func testDownloadUsesRealDelegateProgressAndPreservesExistingFile() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let existing = directory.appendingPathComponent("ok.ipsw")
        try Data("existing".utf8).write(to: existing)
        let progress = DownloadProgressRecorder()
        let downloaded = try await stubDownloader().download(stubRelease("ok"), to: directory) { progress.record($0) }
        XCTAssertFalse(downloaded == existing)
        XCTAssertEqual(try Data(contentsOf: downloaded), Data("abc".utf8))
        XCTAssertEqual(try Data(contentsOf: existing), Data("existing".utf8))
        XCTAssertTrue(progress.values.contains { $0.bytesWritten == 3 && $0.fraction == 1 })
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).count, 2)
    }

    func testDownloadRejectsHTTPSizeAndDigestAndCleansStaging() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        for scenario in ["http", "size", "digest", "redirect"] {
            do {
                _ = try await stubDownloader().download(stubRelease(scenario), to: directory) { _ in }
                XCTFail("Expected failure: \(scenario)")
            } catch let error as FirmwareTransferError {
                let actual: String
                switch error {
                case .httpStatus(404): actual = "http"
                case .incompleteDownload: actual = "size"
                case .checksumMismatch: actual = "digest"
                case .untrustedURL: actual = "redirect"
                default: actual = "unexpected"
                }
                XCTAssertEqual(actual, scenario)
            }
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [])
        }
    }

    func testDownloadCancellationRemovesPartialFiles() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let transfer = Task { try await stubDownloader().download(stubRelease("slow"), to: directory) { _ in } }
        try await Task.sleep(nanoseconds: 30_000_000)
        transfer.cancel()
        do { _ = try await transfer.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [])
    }

    func testDownloadPauseResumeControlsOneTaskWithoutNestedSuspension() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [FirmwareStubProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let task = session.downloadTask(with: stubRelease("slow").url)
        let control = FirmwareDownloadControl()
        control.start(task)
        XCTAssertEqual(task.state, .running)
        XCTAssertTrue(control.setPaused(true))
        XCTAssertTrue(control.setPaused(true))
        // URLSession applies suspension asynchronously on some SDK versions.
        for _ in 0..<50 where task.state != .suspended { try await Task.sleep(nanoseconds: 10_000_000) }
        XCTAssertEqual(task.state, .suspended)
        XCTAssertTrue(control.setPaused(false))
        XCTAssertEqual(task.state, .running)
        XCTAssertTrue(control.setPaused(false))
        control.finish()
        XCTAssertFalse(control.setPaused(true))
    }

    func testDownloadPausedBeforeStartResumesAndValidatesFile() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let control = FirmwareDownloadControl()
        let progress = DownloadProgressRecorder()
        XCTAssertTrue(control.setPaused(true))
        let transfer = Task {
            try await stubDownloader().download(stubRelease("ok"), to: directory, control: control) { progress.record($0) }
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertTrue(progress.values.isEmpty)
        XCTAssertTrue(control.setPaused(false))
        let file = try await transfer.value
        XCTAssertEqual(try Data(contentsOf: file), Data("abc".utf8))
        XCTAssertTrue(progress.values.contains { $0.fraction == 1 })
        XCTAssertFalse(control.setPaused(true))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path).count, 1)
    }

    func testDownloadCanCancelWhilePausedAndCleanPartialFiles() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let control = FirmwareDownloadControl()
        XCTAssertTrue(control.setPaused(true))
        let transfer = Task {
            try await stubDownloader().download(stubRelease("slow"), to: directory, control: control) { _ in }
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        transfer.cancel()
        do { _ = try await transfer.value; XCTFail("Expected cancellation while paused") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertFalse(control.setPaused(false))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [])
    }

    private func stubDownloader() -> FirmwareDownloader {
        FirmwareDownloader(configurationFactory: {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [FirmwareStubProtocol.self]
            return configuration
        })
    }
    private func stubRelease(_ scenario: String) -> FirmwareRelease {
        FirmwareRelease(identifier: "iPhone14,2", version: "18.0", buildID: "22A3354",
                        url: URL(string: "https://updates.cdn-apple.com/\(scenario).ipsw")!,
                        fileSize: scenario == "size" ? 4 : 3, signed: true,
                        sha256: scenario == "digest" ? firmwareHash : "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}

private final class DownloadProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [FirmwareDownloadProgress] = []
    var values: [FirmwareDownloadProgress] { lock.lock(); defer { lock.unlock() }; return storage }
    func record(_ value: FirmwareDownloadProgress) { lock.lock(); storage.append(value); lock.unlock() }
}

/// URLSession still runs its actual download task and delegate; only its network transport is replaced.
private final class FirmwareStubProtocol: URLProtocol, @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        let scenario = url.deletingPathExtension().lastPathComponent
        if scenario == "redirect" {
            let target = URL(string: "https://evil.example/file.ipsw")!
            let response = HTTPURLResponse(url: url, statusCode: 302, httpVersion: "HTTP/1.1", headerFields: ["Location": target.absoluteString])!
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: target), redirectResponse: response)
            return
        }
        let response = HTTPURLResponse(url: url, statusCode: scenario == "http" ? 404 : 200,
                                       httpVersion: "HTTP/1.1", headerFields: ["Content-Length": "3", "Content-Type": "application/octet-stream"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let finish: @Sendable () -> Void = { [self] in
            lock.lock(); let shouldStop = stopped; lock.unlock()
            guard !shouldStop else { return }
            client?.urlProtocol(self, didLoad: Data("abc".utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
        if scenario == "slow" { DispatchQueue.global().asyncAfter(deadline: .now() + 0.25, execute: finish) }
        else { finish() }
    }
    override func stopLoading() { lock.lock(); stopped = true; lock.unlock() }
}
