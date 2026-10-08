import XCTest
import Foundation
import Darwin
@testable import iTelierCore

final class UserFacingErrorTests: XCTestCase {
    func testRecoveryPreparationFailureHasAConcreteNextStepWithoutTheLog() {
        let output = """
        idevicerestore 1.1.0-git-fixture
        ECID: 99999888887777
        Device Product Build: PRIVATEBUILD
        Received SHSH blobs
        Please enter your passcode on the device
        Stashbag committed!
        Entering recovery mode...
        Failed to enter recovery mode
        Unable to place device into recovery mode from normal mode
        """
        for language in ["fr", "en"] {
            withLanguage(language) {
                let value = UserFacingError.presentation(for: DeviceServiceError.commandFailed("idevicerestore", 1, output), operation: .restoration)
                XCTAssertEqual(value.diagnosticCategory, "restoreRecoveryTransition")
                XCTAssertEqual(value.title, language == "fr" ? "L’installation n’a pas pu démarrer" : "Installation could not start")
                XCTAssertTrue(value.message.contains(language == "fr" ? "Gardez-le connecté" : "Keep it connected"))
                XCTAssertTrue(value.message.contains(language == "fr" ? "autorisez la connexion sur le Mac" : "allow the connection on your Mac"))
                XCTAssertTrue(value.message.contains(language == "fr" ? "Vérifiez ensuite son état" : "Then check its status"))
                assertNoPrivateOutput(value)
                for forbidden in ["SHSH", "Stashbag", "idevicerestore", "ECID", "effacer", "erased", "intactes", "preserved"] {
                    XCTAssertFalse(value.message.contains(forbidden), forbidden)
                }
            }
        }
    }

    func testRoutineSignatureAndPasscodeMessagesDoNotBecomeAnAppleRefusal() {
        let output = """
        Checking signing status...
        Received SHSH blobs
        Please enter your passcode on the device
        Stashbag created.
        Unable to send FirmwareUpdater data
        Unable to successfully restore device
        """
        let value = UserFacingError.presentation(for: DeviceServiceError.commandFailed("idevicerestore", 1, output), operation: .restoration)
        XCTAssertEqual(value.diagnosticCategory, "restoreOrDeviceCommand")
        XCTAssertEqual(value.title, L("L’installation a été interrompue"))
        assertNoPrivateOutput(value)
    }

    func testOnlyExplicitNegativeSigningMessagesUseTheAppleValidationExplanation() {
        for output in ["TSS request failed (status=94, message=This device isn't eligible for the requested build)",
                       "ERROR: Firmware is not signed", "TSS request was rejected"] {
            let value = UserFacingError.presentation(for: DeviceServiceError.commandFailed("idevicerestore", 1, output), operation: .restoration)
            XCTAssertEqual(value.diagnosticCategory, "appleSigningRejected", output)
            XCTAssertTrue(value.message.contains("Apple"))
            XCTAssertFalse(value.message.contains(output))
        }
        let positive = UserFacingError.presentation(for: DeviceServiceError.commandFailed("idevicerestore", 1, "Firmware is signed\nReceived SHSH blobs\nLater operation failed"))
        XCTAssertEqual(positive.diagnosticCategory, "restoreOrDeviceCommand")
    }

    func testGenericTSSFailureDoesNotClaimThatAppleHasStoppedSigningTheVersion() {
        for output in ["TSS request failed", "Unable to get SHSH blobs for this device", "Unable to fetch SHSH: request timed out"] {
            let value = UserFacingError.presentation(for: DeviceServiceError.commandFailed("idevicerestore", 1, output), operation: .restoration)
            XCTAssertEqual(value.diagnosticCategory, "appleSigningUnavailable")
            XCTAssertFalse(value.message.contains("version autorisée"))
            XCTAssertFalse(value.message.contains("authorised version"))
            XCTAssertTrue(value.message.contains("Internet"))
        }
    }

