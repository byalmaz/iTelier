import AppKit
import ReScopeCore

extension AppModel {
    var canStartBackup: Bool {
        !busy && !isRefreshing && !isDemo && !recoveryRequired && safetyStorageError == nil
            && device?.family.supportsLocalBackup == true && device?.mode == .normal && device?.ecid != nil && installed("idevicebackup2")
    }
    var backupFolderLabel: String { (backupDirectoryPath as NSString).abbreviatingWithTildeInPath }

    func readBackupEncryption() async {
        guard !busy, !isDemo, let device, device.family.supportsLocalBackup, device.mode == .normal else { return }
        isReadingBackupEncryption = true; backupEncryptionEnabled = nil
        defer { isReadingBackupEncryption = false }
        do {
            let enabled = try await BackupHost.encryptionEnabled(deviceID: device.id)
            guard !Task.isCancelled, self.device?.id == device.id else { return }
            backupEncryptionEnabled = enabled
        } catch { /* The worker rechecks before changing encryption. */ }
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
        guard canStartBackup, let device else { return }
        launchBackup(device: device, backup: nil, encrypted: encrypted, password: password)
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
