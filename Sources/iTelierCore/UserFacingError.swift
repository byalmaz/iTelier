import Foundation
import Darwin

/// Explication et prochaine étape, sans journal du moteur ni information privée.
public struct UserFacingError: Sendable {
    public let title: String
    public let message: String
    public let diagnosticCategory: String?

    public static func presentation(for error: Error, operation: TrackedOperation = .idle) -> Self {
        if let error = error as? DeviceServiceError {
            switch error {
            case .commandFailed(let tool, _, let output):
                return commandFailure(tool: tool, output: output, operation: operation)
            case .missingTool:
                return Self(title: L("iTelier a besoin d’être réinstallé"),
                            message: L("Un élément nécessaire manque dans l’application. Réinstallez iTelier, puis réessayez."),
                            diagnosticCategory: "missingTool")
            case .timedOut:
                return Self(title: L("La réponse se fait attendre"), message: nextDeviceStep(operation),
                            diagnosticCategory: "deviceTimeout")
            case .outputTooLarge:
                return Self(title: L("iTelier n’a pas pu lire la réponse"),
                            message: L("La réponse reçue ne peut pas être utilisée. Si le problème persiste, ouvrez le rapport pour obtenir de l’aide."),
                            diagnosticCategory: "oversizedToolOutput")
            case .invalidData(let reason):
                return guardedFailure(reason, category: "invalidData", operation: operation)
            case .unsafeRestore(let reason):
                return guardedFailure(reason, category: "restoreSafetyCheck", operation: operation)
            }
        }
        if let error = error as? BackupError, case let .invalid(reason) = error {
            return guardedFailure(reason, category: "backupValidation", operation: operation)
        }
        if let error = error as? FirmwareTransferError { return transferFailure(error) }
        if error is CancellationError {
            let message = [.restoration, .backupRestore, .backup, .deviceCheck].contains(operation)
                ? nextDeviceStep(operation) : L("Vous pouvez recommencer lorsque vous êtes prêt.")
            return Self(title: L("Opération annulée"), message: message, diagnosticCategory: "cancelled")
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain { return networkFailure(URLError.Code(rawValue: nsError.code)) }
        if let fileError = fileFailure(nsError) { return fileError }
        return fallback(operation)
    }

    private static func commandFailure(tool: String, output: String, operation: TrackedOperation) -> Self {
        // Seule une partie bornée est examinée. Elle ne quitte jamais cette fonction.
        let text = String(output.suffix(65_536)).lowercased()
        let restoration = tool == "idevicerestore" || operation == .restoration
        if restoration && containsAny(text, ["failed to enter recovery mode", "unable to enter recovery mode",
                                             "unable to place device into recovery mode", "could not enter recovery mode"]) {
            return Self(title: L("L’installation n’a pas pu démarrer"),
                        message: L("L’appareil n’a pas pu se préparer à l’installation. Gardez-le connecté, déverrouillez-le si possible et autorisez la connexion sur le Mac si un message apparaît. Vérifiez ensuite son état dans iTelier avant un nouvel essai."),
                        diagnosticCategory: "restoreRecoveryTransition")
        }
        // Les mentions ordinaires de signature ou « Received SHSH blobs » ne sont pas des refus.
        if restoration && containsAny(text, ["isn't eligible for the requested build", "is not eligible for the requested build",
                                             "firmware is not signed", "version is not signed", "is no longer being signed",
                                             "tss request was rejected"]) {
            return Self(title: L("Cette version n’a pas pu être autorisée"),
                        message: L("Apple n’a pas validé cette version pour l’appareil. Actualisez le catalogue et choisissez une version autorisée, puis vérifiez l’état de l’appareil avant de réessayer."),
                        diagnosticCategory: "appleSigningRejected")
        }
        if restoration && containsAny(text, ["tss request failed", "unable to get shsh blobs", "failed to fetch shsh", "unable to fetch shsh"]) {
            return Self(title: L("La validation auprès d’Apple n’a pas abouti"),
                        message: L("Vérifiez la connexion Internet du Mac et réessayez un peu plus tard. Gardez l’appareil connecté et vérifiez son état dans iTelier avant un nouvel essai."),
                        diagnosticCategory: "appleSigningUnavailable")
        }
        if containsAny(text, ["pairingdialogresponsepending", "userdeniedpairing", "invalidhostid", "not paired", "pairing failed"])
            || (text.contains("trust dialog") && containsAny(text, ["pending", "denied", "required", "failed"])) {
            return Self(title: L("Autorisez la connexion à ce Mac"),
                        message: restoration
                            ? L("Gardez votre appareil connecté, déverrouillez-le et touchez « Faire confiance » si ce message apparaît. Autorisez aussi la connexion sur le Mac si nécessaire. Vérifiez ensuite son état dans iTelier avant un nouvel essai.")
                            : L("Gardez votre appareil connecté, déverrouillez-le et touchez « Faire confiance » si ce message apparaît. Autorisez aussi la connexion sur le Mac si nécessaire, puis réessayez."),
                        diagnosticCategory: "deviceTrustRequired")
        }
        if containsAny(text, ["passwordprotected", "device is locked", "device locked", "please unlock", "unlock the device"]) {
            return Self(title: L("Déverrouillez votre appareil"),
                        message: restoration
                            ? L("Gardez votre appareil connecté et saisissez son code sur son écran. Autorisez la connexion si un message apparaît. Vérifiez ensuite son état dans iTelier avant un nouvel essai.")
                            : L("Gardez votre appareil connecté et saisissez son code sur son écran. Autorisez la connexion si un message apparaît, puis réessayez."),
                        diagnosticCategory: "deviceLocked")
        }
        if containsAny(text, ["no device found", "no devices found", "no device connected", "device not found",
                              "device disconnected", "unable to connect to device", "could not connect to device",
                              "couldn't connect to device", "connection to device failed"]) {
            return Self(title: L("L’appareil n’est plus accessible"), message: nextDeviceStep(operation),
                        diagnosticCategory: "deviceUnavailable")
        }
        if containsAny(text, ["no space left", "not enough disk space", "insufficient disk space"]) { return insufficientSpace() }
        return fallback(restoration ? .restoration : operation, category: "restoreOrDeviceCommand")
    }

    private static func transferFailure(_ error: FirmwareTransferError) -> Self {
        switch error {
        case .insufficientSpace: return insufficientSpace()
        case .invalidDestination:
            return folderUnavailable()
        case .incompleteDownload, .checksumMismatch:
            return Self(title: L("Le fichier téléchargé ne peut pas être utilisé"),
                        message: L("La vérification du fichier a échoué. Téléchargez une nouvelle copie depuis le catalogue avant de préparer l’installation."),
                        diagnosticCategory: "firmwareIntegrity")
        case .untrustedURL:
            return Self(title: L("Le téléchargement a été bloqué"),
                        message: L("Le fichier ne provient pas d’une connexion sécurisée à un serveur Apple. Actualisez le catalogue, puis choisissez à nouveau la version souhaitée."),
                        diagnosticCategory: "firmwareSourceRejected")
        case .httpStatus:
            return Self(title: L("Le serveur n’a pas pu fournir le fichier"),
                        message: L("Réessayez un peu plus tard. Si le problème persiste, actualisez le catalogue ou choisissez une autre version disponible."),
                        diagnosticCategory: "httpStatus")
        case .invalidMetadata, .metadataTooLarge:
            return Self(title: L("Le catalogue n’est pas disponible pour le moment"),
                        message: L("Les informations reçues ne peuvent pas être utilisées. Actualisez le catalogue ou réessayez plus tard."),
                        diagnosticCategory: "firmwareCatalogue")
        }
    }

    private static func networkFailure(_ code: URLError.Code) -> Self {
        switch code {
        case .cannotCreateFile, .cannotOpenFile, .cannotWriteToFile: return folderUnavailable()
        case .fileDoesNotExist, .fileIsDirectory, .noPermissionsToReadFile:
            return fileUnavailable()
        case .secureConnectionFailed, .serverCertificateHasBadDate, .serverCertificateUntrusted,
             .serverCertificateHasUnknownRoot, .serverCertificateNotYetValid:
            return Self(title: L("Connexion sécurisée impossible"),
                        message: L("La sécurité de la connexion n’a pas pu être vérifiée. Vérifiez la date et l’heure du Mac, puis réessayez plus tard."),
                        diagnosticCategory: "secureConnection")
        case .cancelled:
            return Self(title: L("Téléchargement annulé"),
                        message: L("Vous pouvez relancer le téléchargement depuis le catalogue lorsque vous êtes prêt."),
                        diagnosticCategory: "cancelled")
        default:
            return Self(title: L("Connexion Internet à vérifier"),
                        message: L("Le service n’a pas pu être contacté. Vérifiez votre connexion Internet, puis réessayez. Si elle fonctionne, réessayez un peu plus tard."),
                        diagnosticCategory: "network")
        }
    }

    private static func fileFailure(_ error: NSError) -> Self? {
        if error.domain == NSCocoaErrorDomain {
            switch error.code {
            case NSFileWriteOutOfSpaceError: return insufficientSpace()
            case NSFileWriteNoPermissionError, NSFileWriteVolumeReadOnlyError: return folderUnavailable()
            case NSFileNoSuchFileError, NSFileReadNoSuchFileError, NSFileReadNoPermissionError: return fileUnavailable()
            case NSFileReadCorruptFileError:
                return Self(title: L("Ce fichier ne peut pas être lu"),
                            message: L("Le fichier semble incomplet ou endommagé. Sélectionnez une autre copie pour continuer."),
                            diagnosticCategory: "fileInvalid")
            default: return nil
            }
        }
        if error.domain == NSPOSIXErrorDomain {
            switch Int32(error.code) {
            case ENOSPC: return insufficientSpace()
            case EACCES, EPERM, EROFS: return folderUnavailable()
            case ENOENT: return fileUnavailable()
            default: return nil
            }
        }
        return nil
    }

    private static func insufficientSpace() -> Self {
        Self(title: L("Il n’y a pas assez d’espace sur le Mac"),
             message: L("Libérez de l’espace ou choisissez un autre dossier sur un disque disposant de suffisamment de place, puis réessayez."),
             diagnosticCategory: "insufficientSpace")
    }

    private static func folderUnavailable() -> Self {
        Self(title: L("Le dossier choisi n’est pas accessible"),
             message: L("Choisissez un dossier dans lequel vous pouvez enregistrer des fichiers. Si le disque est externe, vérifiez qu’il est connecté."),
             diagnosticCategory: "fileDestination")
    }

    private static func fileUnavailable() -> Self {
        Self(title: L("Le fichier n’est plus accessible"),
             message: L("Sélectionnez à nouveau le fichier ou le dossier. Si le disque est externe, vérifiez qu’il est connecté."),
             diagnosticCategory: "fileUnavailable")
    }

    private static func guardedFailure(_ reason: String, category: String, operation: TrackedOperation) -> Self {
        let base = fallback(operation, category: category)
        if reason.range(of: "^Installez iOS/iPadOS [0-9]+(\\.[0-9]+){0,2} ou une version plus récente sur l’appareil\\.$", options: .regularExpression) != nil
            || reason.range(of: "^Install iOS/iPadOS [0-9]+(\\.[0-9]+){0,2} or later on the device\\.$", options: .regularExpression) != nil {
            return Self(title: base.title,
                        message: L("Installez sur l’appareil une version du système au moins aussi récente que celle de la sauvegarde avant de restaurer ses données."),
                        diagnosticCategory: category)
        }
        // Seules les phrases fixes déjà présentes dans le catalogue de l’app peuvent être conservées.
        // Une interpolation, un journal ou une erreur inconnue ne peut pas exposer de donnée privée.
        guard let entry = EnglishStrings.values.first(where: {
            !$0.key.contains("{") && !$0.key.contains("\n") && $0.key.count <= 600
                && ($0.key == reason || $0.value == reason)
        }) else { return base }
        switch entry.key {
        case "Restauration bloquée : l’ECID de l’appareil ne peut pas être vérifié.",
             "L’appareil confirmé doit être connecté et identifiable par un ECID unique. Rebranchez-le et recommencez.":
            return Self(title: L("L’appareil doit être vérifié"),
                        message: L("L’identité de l’appareil n’a pas pu être confirmée. Gardez-le connecté et vérifiez son état dans iTelier avant un nouvel essai."),
                        diagnosticCategory: category)
        case "L’outil n’a pas renvoyé un dictionnaire plist valide.",
             "Les données transmises à l’outil sont trop volumineuses.",
             "Le journal de restauration est trop volumineux.",
             "Le journal de sécurité est trop volumineux.":
            return Self(title: L("iTelier n’a pas pu lire la réponse"),
                        message: L("Les informations reçues ne peuvent pas être utilisées. Vérifiez la connexion de l’appareil, puis réessayez. Si le problème persiste, ouvrez le rapport pour obtenir de l’aide."),
                        diagnosticCategory: category)
        case "Ce moteur est trop ancien pour imposer la conservation des données. Mettez idevicerestore à jour.",
             "Les informations Recovery/DFU sont incomplètes. Mettez à jour libirecovery.":
            return Self(title: L("iTelier doit être mis à jour"),
                        message: L("Cette version de l’application ne permet pas de terminer les vérifications nécessaires. Installez une version plus récente d’iTelier avant de réessayer."),
                        diagnosticCategory: category)
        case "BuildManifest.plist est incomplet : version, modèles ou identités manquants.",
             "Impossible de lire BuildManifest.plist. Le fichier doit être une archive IPSW valide.",
             "Ce firmware ne contient aucune identité complète de restauration ou de mise à jour.":
            return Self(title: L("Ce fichier ne peut pas être utilisé"),
                        message: L("Le fichier ne contient pas les informations nécessaires à l’installation. Choisissez une autre copie depuis le catalogue."),
                        diagnosticCategory: category)
        default:
            return Self(title: base.title, message: L(LocalizedText(stringLiteral: entry.key)), diagnosticCategory: category)
        }
    }

    private static func nextDeviceStep(_ operation: TrackedOperation) -> String {
        if operation == .restoration || operation == .backupRestore {
            return L("Gardez l’appareil connecté et vérifiez son écran. Attendez la fin d’un éventuel redémarrage, puis vérifiez son état dans iTelier avant un nouvel essai.")
        }
        return L("Gardez votre appareil connecté, déverrouillez-le si possible et autorisez la connexion si un message apparaît. Vérifiez ensuite qu’il est accessible dans iTelier avant de réessayer.")
    }

    private static func fallback(_ operation: TrackedOperation, category: String = "application") -> Self {
        let title: String, message: String
        switch operation {
        case .restoration:
            title = L("L’installation a été interrompue"); message = nextDeviceStep(operation)
        case .backupRestore:
            title = L("La récupération des données a été interrompue"); message = nextDeviceStep(operation)
        case .backup:
            title = L("La sauvegarde n’a pas pu se terminer")
            message = L("Vérifiez que votre appareil est connecté et déverrouillé, et qu’il reste assez d’espace sur le Mac, puis réessayez. Si le problème persiste, ouvrez le rapport pour obtenir de l’aide.")
        case .deviceCheck:
            title = L("La vérification n’a pas pu se terminer"); message = nextDeviceStep(operation)
        case .firmwareInspection:
            title = L("Ce fichier ne peut pas être vérifié")
            message = L("Sélectionnez à nouveau le fichier. Si le problème persiste, téléchargez une nouvelle copie depuis le catalogue.")
        case .firmwareDownload:
            title = L("Le téléchargement n’a pas pu se terminer")
            message = L("Vérifiez la connexion Internet et l’espace libre du Mac, puis réessayez.")
        case .idle:
            title = L("L’action n’a pas pu être terminée")
            message = L("Réessayez. Si le problème persiste, ouvrez le rapport pour obtenir de l’aide.")
        }
        return Self(title: title, message: message, diagnosticCategory: category)
    }

    private static func containsAny(_ text: String, _ phrases: [String]) -> Bool {
        phrases.contains(where: text.contains)
    }
}