    func testComponentFirmwareFailureExplainsInterruptionAndOffersFinderWithoutRetrying() {
        let failures = ["Unable to fetch Yonkers ticket", "Unable to fetch Savage ticket", "Unable to fetch Rose ticket",
                        "Unable to fetch SE ticket", "restore_send_firmware_updater_data: Couldn't get Yonkers firmware data!",
                        "Couldn't get PRIVATEDEVICE firmware data", "Could not determine Savage firmware component"]
        for language in ["fr", "en"] {
            withLanguage(language) {
                for failure in failures {
                    let output = "TSS request failed\nTSS request was rejected\nReceived SHSH blobs\nPasswordProtected\n\(failure)\nUnable to send FirmwareUpdater data\nECID: 99999888887777\nPRIVATEBUILD /private/SECRETFILE"
                    let value = UserFacingError.presentation(for: DeviceServiceError.commandFailed("idevicerestore", 1, output))
                    XCTAssertEqual(value.diagnosticCategory, "restoreComponentFirmware", failure)
                    XCTAssertEqual(value.title, language == "fr" ? "L’installation a été interrompue" : "Installation was interrupted")
                    XCTAssertTrue(value.message.contains(language == "fr" ? "composant" : "component"))
                    XCTAssertTrue(value.message.contains(language == "fr" ? "vérifiez son écran" : "check its screen"))
                    XCTAssertTrue(value.message.contains("Finder"))
                    XCTAssertTrue(value.message.contains(language == "fr" ? "Mettre à jour" : "Update"))
                    assertNoPrivateOutput(value)
                    for forbidden in ["Yonkers", "TSS", "SHSH", "FirmwareUpdater", "réessay", "try again", "câble", "cable",
                                      "réinitialis", "reset", "effac", "erase", "intact", "preserved", "version autorisée", "authorised version"] {
                        XCTAssertFalse(value.message.contains(forbidden), forbidden)
                    }
                }
                let unsigned = UserFacingError.presentation(for: DeviceServiceError.commandFailed("idevicerestore", 1,
                    "Firmware is not signed\nUnable to fetch Yonkers ticket"))
                XCTAssertEqual(unsigned.diagnosticCategory, "appleSigningRejected")
                let transition = UserFacingError.presentation(for: DeviceServiceError.commandFailed("idevicerestore", 1,
                    "Unable to fetch Yonkers ticket\nFailed to enter recovery mode"))
                XCTAssertEqual(transition.diagnosticCategory, "restoreRecoveryTransition")
                let unrelated = UserFacingError.presentation(for: DeviceServiceError.commandFailed("idevicerestore", 1,
                    "Received Yonkers ticket\nTSS request failed\nCouldn't get response\nReceived SE firmware data"))
                XCTAssertEqual(unrelated.diagnosticCategory, "appleSigningUnavailable")
                let check = UserFacingError.presentation(for: DeviceServiceError.commandFailed("idevicediagnostics", 1,
                    "Unable to fetch Yonkers ticket"), operation: .deviceCheck)
                XCTAssertEqual(check.diagnosticCategory, "restoreOrDeviceCommand")
            }
        }
    }

    func testFinalPreparationFailureTakesPriorityOverEarlierPairingInstructions() {
        let value = UserFacingError.presentation(for: DeviceServiceError.commandFailed("idevicerestore", 1,
            "PairingDialogResponsePending\nPlease enter your passcode\nReceived SHSH blobs\nFailed to enter recovery mode"))
        XCTAssertEqual(value.diagnosticCategory, "restoreRecoveryTransition")
    }

    func testTrustLockedAndUnavailableDeviceOfferDistinctActions() {
        let cases = [("ERROR: UserDeniedPairing", "deviceTrustRequired"),
                     ("ERROR: PasswordProtected", "deviceLocked"),
                     ("ERROR: Device is locked", "deviceLocked"),
                     ("ERROR: No device found", "deviceUnavailable"),
                     ("ERROR: Device disconnected", "deviceUnavailable")]
        for (output, category) in cases {
            let value = UserFacingError.presentation(for: DeviceServiceError.commandFailed("ideviceinfo", 1, output), operation: .deviceCheck)
            XCTAssertEqual(value.diagnosticCategory, category)
            XCTAssertFalse(value.message.contains(output))
        }
        let positive = UserFacingError.presentation(for: DeviceServiceError.commandFailed("ideviceinfo", 1, "Trust dialog accepted\nDevice unlocked\nUnrelated failure"), operation: .deviceCheck)
        XCTAssertEqual(positive.diagnosticCategory, "restoreOrDeviceCommand")
        let restoring = UserFacingError.presentation(for: DeviceServiceError.commandFailed("idevicerestore", 1, "Device disconnected"), operation: .restoration)
        XCTAssertFalse(restoring.message.lowercased().contains("débranche"))
        XCTAssertFalse(restoring.message.lowercased().contains("unplug"))
    }

