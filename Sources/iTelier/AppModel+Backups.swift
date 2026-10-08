import AppKit
import iTelierCore

extension AppModel {
    var canStartBackup: Bool {
        canRequestBackup && !isRefreshing
    }
    var canRequestBackup: Bool {
        !busy && !isDemo && !recoveryRequired && safetyStorageError == nil
            && device?.family.supportsLocalBackup == true && device?.mode == .normal && device?.ecid != nil && installed("idevicebackup2")
    }
    var backupFolderLabel: String { (backupDirectoryPath as NSString).abbreviatingWithTildeInPath }

    func invalidateBackupEncryptionIfNeeded() {
        guard let target = backupEncryptionTarget else { return }
        guard let current = device, current.id == target.id, current.ecid == target.ecid,
              current.productType == target.productType, current.mode == .normal else {
            backupEncryptionEnabled = nil; backupEncryptionTarget = nil
            return
        }
    }

    func readBackupEncryption() async {
        do {
            // Une nouvelle sélection attend la fin de la lecture précédente, sans la chevaucher.
            while isReadingBackupEncryption { try await Task.sleep(nanoseconds: 100_000_000) }
            try Task.checkCancellation()
            guard !busy, !isDemo, let requested = device, requested.family.supportsLocalBackup, requested.mode == .normal else { return }
            isReadingBackupEncryption = true
            defer { isReadingBackupEncryption = false }
            invalidateBackupEncryptionIfNeeded()
            backupEncryptionTarget = requested
            // Garder le résultat connu pendant la relecture évite de déplier le formulaire.
            while isRefreshing { try await Task.sleep(nanoseconds: 100_000_000) }
            try Task.checkCancellation()
            guard let current = device, current.id == requested.id, current.ecid == requested.ecid,
                  current.productType == requested.productType, current.mode == .normal else { return }
            let enabled = try await BackupHost.encryptionEnabled(deviceID: current.id)
            guard !Task.isCancelled, backupEncryptionTarget != nil, self.device?.id == current.id,
                  self.device?.ecid == current.ecid, self.device?.productType == current.productType,
                  self.device?.mode == .normal else { return }
            backupEncryptionEnabled = enabled
        } catch is CancellationError {
            return
        } catch {
            // Une lecture échouée ne confirme plus le statut. Le helper le revérifie avant toute écriture.
            backupEncryptionEnabled = nil
        }
    }

    func reloadBackups() async {
        guard !isLoadingBackups else { return }
        isLoadingBackups = true
        defer { isLoadingBackups = false }
        while !Task.isCancelled {
            let path = backupDirectoryPath
            let imports = UserDefaults.standard.stringArray(forKey: "backupImports") ?? []
            do {
                let list = try await Task.detached(priority: .utility) {
                    var all = try BackupLibrary.scan(URL(fileURLWithPath: path))
                    for entry in imports {
                        if let imported = try? BackupLibrary.scan(URL(fileURLWithPath: entry)) { all += imported }
                    }
                    var ids = Set<String>()
                    return all.filter { ids.insert($0.id).inserted }.sorted { ($0.date ?? .distantPast) > ($1.date ?? .distantPast) }
                }.value
                guard !Task.isCancelled else { return }
                // Un changement de dossier ou un ajout pendant la lecture relance le scan,
                // sans publier le résultat d’une bibliothèque qui n’est plus sélectionnée.
                guard path == backupDirectoryPath,
                      imports == (UserDefaults.standard.stringArray(forKey: "backupImports") ?? []) else { continue }
                backups = list; backupLibraryError = nil
            } catch {
                guard !Task.isCancelled else { return }
                guard path == backupDirectoryPath,
                      imports == (UserDefaults.standard.stringArray(forKey: "backupImports") ?? []) else { continue }
                backups = []
                backupLibraryError = L("Le dossier des sauvegardes est inaccessible. Vérifiez son emplacement et ses autorisations.")
            }
            return
        }
    }

    func chooseBackupFolder(importing: Bool) {
        guard !busy else { return }
        let panel = NSOpenPanel()
        panel.title = importing ? L("Ajouter des sauvegardes locales") : L("Emplacement des nouvelles sauvegardes")
        panel.prompt = importing ? L("Ajouter") : L("Choisir")
        panel.canChooseFiles = false; panel.canChooseDirectories = true; panel.allowsMultipleSelection = false
        panel.canCreateDirectories = !importing
        panel.directoryURL = importing ? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/MobileSync/Backup") : URL(fileURLWithPath: backupDirectoryPath)
        panel.begin { [weak self] response in
            guard response == .OK, let self, let url = panel.url, !self.busy else { return }
            Task {
                if importing {
                    do {
                        let items = try await Task.detached { try BackupLibrary.scan(url) }.value
                        guard !items.isEmpty else { self.alert = L("Aucune sauvegarde Apple lisible dans ce dossier. Sélectionnez le dossier contenant Info.plist, Manifest.plist et Status.plist, ou son dossier parent."); return }
                        var imports = UserDefaults.standard.stringArray(forKey: "backupImports") ?? []
                        if !imports.contains(url.path) { imports.append(url.path) }
                        UserDefaults.standard.set(imports, forKey: "backupImports")
                    } catch { self.reportFailure(error); return }
                } else {
                    self.backupDirectoryPath = url.path
                    UserDefaults.standard.set(url.path, forKey: "backupDirectory")
                }
                await self.reloadBackups()
            }
        }
    }

