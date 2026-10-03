import AppKit
import iTelierCore

struct RestoreSession: Identifiable {
    let directory: URL
    var snapshot: RestoreHostSnapshot
    var isActive: Bool
    var id: String { snapshot.sessionID }
    var needsReview: Bool { !isActive && snapshot.completion != .confirmed && snapshot.reviewAcknowledged != true }
    var phase: String {
        !isActive && !snapshot.finished ? L("Résultat de la restauration à vérifier") : AppLocalization.label(snapshot.phase)
    }
}

extension AppModel {
    /// Les tâches USB ordinaires restent protégées par `busy`. La préparation locale
    /// d’une autre cible est permise pendant les écritures indépendantes.
    var preparationBusy: Bool { isReadingDeviceInformation || isReadingBackupEncryption || isBackupBusy || isInspecting || isChecking || isDownloadingFirmware || isChoosingDownloadFolder || isManagingReference }
    var activeRestoreSessions: [RestoreSession] { restoreSessions.filter(\.isActive) }
    var selectedDeviceRestoring: Bool {
        guard let device else { return false }
        return activeRestoreSessions.contains { $0.snapshot.target?.matches(device) == true }
            || device.ecid.map { RestoreHost.isRestoring(ecid: $0) } == true
    }
    var selectedDeviceNeedsReview: Bool {
        guard let device else { return false }
        return restoreSessions.contains { $0.needsReview && $0.snapshot.target?.matches(device) == true }
    }
    var hasUnidentifiedRestore: Bool { activeRestoreSessions.contains { $0.snapshot.target == nil } }

    func trackRestore(_ session: RestoreSession) -> Bool {
        guard let journal = safetyJournal else { return false }
        let target = session.snapshot.target
        let context = SupportContext(operation: .restoration, phase: session.phase,
            deviceModel: target?.productType, systemVersion: target?.systemVersion,
            firmwareVersion: target?.firmwareVersion, firmwareBuild: target?.firmwareBuild, restoreMode: target?.mode)
        do { try journal.update(context); return true }
        catch { safetyStorageError = error.localizedDescription; return false }
    }

    func updateRestoreSummary() {
        let active = activeRestoreSessions
        isRestoring = !active.isEmpty
        AppDelegate.restorationActive = isRestoring
        NSApp.windows.forEach { $0.standardWindowButton(.closeButton)?.isEnabled = !isRestoring && !isBackupBusy }
        restorePhase = active.first?.phase ?? restoreSessions.first?.phase ?? L("Prêt à préparer la restauration")
        // Les pourcentages décrivent des phases distinctes : une moyenne serait trompeuse.
        restoreProgress = active.count == 1 ? active.first?.snapshot.progress : nil
        activeRestoreMode = active.count == 1 ? active.first?.snapshot.target?.mode : nil
        restorationComplete = !isRestoring && restoreSessions.first?.snapshot.completion == .confirmed
        restorationFailed = !isRestoring && restoreSessions.contains(where: \.needsReview)
        if let selected = restoreSessions.first(where: { session in device.map { session.snapshot.target?.matches($0) == true } == true }) {
            logs = selected.snapshot.log
        }
    }

    func startRestore(device: DeviceSnapshot, firmware: FirmwareInfo, mode: RestoreMode) async {
        let directory: URL
        do { directory = try RestoreHost.prepare(target: RestoreTarget(device: device, firmware: firmware, mode: mode)) }
        catch { reportFailure(error); return }
        guard let snapshot = RestoreHost.read(directory) else { safetyStorageError = L("Le suivi de cette restauration est inaccessible."); return }
        var session = RestoreSession(directory: directory, snapshot: snapshot, isActive: true)
        guard trackRestore(session) else { try? RestoreHost.recordPreparationFailure(directory); return }
        restoreSessions.insert(session, at: 0)
        restoreExecutions.insert(session.id)
        defer { restoreExecutions.remove(session.id) }
        showConfirmation = false
        resetAcknowledgements(clearOutcome: false)
        updateRestoreSummary()
        let approval = RestoreApproval(deviceID: device.id, firmwareSHA256: firmware.sha256,
            acknowledgedDataLoss: mode == .erase, mode: mode, acknowledgedPreservationRisk: mode == .preserveData)
        addActivity(L("Restauration lancée"), "\(device.name) · \(mode.title) · \(firmware.version) (\(firmware.build))", symbol: "arrow.triangle.2.circlepath")
        do {
            try await service.restore(device: device, firmware: firmware, approval: approval, sessionDirectory: directory) { [weak self] event in
                Task { @MainActor [weak self] in self?.receiveRestoreEvent(event, sessionID: snapshot.sessionID) }
            }
            if let final = RestoreHost.read(directory) { session.snapshot = final }
            session.isActive = false
            if report?.device.ecid == device.ecid { report = nil }
            addActivity(L("Installation du système terminée"), "\(device.name) · \(firmware.version) (\(firmware.build))", symbol: "checkmark.circle")
        } catch {
            if RestoreHost.isSessionRunning(directory) {
                // L’observation peut échouer ; ne jamais transformer une écriture active
                // en échec ni arrêter son moteur indépendant.
                resumeRestoreObservation()
                return
            }
            do { try RestoreHost.recordPreparationFailure(directory) } catch { safetyStorageError = error.localizedDescription }
            if let final = RestoreHost.read(directory) { session.snapshot = final }
            session.snapshot.log.append(String(error.localizedDescription.prefix(1000)))
            session.isActive = false
            _ = trackRestore(session)
            reportFailure(error)
            addActivity(L("Échec de restauration"), "\(device.name) · \(error.localizedDescription)", symbol: "exclamationmark.triangle")
        }
        if let index = restoreSessions.firstIndex(where: { $0.id == session.id }) { restoreSessions[index] = session }
        updateRestoreSummary()
        completeRestoreTrackingIfPossible()
    }