    func testTrustAndLockedMessagesRequireAStatusCheckBeforeRetryingAnInterruptedRestore() {
        for language in ["fr", "en"] {
            withLanguage(language) {
                for output in ["UserDeniedPairing", "PasswordProtected"] {
                    let value = UserFacingError.presentation(for: DeviceServiceError.commandFailed("idevicerestore", 1, output))
                    XCTAssertTrue(value.message.contains(language == "fr" ? "Vérifiez ensuite son état" : "Then check its status"))
                    XCTAssertFalse(value.message.contains(output))
                }
            }
        }
    }

    func testApplicationSafetyReasonsRemainVisibleInBothLanguages() {
        for language in ["fr", "en"] {
            withLanguage(language) {
                let preservation = L("La conservation des données exige la même version ou une version plus récente. Un retour en arrière est bloqué.")
                let value = UserFacingError.presentation(for: DeviceServiceError.unsafeRestore(preservation), operation: .restoration)
                XCTAssertEqual(value.message, preservation)
                XCTAssertEqual(value.diagnosticCategory, "restoreSafetyCheck")
                let target = L("L’appareil connecté ne correspond plus à l’appareil sélectionné.")
                XCTAssertEqual(UserFacingError.presentation(for: DeviceServiceError.invalidData(target)).message, target)
                let password = L("Le mot de passe de la sauvegarde est incorrect.")
                XCTAssertEqual(UserFacingError.presentation(for: BackupError.invalid(password), operation: .backupRestore).message, password)
                let encryption = L("Le chiffrement demandé n’est pas confirmé dans la sauvegarde.")
                XCTAssertEqual(UserFacingError.presentation(for: BackupError.invalid(encryption), operation: .backup).message, encryption)
            }
        }
    }

    func testKnownReasonWithPrivateSuffixAndUnknownFrenchReasonAreNeverEchoed() {
        let reasons = [L("Le mot de passe de la sauvegarde est incorrect.") + "\n/private/SECRETFILE · ECID: 99999888887777",
                       "Votre appareil PRIVATEDEVICE a un problème : /private/SECRETFILE",
                       "Unable to place device into recovery mode from normal mode\nECID: 99999888887777"]
        for reason in reasons {
            let errors: [Error] = [DeviceServiceError.invalidData(reason), DeviceServiceError.unsafeRestore(reason), BackupError.invalid(reason)]
            for error in errors {
                let value = UserFacingError.presentation(for: error, operation: .restoration)
                XCTAssertFalse(value.message.contains(reason))
                assertNoPrivateOutput(value)
            }
        }
    }

    func testPrivateToolNamesAndUnknownErrorDescriptionsAreNeverDisplayed() {
        let tool = "/private/SECRETFILE/PRIVATEDEVICE"
        let errors: [Error] = [DeviceServiceError.commandFailed(tool, 999, "ECID: 99999888887777\nPRIVATEBUILD"),
                               DeviceServiceError.missingTool(tool), DeviceServiceError.timedOut(tool),
                               DeviceServiceError.outputTooLarge(tool),
                               NSError(domain: "PRIVATEDEVICE", code: 999, userInfo: [NSLocalizedDescriptionKey: "ECID: 99999888887777 /private/SECRETFILE"]) ]
        for error in errors {
            let value = UserFacingError.presentation(for: error, operation: .restoration)
            assertNoPrivateOutput(value)
            XCTAssertFalse(value.message.contains("999"))
            XCTAssertFalse(value.title.isEmpty)
            XCTAssertTrue(value.message.count < 600)
        }
    }

    func testFirmwareFailureReasonsSeparateSpaceIntegritySourceAndServer() {
        let cases: [(FirmwareTransferError, String)] = [(.insufficientSpace, "insufficientSpace"),
            (.invalidDestination, "fileDestination"), (.checksumMismatch, "firmwareIntegrity"),
            (.incompleteDownload, "firmwareIntegrity"), (.untrustedURL, "firmwareSourceRejected"),
            (.httpStatus(503), "httpStatus"), (.invalidMetadata, "firmwareCatalogue"), (.metadataTooLarge, "firmwareCatalogue")]
        for (error, category) in cases {
            let value = UserFacingError.presentation(for: error, operation: .firmwareDownload)
            XCTAssertEqual(value.diagnosticCategory, category)
            XCTAssertFalse(value.message.contains("HTTP"))
            XCTAssertFalse(value.message.contains("503"))
            XCTAssertFalse(value.message.contains("checksum"))
        }
    }

