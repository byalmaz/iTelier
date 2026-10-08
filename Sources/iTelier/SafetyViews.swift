import SwiftUI
import iTelierCore

struct RestoreOptionsView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        Surface {
            VStack(alignment: .leading, spacing: 16) {
                Text(L("Options de restauration")).font(.system(size: 23, weight: .light))
                Picker(L("Opération"), selection: Binding(
                    get: { model.restoreMode },
                    set: { if model.canChangeRestoreMode { model.restoreMode = $0 } }
                )) {
                    Text(L("Mettre à jour")).tag(RestoreMode.preserveData)
                    Text(L("Restaurer")).tag(RestoreMode.erase)
                }.pickerStyle(.segmented).disabled(!model.canChangeRestoreMode)
                Text(model.restoreMode == .preserveData
                    ? L("Réinstalle iOS en conservant les apps, photos et réglages. Une sauvegarde reste nécessaire : une erreur peut entraîner une perte de données. Aucun effacement automatique en cas d’échec.")
                    : L("Toutes les données de l’appareil seront effacées. Préparez une sauvegarde et gardez le câble branché pendant l’opération."))
                    .font(.system(size: 13)).foregroundStyle(Palette.secondary).lineSpacing(4)
                if model.restoreMode == .preserveData, let device = model.device, let firmware = model.firmware,
                   let issue = firmware.preservationIssue(for: device, declaration: model.systemDeclaration) {
                    Label(issue, systemImage: "exclamationmark.triangle").font(.system(size: 11)).foregroundStyle(Palette.amber)
                }
                if model.needsSystemDeclaration {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L("Version installée avant le problème")).font(.system(size: 13, weight: .medium))
                        HStack {
                            TextField(L("Version (ex. 27.2)"), text: $model.declaredSystemVersion)
                            TextField(L("Build (ex. 24B5089g)"), text: $model.declaredSystemBuild)
                        }.textFieldStyle(.roundedBorder)
                        Text(L("Le build est le numéro détaillé de la version, affiché entre parenthèses dans les informations de l’appareil."))
                            .font(.system(size: 11)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
                        Text(L("Cette version est indiquée par vous. Une information incorrecte peut conduire à installer une version trop ancienne et compromettre vos données."))
                            .font(.system(size: 11)).foregroundStyle(Palette.amber).fixedSize(horizontal: false, vertical: true)
                        Toggle(L("Je confirme la version et le build installés avant le problème."), isOn: $model.declaredSystemAcknowledged)
                            .disabled(model.systemDeclaration == nil)
                    }.disabled(!model.canChangeRestoreMode || model.preparationBusy)
                }
                Toggle(model.restoreMode == .preserveData ? L("J’ai une sauvegarde récente de mes données.") : L("J’ai sauvegardé mes données ou j’accepte de les perdre."), isOn: $model.backupAcknowledged)
                Toggle(L("Je dispose des identifiants Apple nécessaires à l’activation."), isOn: $model.appleIDAcknowledged)
                Label(model.device.map { "\($0.name) · \($0.mode.title) · ECID \(model.visible($0.ecid, sensitive: true))" } ?? L("Aucun appareil sélectionné"), systemImage: "cable.connector")
                    .font(.system(size: 11)).foregroundStyle(Palette.secondary)
                if let device = model.device, device.ecid == nil {
                    Text(L("L’identité ECID est indisponible. La restauration reste bloquée pour éviter de cibler le mauvais appareil."))
                        .font(.system(size: 11)).foregroundStyle(Palette.amber)
                }
            }.toggleStyle(.checkbox).font(.system(size: 13))
        }
    }
}

struct RestorePreparationView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack(spacing: 16) {
                        GlassIcon(systemName: "checkmark.seal.fill", size: 54, color: Palette.mint)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(L("Votre IPSW est prêt.")).font(.system(size: 28, weight: .light))
                            Text(model.firmware.map { "iOS / iPadOS \($0.version) · build \($0.build)" } ?? L("Firmware vérifié"))
                                .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                        }
                    }
                    RestoreOptionsView()
                    RestoreAccessoryGuidance()
                    Text(L("Vérifiez le mode choisi. Une dernière confirmation précède le lancement sur votre appareil."))
                        .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                }
            }.frame(maxHeight: 540)
            HStack {
                Button(L("Plus tard")) { model.showRestorePreparation = false }.buttonStyle(QuietButtonStyle())
                Spacer()
                Button(L("Continuer…")) { model.presentConfirmation() }.buttonStyle(PrimaryButtonStyle()).disabled(!model.canRestore)
            }
        }.padding(28).frame(width: 590).foregroundStyle(Palette.ink).background(Palette.canvas)
    }
}