    private func receiveRestoreEvent(_ event: RestoreEvent, sessionID: String) {
        guard let index = restoreSessions.firstIndex(where: { $0.id == sessionID }), restoreSessions[index].isActive else { return }
        switch event {
        case .log(let line):
            restoreSessions[index].snapshot.log.append(String(line.prefix(1000)))
            if restoreSessions[index].snapshot.log.count > 150 { restoreSessions[index].snapshot.log.removeFirst() }
        case .phase(let phase):
            restoreSessions[index].snapshot.phase = phase; restoreSessions[index].snapshot.progress = nil
            _ = trackRestore(restoreSessions[index])
        case .progress(let progress): restoreSessions[index].snapshot.progress = progress
        case .finished: break
        }
        updateRestoreSummary()
    }

    func completeRestoreTrackingIfPossible() {
        if let active = activeRestoreSessions.first { _ = trackRestore(active); return }
        if !restoreSessions.contains(where: \.needsReview), !recoveryRequired { acknowledgeRecovery() }
        finishTracking()
    }

    /// Reprendre tous les suivis sans relancer une seule requête d’écriture.
    func resumeRestoreObservation() {
        guard restoreObservation == nil else { return }
        let entries = RestoreHost.sessions()
        for entry in entries where !restoreSessions.contains(where: { $0.id == entry.snapshot.sessionID }) {
            let active = RestoreHost.isSessionRunning(entry.directory)
                || (entry.snapshot.target == nil && !entry.snapshot.finished && RestoreHost.isRunning)
            // Une ancienne session sans identité, déjà vérifiée dans l’ancienne
            // interface, ne doit pas redevenir bloquante après une opération récente.
            let resolvedLegacy = entry.snapshot.target == nil && entry.snapshot.finished && !active
                && (!recoveryRequired || entries.contains { $0.snapshot.target != nil && $0.snapshot.updatedAt > entry.snapshot.updatedAt })
            if resolvedLegacy { continue }
            let unresolved = entry.snapshot.completion != .confirmed && entry.snapshot.reviewAcknowledged != true
            if active || unresolved || restoreSessions.count < 20 {
                restoreSessions.append(RestoreSession(directory: entry.directory, snapshot: entry.snapshot, isActive: active))
            }
        }
        if activeRestoreSessions.contains(where: { $0.snapshot.target != nil }), supportIncident?.context.operation != .backupRestore {
            // La reprise connue est protégée par appareil, pas par une interdiction globale.
            recoveryRequired = false; page = .restore
        }
        updateRestoreSummary()
        if restoreSessions.contains(where: { $0.needsReview && $0.snapshot.target == nil }) { recoveryRequired = true }
        if activeRestoreSessions.isEmpty {
            if restoreSessions.contains(where: \.needsReview), restoreSessions.allSatisfy({ $0.snapshot.target != nil }), supportIncident?.context.operation != .backupRestore { recoveryRequired = false }
            completeRestoreTrackingIfPossible()
            return
        }
        restoreObservation = Task { [weak self] in
            defer { self?.restoreObservation = nil }
            while let self, !Task.isCancelled, !self.activeRestoreSessions.isEmpty {
                for index in self.restoreSessions.indices where self.restoreSessions[index].isActive {
                    let directory = self.restoreSessions[index].directory
                    if let state = RestoreHost.read(directory) { self.restoreSessions[index].snapshot = state }
                    let state = self.restoreSessions[index].snapshot
                    let running = RestoreHost.isSessionRunning(directory)
                        || (state.target == nil && !state.finished && RestoreHost.isRunning)
                    if state.finished || (!running && !self.restoreExecutions.contains(state.sessionID) && Date().timeIntervalSince(state.updatedAt) > 15) { self.restoreSessions[index].isActive = false }
                }
                self.updateRestoreSummary()
                try? await Task.sleep(nanoseconds: 750_000_000)
            }
            self?.completeRestoreTrackingIfPossible()
        }
    }

    func recheckRestore(_ sessionID: String) async {
        guard let session = restoreSessions.first(where: { $0.id == sessionID }), session.needsReview,
              canRefreshDevices else { return }
        await refresh()
        guard let target = session.snapshot.target, let current = devices.first(where: target.matches),
              !RestoreHost.isRestoring(ecid: target.ecid) else {
            alert = L("Gardez cet appareil connecté, puis réessayez de vérifier son état."); return
        }
        do {
            try RestoreHost.acknowledgeReview(session.directory)
            if let index = restoreSessions.firstIndex(where: { $0.id == sessionID }) { restoreSessions[index].snapshot.reviewAcknowledged = true }
            selectDevice(current.id)
            updateRestoreSummary()
            completeRestoreTrackingIfPossible()
        } catch { reportFailure(error) }
    }
}
