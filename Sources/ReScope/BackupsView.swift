import SwiftUI
import ReScopeCore

struct BackupsView: View {
    @EnvironmentObject private var model: AppModel
    @AppStorage("encryptBackups") private var encrypt = false
    @ViewState private var password = ""
    @ViewState private var repeatedPassword = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if model.device?.isVisionPro == true {
                Label(L("La sauvegarde locale de Vision Pro n’est pas prise en charge. Utilisez les options iCloud du casque."), systemImage: "info.circle").foregroundStyle(Palette.secondary)
            }
            HStack(alignment: .top, spacing: 18) {
                createCard
                Surface {
                    VStack(alignment: .leading, spacing: 17) {
                        GlassIcon(systemName: "folder.fill", size: 57, color: Palette.violet)
                        Text(L("Sur votre Mac")).font(.system(size: 21, weight: .medium))
                        Text(L("Chaque sauvegarde est conservée séparément. Vos anciennes copies restent disponibles."))
                            .foregroundStyle(Palette.secondary).lineSpacing(4)
                        Text(model.backupFolderLabel).font(.system(size: 11)).foregroundStyle(Palette.secondary)
                            .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Button(L("Changer…")) { model.chooseBackupFolder(importing: false) }.disabled(model.busy)
                            Button(L("Ouvrir le dossier")) { model.revealBackupFolder() }
                        }.buttonStyle(QuietButtonStyle())
                        Text(L("Une sauvegarde locale contient les données prises en charge par iOS. Les contenus déjà synchronisés avec iCloud et certaines apps peuvent nécessiter une connexion après restauration."))
                            .font(.system(size: 11)).foregroundStyle(Palette.secondary).lineSpacing(3)
                    }
                }.frame(width: 315)
            }
            if !model.backupPhase.isEmpty {
                Surface(padding: 18) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            if model.isBackupBusy { ProgressView().controlSize(.small) }
                            Text(model.backupPhase).fontWeight(.medium).fixedSize(horizontal: false, vertical: true)
                            Spacer()
                            if model.isBackupBusy && model.backupOperation == .backup {
                                Button(L("Annuler")) { model.cancelBackup() }.buttonStyle(QuietButtonStyle())
                            }
                        }
                        if model.isBackupBusy {
                            if let progress = model.backupProgress {
                                ProgressView(value: progress).tint(Palette.mint)
                                Text(L("Progression transmise par l’appareil · \(Int(progress * 100)) %")).font(.system(size: 11)).foregroundStyle(Palette.secondary)
                            } else { Text(L("Confirmez le code demandé sur l’appareil et gardez le câble branché.")).foregroundStyle(Palette.secondary) }
                        }
                    }
                }
            }
            HStack {
                Text(L("Mes sauvegardes")).font(.system(size: 21, weight: .medium))
                Spacer()
                if model.isLoadingBackups { ProgressView().controlSize(.small) }
                Button(L("Ajouter un dossier…")) { model.chooseBackupFolder(importing: true) }.disabled(model.busy)
                Button { Task { await model.reloadBackups() } } label: { Image(systemName: "arrow.clockwise") }
                    .help(L("Actualiser les sauvegardes")).accessibilityLabel(L("Actualiser les sauvegardes"))
                    .disabled(model.isLoadingBackups || model.isBackupBusy)
            }.buttonStyle(QuietButtonStyle())
            if let error = model.backupLibraryError { Text(error).foregroundStyle(Palette.amber) }
            if model.backups.isEmpty {
                Surface(padding: 26) {
                    HStack(spacing: 20) {
                        GlassIcon(systemName: "externaldrive.badge.timemachine", size: 54, color: Palette.mint)
                        VStack(alignment: .leading, spacing: 8) {
                            Text(L("Votre première sauvegarde commence ici")).font(.system(size: 16, weight: .medium))
                            Text(L("Connectez votre iPhone ou iPad, puis cliquez sur Sauvegarder. Vous pouvez aussi ajouter le dossier d’une sauvegarde Finder existante."))
                                .foregroundStyle(Palette.secondary).lineSpacing(4)
                        }
                    }
                }
            } else {
                ForEach(model.backups) { backup in backupRow(backup) }
            }
        }
        .task { await model.reloadBackups() }
        .task(id: "\(model.selectedDeviceID ?? "none")-\(model.isBackupBusy)-\(model.isDemo)") { await model.readBackupEncryption() }
        .onDisappear { password = ""; repeatedPassword = "" }
        .onChange(of: model.selectedDeviceID) { _ in password = ""; repeatedPassword = "" }
    }

    private var newPasswordIssue: String? { password.isEmpty ? nil : BackupHost.passwordIssue(password) }

    private var createCard: some View {
        Surface {
            VStack(alignment: .leading, spacing: 17) {
                HStack(spacing: 17) {
                    GlassIcon(systemName: "externaldrive.badge.plus", size: 61, color: Palette.mint)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L("Garder une copie")).font(.system(size: 23, weight: .medium))
                        Text(model.device?.name ?? L("Connectez votre iPhone ou iPad")).foregroundStyle(Palette.secondary)
                    }
                }
                Text(L("Sauvegardez les données et les réglages de votre appareil, avant une restauration ou simplement par précaution."))
                    .foregroundStyle(Palette.secondary).lineSpacing(4)
                Divider().overlay(Palette.line)
                Toggle(L("Chiffrer la sauvegarde"), isOn: $encrypt).toggleStyle(.switch).disabled(model.busy)
                Text(encrypt ? L("Le chiffrement protège aussi les données sensibles prises en charge, comme les mots de passe et Santé. S’il est déjà actif, le mot de passe existant est conservé.") : L("Si le chiffrement est déjà actif sur l’appareil, il reste activé."))
                    .font(.system(size: 11)).foregroundStyle(Palette.secondary).lineSpacing(3)
                if !encrypt && model.backupEncryptionEnabled != true {
                    Text(L("Sans chiffrement, d’autres programmes de votre session macOS peuvent lire cette sauvegarde sans autorisation."))
                        .font(.system(size: 11)).foregroundStyle(Palette.amber).lineSpacing(3)
                }
                if encrypt && model.backupEncryptionEnabled != true {
                    SecureField(L("Mot de passe (pour activer le chiffrement)"), text: $password)
                    if !password.isEmpty { SecureField(L("Confirmer le mot de passe"), text: $repeatedPassword) }
                    if let issue = newPasswordIssue { Text(issue).font(.system(size: 11)).foregroundStyle(Palette.amber) }
                    Text(L("L’activation s’applique aux prochaines sauvegardes de cet appareil. Conservez ce mot de passe : iTelier ne l’enregistre pas et ne pourra pas le retrouver."))
                        .font(.system(size: 11)).foregroundStyle(Palette.amber).lineSpacing(3)
                }
                if model.isReadingBackupEncryption {
                    Text(L("Lecture du chiffrement de l’appareil…")).font(.system(size: 11)).foregroundStyle(Palette.secondary)
                } else if model.backupEncryptionEnabled == true {
                    Label(L("Chiffrement déjà activé sur cet appareil"), systemImage: "lock.fill")
                        .font(.system(size: 11)).foregroundStyle(Palette.mint)
                }
                Button {
                    model.startBackup(encrypted: encrypt, password: password)
                    password = ""; repeatedPassword = ""
                } label: { Label(L("Sauvegarder maintenant"), systemImage: "externaldrive.badge.plus").frame(maxWidth: .infinity) }
                    .buttonStyle(PrimaryButtonStyle())
                    .disabled(!model.canStartBackup || (encrypt && model.backupEncryptionEnabled != true && (password.isEmpty || password != repeatedPassword || newPasswordIssue != nil)))
                if model.device?.mode != .normal { Text(L("L’appareil doit être connecté, déverrouillé et avoir accepté « Faire confiance ».")).font(.system(size: 11)).foregroundStyle(Palette.secondary) }
                if model.recoveryRequired { Text(L("Vérifiez l’appareil dans l’avis d’interruption avant de démarrer une autre opération.")).font(.system(size: 11)).foregroundStyle(Palette.amber) }
            }.textFieldStyle(.roundedBorder)
        }
    }

    private func backupRow(_ backup: LocalBackup) -> some View {
        Surface(padding: 20) {
            HStack(spacing: 17) {
                GlassIcon(systemName: backup.encrypted ? "lock.shield" : "externaldrive", size: 43, color: Palette.mint)
                VStack(alignment: .leading, spacing: 7) {
                    Text(backup.name).font(.system(size: 16, weight: .medium))
                    Text("\(backup.productType) · iOS/iPadOS \(backup.version) · \(backup.encrypted ? L("Chiffrée") : L("Non chiffrée"))")
                        .font(.system(size: 11)).foregroundStyle(Palette.secondary)
                    if let date = backup.date { Text(date, format: .dateTime.day().month(.wide).year().hour().minute()).font(.system(size: 11)).foregroundStyle(Palette.secondary) }
                    if let issue = backup.restorationIssue(for: model.device) {
                        Text(issue).font(.system(size: 11)).foregroundStyle(Palette.amber)
                    } else { Text(L("Sauvegarde terminée")).font(.system(size: 11)).foregroundStyle(Palette.mint) }
                }
                Spacer()
                Button { model.revealBackupFolder(backup) } label: { Image(systemName: "folder") }
                    .help(L("Afficher dans le Finder")).accessibilityLabel(L("Afficher la sauvegarde dans le Finder"))
                Button(L("Restaurer…")) { model.presentBackupRestore(backup) }
                    .disabled(!model.canStartBackup || backup.restorationIssue(for: model.device) != nil)
            }.buttonStyle(QuietButtonStyle())
        }
    }
}

