import AppKit
import UniformTypeIdentifiers
import ReScopeCore

extension AppModel {
    var appVersion: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? L("développement") }
    var downloadFolderLabel: String {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0].appendingPathComponent("ReScope").path
        return downloadDirectoryPath == downloads ? L("Téléchargements/ReScope") : (downloadDirectoryPath as NSString).abbreviatingWithTildeInPath
    }
    var supportContext: SupportContext {
        SupportContext(operation: isBackupBusy ? (backupOperation == .backup ? .backup : .backupRestore) : isRestoring ? .restoration : isDownloadingFirmware ? .firmwareDownload : .idle,
            phase: isBackupBusy ? backupPhase : isRestoring ? restorePhase : L("Consultation d’iTelier"), deviceModel: device?.productType,
            systemVersion: device?.osVersion, firmwareVersion: firmware?.version ?? downloadRelease?.version,
            firmwareBuild: firmware?.build ?? downloadRelease?.buildID, restoreMode: restoreMode)
    }

    func initializeSafety() {
        do {
            let directory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("ReScope/Support", isDirectory: true)
            let journal = try SafetyJournal(directory: directory, appVersion: appVersion)
            safetyJournal = journal
            supportIncident = journal.previousInterruption ?? journal.latestReport
            interruptionNotice = journal.previousInterruption != nil
            recoveryRequired = journal.requiresRecovery
            if let interrupted = journal.previousInterruption, interrupted.context.operation == .restoration,
               let modeName = interrupted.context.restoreMode, let mode = RestoreMode(rawValue: modeName) { restoreMode = mode; activeRestoreMode = mode }
            if recoveryRequired { page = .restore }
            AppDelegate.onCleanExit = { [weak self] in try? self?.safetyJournal?.closeNormally() }
        } catch { safetyStorageError = L("Le journal de sécurité est inaccessible. La restauration reste bloquée : \(error.localizedDescription)") }
        if RestoreHost.isRunning { resumeRestoreObservation() }
    }

    @discardableResult func track(_ operation: TrackedOperation, phase: String) -> Bool {
        guard let journal = safetyJournal else { return false }
        var context = supportContext; context.operation = operation; context.phase = phase
        do { try journal.update(context); return true }
        catch { safetyStorageError = L("Impossible d’enregistrer l’état de l’opération. \(error.localizedDescription)"); return false }
    }
    func finishTracking() { do { try safetyJournal?.completeOperation() } catch { safetyStorageError = error.localizedDescription } }
    func reportFailure(_ error: Error) {
        alert = error.localizedDescription
        var code = (error as NSError).code
        let category: String
        switch error {
        case DeviceServiceError.commandFailed(_, let exitCode, _): category = "restoreOrDeviceCommand"; code = Int(exitCode)
        case DeviceServiceError.missingTool: category = "missingTool"
        case DeviceServiceError.timedOut: category = "deviceTimeout"
        case DeviceServiceError.outputTooLarge: category = "oversizedToolOutput"
        case DeviceServiceError.invalidData: category = "invalidData"
        case DeviceServiceError.unsafeRestore: category = "restoreSafetyCheck"
        case FirmwareTransferError.httpStatus(let status): category = "httpStatus"; code = status
        case FirmwareTransferError.checksumMismatch: category = "firmwareChecksum"
        case FirmwareTransferError.incompleteDownload: category = "incompleteDownload"
        case FirmwareTransferError.insufficientSpace: category = "insufficientSpace"
        case is FirmwareTransferError: category = "firmwareTransfer"
        case is URLError: category = "network"
        default: category = "application"
        }
        do { supportIncident = try safetyJournal?.recordFailure(code: code, category: category) }
        catch { safetyStorageError = error.localizedDescription }
    }
    func openSupportReport() {
        if supportIncident == nil { supportIncident = SupportReport(kind: .userFeedback, appVersion: appVersion, context: supportContext) }
        backupToRestore = nil; showSettings = false; showFirmwareBrowser = false; showRestorePreparation = false; showConfirmation = false; alert = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.showSupportReport = true }
    }
    var supportReportText: String {
        guard let report = supportIncident, let data = try? report.json(description: supportDescription) else { return L("Rapport indisponible.") }
        return String(decoding: data, as: UTF8.self)
    }
    func exportSupportReport() {
        let panel = NSSavePanel()
        panel.title = L("Exporter le rapport d’incident")
        panel.nameFieldStringValue = "iTelier-incident-\(supportIncident?.id.uuidString.prefix(8) ?? "rapport").json"
        panel.allowedContentTypes = [.json]
        panel.begin { [weak self] response in
            guard response == .OK, let self, let url = panel.url else { return }
            do { try Data(self.supportReportText.utf8).write(to: url, options: .atomic) }
            catch { self.alert = error.localizedDescription }
        }
    }
    func copySupportReport() { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(supportReportText, forType: .string) }
    func chooseDownloadDirectory() {
        guard !busy else { return }
        let panel = NSOpenPanel(); panel.title = L("Dossier de téléchargement des IPSW")
        panel.prompt = L("Utiliser ce dossier"); panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.canCreateDirectories = true; panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: downloadDirectoryPath)
        panel.begin { [weak self] response in
            guard response == .OK, let self, let url = panel.url else { return }
            self.downloadDirectoryPath = url.path
            UserDefaults.standard.set(url.path, forKey: "downloadDirectory")
        }
    }
    func revealDownloadDirectory() {
        let url = URL(fileURLWithPath: downloadDirectoryPath, isDirectory: true)
        do { try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true); NSWorkspace.shared.open(url) }
        catch { reportFailure(error) }
    }

    func recheckAfterInterruption() async {
        guard !busy, !isRefreshing, !isDemo else { return }
        guard !BackupHost.isRunning else { resumeBackupObservation(); return }
        guard !RestoreHost.isRunning else { resumeRestoreObservation(); return }
        await refresh()
        if device != nil { acknowledgeRecovery(); resetAcknowledgements() }
        else { alert = L("Aucun appareil identifié. Gardez le câble branché, vérifiez l’écran de l’appareil et réessayez. La restauration reste bloquée.") }
    }

    func acknowledgeRecovery() {
        do { try safetyJournal?.acknowledgeRecovery(); recoveryRequired = false }
        catch { safetyStorageError = error.localizedDescription }
    }

    private func resumeRestoreObservation() {
        guard !isRestoring else { return }
        isRestoring = true; recoveryRequired = true; page = .restore
        AppDelegate.restorationActive = true
        restorePhase = L("Reprise du suivi de la restauration")
        track(.restoration, phase: restorePhase)
        Task {
            var trackedID: String?
            while RestoreHost.isRunning {
                if let latest = RestoreHost.latest() {
                    trackedID = latest.snapshot.sessionID
                    restorePhase = latest.snapshot.phase; restoreProgress = latest.snapshot.progress; logs = latest.snapshot.log
                    track(.restoration, phase: restorePhase)
                }
                try? await Task.sleep(nanoseconds: 750_000_000)
            }
            isRestoring = false; AppDelegate.restorationActive = false
            if let latest = RestoreHost.latest(), latest.snapshot.sessionID == trackedID, latest.snapshot.finished {
                restorationComplete = latest.snapshot.completion == .confirmed
                restorationFailed = !restorationComplete
                restorePhase = restorationComplete ? L("Installation du système terminée") : latest.snapshot.completion == .failed ? L("La restauration n’a pas abouti") : L("Résultat de la restauration à vérifier")
                restoreProgress = restorationComplete ? 1 : nil; logs = latest.snapshot.log
                if restorationComplete { acknowledgeRecovery() }
            } else {
                restorationFailed = true
                restorePhase = L("Résultat de la restauration à vérifier")
            }
            if restorationFailed { reportFailure(DeviceServiceError.unsafeRestore(L("Une restauration s’est interrompue. Gardez l’appareil connecté et vérifiez son état avant une nouvelle tentative."))) }
            finishTracking()
        }
    }
}