struct SafetyNoticeView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        HStack(alignment: .center, spacing: 13) {
            Image(systemName: "exclamationmark.shield.fill").foregroundStyle(Palette.amber)
            VStack(alignment: .leading, spacing: 5) {
                Text(model.safetyStorageError != nil ? L("Journal de sécurité indisponible") : model.isRestoring ? L("Suivi de la restauration retrouvé") : model.recoveryRequired ? L("Vérifiez l’appareil avant de continuer") : L("iTelier a quitté de façon inattendue"))
                    .font(.system(size: 12, weight: .medium))
                Text(model.safetyStorageError ?? (model.isRestoring
                    ? L("Le moteur indépendant reste actif. Gardez le câble branché.")
                    : model.recoveryRequired ? L("Aucune restauration ne sera relancée automatiquement. Gardez l’appareil connecté et actualisez son état.")
                    : L("Un rapport local est disponible. Vous pouvez le consulter et le partager.")))
                    .font(.system(size: 11)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 5)
            Button(L("Rapport…")) { model.openSupportReport() }.buttonStyle(QuietButtonStyle())
            if model.recoveryRequired && !model.isRestoring {
                Button(L("Vérifier l’appareil")) { Task { await model.recheckAfterInterruption() } }
                    .buttonStyle(QuietButtonStyle()).disabled(model.busy || model.isRefreshing || model.isDemo)
            } else if !model.recoveryRequired && model.safetyStorageError == nil {
                Button { model.interruptionNotice = false } label: { CloseGlyph() }
                    .buttonStyle(.plain).accessibilityLabel(L("Masquer l’avis d’interruption"))
            }
        }.padding(15).background(Palette.amber.opacity(0.06))
            .padding(.horizontal, 30).padding(.bottom, 6)
    }
}

struct SupportReportView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            HStack(spacing: 13) {
                GlassIcon(systemName: "doc.text.magnifyingglass", size: 48, color: Palette.violet)
                Text(L("Rapport d’incident")).font(.system(size: 28, weight: .light))
                Spacer()
                Button { model.showSupportReport = false } label: { CloseGlyph() }
                    .buttonStyle(.plain).accessibilityLabel(L("Fermer le rapport"))
            }
            Text(L("Ce rapport reste sur votre Mac. Il contient la version d’iTelier, macOS, le modèle d’appareil et l’étape concernée. Les identifiants, chemins et journaux bruts sont exclus."))
                .font(.system(size: 12)).foregroundStyle(Palette.secondary).lineSpacing(4)
            Text(L("Que s’est-il passé ? (facultatif)")).font(.system(size: 12, weight: .medium))
            TextEditor(text: $model.supportDescription).font(.system(size: 12)).frame(height: 76)
                .padding(8).background(Palette.card, in: RoundedRectangle(cornerRadius: 10))
                .accessibilityLabel(L("Description du problème"))
                .onChange(of: model.supportDescription) { value in
                    if value.count > 4_000 { model.supportDescription = String(value.prefix(4_000)) }
                }
            Text(L("Contenu exact du rapport")).font(.system(size: 12, weight: .medium))
            ScrollView {
                Text(model.supportReportText).font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(14)
            }.frame(height: 205).background(Palette.deep.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
            Text(L("Relisez aussi votre description avant de partager. « Envoyer » ouvre le partage macOS : vous choisissez le destinataire et validez l’envoi."))
                .font(.system(size: 11)).foregroundStyle(Palette.secondary)
            HStack {
                Button(L("Copier")) { model.copySupportReport() }.buttonStyle(QuietButtonStyle())
                Button(L("Exporter…")) { model.exportSupportReport() }.buttonStyle(QuietButtonStyle())
                Spacer()
                ShareLink(item: model.supportReportText) { Label(L("Envoyer…"), systemImage: "square.and.arrow.up") }
                    .buttonStyle(PrimaryButtonStyle())
            }
        }.padding(28).frame(width: 610).foregroundStyle(Palette.ink).background(Palette.canvas)
    }
}