    func revealBackupFolder(_ backup: LocalBackup? = nil) {
        if let backup { NSWorkspace.shared.activateFileViewerSelecting([backup.directory]); return }
        do {
            let url = URL(fileURLWithPath: backupDirectoryPath)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            NSWorkspace.shared.open(url)
        } catch { reportFailure(error) }
    }

    func startBackup(encrypted: Bool, password: String) {
        guard canRequestBackup, let requested = device else { return }
        // Réserver immédiatement le clic : aucune autre lecture USB ne démarre pendant l’attente.
        isPreparingBackup = true
        Task {
            defer { isPreparingBackup = false }
            do {
                while isRefreshing { try await Task.sleep(nanoseconds: 100_000_000) }
                try Task.checkCancellation()
                guard let current = device, current.id == requested.id, current.ecid == requested.ecid,
                      current.productType == requested.productType, current.mode == .normal else {
                    throw BackupError.invalid(L("L’appareil connecté ne correspond plus à l’appareil sélectionné."))
                }
                isPreparingBackup = false
                guard canStartBackup else { return }
                launchBackup(device: current, backup: nil, encrypted: encrypted, password: password)
            } catch is CancellationError {
                return
            } catch { reportFailure(error) }
        }
    }
    func presentBackupRestore(_ backup: LocalBackup) {
        guard canStartBackup, backup.restorationIssue(for: device) == nil else { return }
        backupRestoreTarget = device; backupToRestore = backup
    }
    func restoreBackup(_ backup: LocalBackup, password: String) {
        guard canStartBackup, let target = backupRestoreTarget, let current = device,
              target.id == current.id, target.ecid == current.ecid else {
            backupToRestore = nil; alert = L("L’appareil a changé. Sélectionnez à nouveau la sauvegarde et confirmez la cible."); return
        }
        backupToRestore = nil
        launchBackup(device: target, backup: backup, encrypted: false, password: password)
    }
    private func launchBackup(device: DeviceSnapshot, backup: LocalBackup?, encrypted: Bool, password: String) {
        backupOperation = backup == nil ? .backup : .restore
        guard track(backup == nil ? .backup : .backupRestore, phase: L("Préparation de l’opération de sauvegarde")) else { return }
        do {
            let session = try BackupHost.launch(device: device, library: URL(fileURLWithPath: backupDirectoryPath), backup: backup, enableEncryption: encrypted, password: password)
            if backup != nil { recoveryRequired = true }
            observeBackup(session)
        } catch { reportFailure(error); finishTracking() }
    }
    func cancelBackup() {
        guard backupOperation == .backup, let backupSession else { return }
        do { try BackupHost.cancel(backupSession); backupPhase = L("Annulation demandée…") }
        catch { reportFailure(error) }
    }
    func resumeBackupObservation() {
        guard !isBackupBusy, let latest = BackupHost.latest() else { return }
        if BackupHost.isRunning || !latest.state.finished {
            backupOperation = latest.state.operation
            page = .backups
            observeBackup(latest.directory)
        }
    }
    private func observeBackup(_ session: URL) {
        backupSession = session; isBackupBusy = true; AppDelegate.backupActive = true
        backupProgress = nil; backupPhase = L("Vérification de l’appareil"); page = .backups
        let started = Date()
        backupObservation = Task {
            defer { isBackupBusy = false; AppDelegate.backupActive = false; backupSession = nil }
            while !Task.isCancelled {
                if let state = BackupHost.read(session) {
                    backupOperation = state.operation; backupPhase = state.phase; backupProgress = state.progress
                    if state.finished {
                        if state.exitCode == 0 {
                            addActivity(state.operation == .backup ? L("Sauvegarde terminée") : L("Sauvegarde restaurée"), L("L’opération s’est terminée avec succès."), symbol: "externaldrive.badge.checkmark")
                            if state.operation == .restore { acknowledgeRecovery() }
                        } else if state.exitCode != 130 {
                            if state.operation == .restore { recoveryRequired = true }
                            reportFailure(BackupError.invalid(state.phase))
                        }
                        finishTracking(); await reloadBackups(); return
                    }
                }
                if Date().timeIntervalSince(started) > 15, !BackupHost.isRunning {
                    BackupHost.markInterrupted(session)
                    backupPhase = L("Opération interrompue · vérifiez l’appareil avant de réessayer")
                    if backupOperation == .restore { recoveryRequired = true }
                    reportFailure(BackupError.invalid(backupPhase)); finishTracking(); await reloadBackups(); return
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }
}