    func testNetworkAndFileErrorsNeverExposeTheirUnderlyingURLOrPath() {
        let secret: [String: Any] = [NSLocalizedDescriptionKey: "PRIVATEDEVICE /private/SECRETFILE",
                                     NSFilePathErrorKey: "/private/SECRETFILE",
                                     NSURLErrorFailingURLErrorKey: URL(string: "https://private.invalid/SECRETFILE")!]
        let cases: [(String, Int, String)] = [
            (NSURLErrorDomain, URLError.notConnectedToInternet.rawValue, "network"),
            (NSURLErrorDomain, URLError.timedOut.rawValue, "network"),
            (NSURLErrorDomain, URLError.serverCertificateUntrusted.rawValue, "secureConnection"),
            (NSCocoaErrorDomain, NSFileWriteOutOfSpaceError, "insufficientSpace"),
            (NSCocoaErrorDomain, NSFileWriteNoPermissionError, "fileDestination"),
            (NSCocoaErrorDomain, NSFileReadNoPermissionError, "fileUnavailable"),
            (NSCocoaErrorDomain, NSFileReadNoSuchFileError, "fileUnavailable"),
            (NSCocoaErrorDomain, NSFileReadCorruptFileError, "fileInvalid"),
            (NSPOSIXErrorDomain, Int(ENOSPC), "insufficientSpace")]
        for (domain, code, category) in cases {
            let value = UserFacingError.presentation(for: NSError(domain: domain, code: code, userInfo: secret))
            XCTAssertEqual(value.diagnosticCategory, category)
            assertNoPrivateOutput(value)
            XCTAssertFalse(value.message.contains("private.invalid"))
        }
    }

    func testFallbackExplainsTheRelevantOperationAndDoesNotInventDataRecovery() {
        let error = NSError(domain: "fixture", code: -1, userInfo: [NSLocalizedDescriptionKey: "PRIVATEDEVICE"])
        let titles: [(TrackedOperation, LocalizedText)] = [
            (.idle, "L’action n’a pas pu être terminée"), (.deviceCheck, "La vérification n’a pas pu se terminer"),
            (.firmwareInspection, "Ce fichier ne peut pas être vérifié"), (.firmwareDownload, "Le téléchargement n’a pas pu se terminer"),
            (.restoration, "L’installation a été interrompue"), (.backup, "La sauvegarde n’a pas pu se terminer"),
            (.backupRestore, "La récupération des données a été interrompue")]
        for (operation, title) in titles {
            let value = UserFacingError.presentation(for: error, operation: operation)
            XCTAssertEqual(value.title, L(title))
            assertNoPrivateOutput(value)
            XCTAssertFalse(value.message.contains("Vos données sont"))
            XCTAssertFalse(value.message.contains("Your data is"))
        }
    }

    func testBackupVersionGuardRetainsTheReasonWithoutTransportingItsArgument() {
        for language in ["fr", "en"] {
            withLanguage(language) {
                let reason = L("Installez iOS/iPadOS \("27.2") ou une version plus récente sur l’appareil.")
                let value = UserFacingError.presentation(for: BackupError.invalid(reason), operation: .backupRestore)
                XCTAssertTrue(value.message.contains(language == "fr" ? "au moins aussi récente" : "at least as recent"))
                XCTAssertFalse(value.message.contains("27.2"))
                let injected = L("Installez iOS/iPadOS \("/private/SECRETFILE") ou une version plus récente sur l’appareil.")
                assertNoPrivateOutput(UserFacingError.presentation(for: BackupError.invalid(injected), operation: .backupRestore))
            }
        }
    }