struct BackupRestoreConfirmation: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let backup: LocalBackup
    @ViewState private var password = ""
    @ViewState private var acknowledged = false
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            GlassIcon(systemName: "externaldrive.badge.timemachine", size: 64, color: Palette.mint)
            Text(L("Restaurer cette sauvegarde ?")).font(.system(size: 27, weight: .medium))
            Text(L("De \(backup.name) vers \(model.backupRestoreTarget?.name ?? L("l’appareil sélectionné"))")).font(.system(size: 16, weight: .medium))
            if let date = backup.date { Text(date, format: .dateTime.day().month(.wide).year().hour().minute()).foregroundStyle(Palette.secondary) }
            Text(L("Les données et réglages de la sauvegarde remplaceront ceux de l’appareil. La version d’iOS installée restera la même. Sauvegardez d’abord les données actuelles si vous souhaitez les conserver.")).lineSpacing(4)
            Text(L("Gardez le câble connecté jusqu’à la fin. L’appareil pourra redémarrer et demander votre compte Apple. Si iOS le demande, désactivez Localiser dans ses réglages.")).foregroundStyle(Palette.secondary).lineSpacing(4)
            if backup.encrypted { SecureField(L("Mot de passe de la sauvegarde"), text: $password).textFieldStyle(.roundedBorder) }
            if passwordRejected {
                Text(L("Ce mot de passe contient des caractères que le moteur de sauvegarde ne peut pas recevoir (255 caractères ASCII imprimables au plus). Restaurez cette sauvegarde avec le Finder."))
                    .font(.system(size: 11)).foregroundStyle(Palette.amber).fixedSize(horizontal: false, vertical: true)
            }
            Toggle(L("Je confirme la cible et le remplacement de ses données."), isOn: $acknowledged)
            HStack {
                Button(L("Annuler")) { dismiss() }.buttonStyle(QuietButtonStyle()).keyboardShortcut(.cancelAction)
                Spacer()
                Button(L("Restaurer les données")) { model.restoreBackup(backup, password: password); password = "" }
                    .buttonStyle(PrimaryButtonStyle(destructive: true))
                    .disabled(!acknowledged || !model.canStartBackup || (backup.encrypted && password.isEmpty) || passwordRejected)
            }
        }.padding(30).frame(width: 550).foregroundStyle(Palette.ink).background(Palette.canvas)
            .onDisappear { password = "" }
    }
    private var passwordRejected: Bool { backup.encrypted && !password.isEmpty && BackupHost.passwordIssue(password) != nil }
}