    func testEveryPresentationBranchHasAnEnglishTranslation() {
        let errors: [(Error, TrackedOperation)] = [
            (DeviceServiceError.commandFailed("idevicerestore", 1, "Failed to enter recovery mode"), .restoration),
            (DeviceServiceError.commandFailed("idevicerestore", 1, "TSS request failed"), .restoration),
            (DeviceServiceError.commandFailed("idevicerestore", 1, "TSS request was rejected"), .restoration),
            (DeviceServiceError.commandFailed("idevicerestore", 1, "Unable to fetch Yonkers ticket"), .restoration),
            (DeviceServiceError.commandFailed("ideviceinfo", 1, "UserDeniedPairing"), .deviceCheck),
            (DeviceServiceError.commandFailed("ideviceinfo", 1, "PasswordProtected"), .deviceCheck),
            (DeviceServiceError.commandFailed("idevicerestore", 1, "No device found"), .restoration),
            (DeviceServiceError.missingTool("fixture"), .idle), (DeviceServiceError.timedOut("fixture"), .idle),
            (DeviceServiceError.outputTooLarge("fixture"), .idle),
            (DeviceServiceError.unsafeRestore("Restauration bloquée : l’ECID de l’appareil ne peut pas être vérifié."), .restoration),
            (DeviceServiceError.invalidData("L’outil n’a pas renvoyé un dictionnaire plist valide."), .deviceCheck),
            (DeviceServiceError.invalidData("Les informations Recovery/DFU sont incomplètes. Mettez à jour libirecovery."), .deviceCheck),
            (DeviceServiceError.invalidData("BuildManifest.plist est incomplet : version, modèles ou identités manquants."), .firmwareInspection),
            (FirmwareTransferError.insufficientSpace, .firmwareDownload), (FirmwareTransferError.invalidDestination, .firmwareDownload),
            (FirmwareTransferError.checksumMismatch, .firmwareDownload), (FirmwareTransferError.untrustedURL, .firmwareDownload),
            (FirmwareTransferError.httpStatus(503), .firmwareDownload), (FirmwareTransferError.invalidMetadata, .firmwareDownload),
            (URLError(.notConnectedToInternet), .firmwareDownload), (URLError(.serverCertificateUntrusted), .firmwareDownload),
            (URLError(.cancelled), .firmwareDownload), (URLError(.fileDoesNotExist), .firmwareDownload),
            (NSError(domain: NSCocoaErrorDomain, code: NSFileReadCorruptFileError), .firmwareInspection),
            (CancellationError(), .idle)] + [TrackedOperation.idle, .deviceCheck, .firmwareInspection, .firmwareDownload, .restoration, .backup, .backupRestore].map {
                (NSError(domain: "fixture", code: 1), $0)
            }
        for (error, operation) in errors {
            let french = withLanguage("fr") { UserFacingError.presentation(for: error, operation: operation) }
            let english = withLanguage("en") { UserFacingError.presentation(for: error, operation: operation) }
            XCTAssertEqual(EnglishStrings.values[french.title], english.title, french.title)
            XCTAssertEqual(EnglishStrings.values[french.message], english.message, french.message)
            XCTAssertTrue(french.title != english.title)
            XCTAssertTrue(french.message != english.message)
            XCTAssertEqual(french.diagnosticCategory, english.diagnosticCategory)
        }
    }

    func testPartiallyAvailableCatalogueWarningIsTranslatedAndContainsNoRawError() throws {
        let error = NSError(domain: "fixture", code: 1, userInfo: [NSLocalizedDescriptionKey: "PRIVATEDEVICE /private/SECRETFILE"])
        for language in ["fr", "en"] {
            try withLanguage(language) {
                let value = try FirmwareCatalog.merge(publicResult: .failure(error), appleDBResult: .success([]))
                XCTAssertEqual(value.warnings.count, 1)
                XCTAssertTrue(value.warnings[0].hasPrefix(language == "fr" ? "IPSW.me indisponible :" : "IPSW.me unavailable:"))
                XCTAssertFalse(value.warnings[0].contains("PRIVATEDEVICE"))
                XCTAssertFalse(value.warnings[0].contains("SECRETFILE"))
            }
        }
    }

    private func assertNoPrivateOutput(_ value: UserFacingError, file: StaticString = #filePath, line: UInt = #line) {
        let combined = value.title + value.message + (value.diagnosticCategory ?? "")
        for token in ["99999888887777", "PRIVATEDEVICE", "PRIVATEBUILD", "SECRETFILE", "/private/"] {
            XCTAssertFalse(combined.contains(token), token, file: file, line: line)
        }
        XCTAssertFalse(value.message.contains("\n"), file: file, line: line)
    }

    private func withLanguage<T>(_ language: String, _ body: () throws -> T) rethrows -> T {
        let previous = getenv("ITELIER_LANGUAGE").map { String(cString: $0) }
        setenv("ITELIER_LANGUAGE", language, 1)
        defer {
            if let previous { setenv("ITELIER_LANGUAGE", previous, 1) }
            else { unsetenv("ITELIER_LANGUAGE") }
        }
        return try body()
    }
}
