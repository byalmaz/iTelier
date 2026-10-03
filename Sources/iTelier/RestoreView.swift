import SwiftUI
import iTelierCore
import UniformTypeIdentifiers

struct RestoreView: View {
    @EnvironmentObject private var model: AppModel
    @ViewState private var isTargeted = false
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if model.device?.isVisionPro == true {
                Surface {
                    VStack(alignment: .leading, spacing: 14) {
                        Label(L("Apple Vision Pro · visionOS"), systemImage: "visionpro").font(.system(size: 22, weight: .light))
                        Text(L("Téléchargez un IPSW visionOS depuis le catalogue. Pour restaurer le casque, suivez le parcours Apple Configurator.")).foregroundStyle(Palette.secondary)
                        Button(L("Guide de restauration Vision Pro")) { model.showVisionProGuide = true }.buttonStyle(PrimaryButtonStyle())
                    }
                }
            }
            RestoreSessionsView()
            if model.selectedDeviceRestoring || model.hasUnidentifiedRestore {
                Surface(padding: 20) {
                    VStack(alignment: .leading, spacing: 10) {
                        Label(L("Cet appareil est en cours de restauration."), systemImage: "arrow.triangle.2.circlepath")
                        Text(L("Choisissez un autre appareil connecté pour préparer sa restauration. Chaque appareil garde sa version et ses réglages."))
                            .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                    }
                }
            } else {
                HStack(spacing: 0) {
                    step(1, model.isDownloadingFirmware && !model.isCheckingExistingFirmware ? L("Télécharger") : L("Choisir l’IPSW"), active: model.firmware == nil && !model.isInspecting)
                    Rectangle().fill(Palette.line).frame(height: 1).padding(.horizontal, 15)
                    step(2, L("Vérifier"), active: model.firmware != nil || model.isInspecting)
                    Rectangle().fill(Palette.line).frame(height: 1).padding(.horizontal, 15)
                    step(3, L("Restaurer"), active: false)
                }.padding(.horizontal, 10).padding(.vertical, 3)
                if model.isDownloadingFirmware { downloadCard }
                else { firmwareCard }
                if let firmware = model.firmware {
                    compatibility(firmware)
                }
                RestoreOptionsView()
                RestoreAccessoryGuidance()
                if !model.isDownloadingFirmware { HStack {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(L("Prêt pour un nouveau départ ?")).font(.system(size: 22, weight: .light))
                        Text(model.device == nil ? L("Connectez un appareil pour continuer.") : model.isDemo ? L("Le lancement est désactivé dans l’aperçu.") : (model.restoreMode == .erase ? L("Une dernière confirmation précède l’effacement.") : L("Une dernière confirmation précède la réinstallation.")))
                            .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                    }
                    Spacer()
                    Button {
                        model.presentConfirmation()
                    } label: { Label(L("Restaurer…"), systemImage: "arrow.triangle.2.circlepath") }
                        .buttonStyle(PrimaryButtonStyle()).disabled(!model.canRestore)
                }.padding(.top, 4) }
                if !model.installed("idevicerestore"), !model.isDemo {
                    HStack(spacing: 9) {
                        Image(systemName: "puzzlepiece.extension")
                        Text(L("Le moteur de restauration doit être installé pour lancer l’opération."))
                        Spacer()
                        Button(L("Configuration")) { model.showSettings = true }.buttonStyle(.plain).fontWeight(.semibold)
                    }.font(.system(size: 12)).foregroundStyle(Palette.secondary).padding(16)
                        .background(Palette.card.opacity(0.6), in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.line))
                }
            }
        }
        .foregroundStyle(Palette.ink)
    }
    private var firmwareCard: some View {
        Surface(padding: 30) {
            HStack(spacing: 30) {
                GlassIcon(systemName: "doc.badge.gearshape", size: 112, color: Palette.violet)
                    .frame(width: 128, height: 138).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 10) {
                    Eyebrow(text: model.firmwareSourceRelease == nil ? L("Firmware IPSW") : L("IPSW vérifié"))
                    Text(model.isInspecting ? L("Analyse du firmware…") : model.firmware?.url.lastPathComponent ?? L("Déposez votre fichier IPSW."))
                        .font(.system(size: 25, weight: .light)).tracking(-0.4).lineLimit(2)
                    if let firmware = model.firmware {
                        let systems = Set(firmware.supportedProductTypes.map { DeviceFamily(identifier: $0).systemName }).sorted().joined(separator: " / ")
                        Text("\(systems) \(firmware.version) · build \(firmware.build) · \(localizedByteCount( firmware.sizeBytes))")
                            .font(.system(size: 13)).foregroundStyle(Palette.secondary)
                    } else {
                        Text(L("Choisissez une version à télécharger depuis Apple,\nou utilisez un fichier IPSW déjà sur votre Mac."))
                            .font(.system(size: 13)).foregroundStyle(Palette.secondary).lineSpacing(5)
                    }
                    if model.isInspecting {
                        HStack(spacing: 10) { ProgressView().controlSize(.small); Text(L("Lecture du manifeste et calcul SHA-256")).font(.system(size: 11)).foregroundStyle(Palette.secondary) }
                    } else {
                        HStack(spacing: 10) {
                            Button(L("Choisir une version")) { model.openFirmwareBrowser() }
                                .buttonStyle(PrimaryButtonStyle()).disabled(model.preparationBusy)
                            Button(model.firmware == nil ? L("Fichier local…") : L("Autre fichier…")) { model.chooseFirmware() }
                                .buttonStyle(QuietButtonStyle()).disabled(!model.canInspect)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }.overlay(RoundedRectangle(cornerRadius: 20).stroke(isTargeted ? Palette.accent : Color.clear, lineWidth: 2))
            .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
                guard model.canInspect, let provider = providers.first else { return false }
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                    let url: URL?
                    if let value = item as? URL { url = value }
                    else if let data = item as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
                    else { url = nil }
                    if let url { Task { @MainActor in await model.inspectFirmware(url) } }
                }
                return true
            }
    }
    private var downloadCard: some View {
        FirmwareTransferCard(
            version: model.downloadRelease.map { "\(DeviceFamily(identifier: $0.identifier).systemName) \($0.displayVersion)" } ?? L("Firmware IPSW"),
            details: model.downloadRelease.map { "Build \($0.buildID) · \($0.identifier)" } ?? "",
            host: model.downloadRelease?.url.host,
            size: downloadSize, fraction: model.downloadFraction,
            isPaused: model.isDownloadPaused, isVerifying: model.isInspecting,
            isCheckingExisting: model.isCheckingExistingFirmware,
            isCancelling: model.isCancellingFirmware,
            onTogglePause: { model.toggleDownloadPause() },
            onCancel: { model.cancelFirmwareDownload() })
    }
    private var downloadSize: String {
        let received = localizedByteCount( model.downloadBytesWritten)
        guard let total = model.downloadTotalBytes else { return L("\(received) reçus") }
        return "\(received) sur \(localizedByteCount( total))"
    }
    private func compatibility(_ firmware: FirmwareInfo) -> some View {
        let compatible = model.device.map { firmware.supports($0, mode: model.restoreMode) }
        return Surface(padding: 20) {
            VStack(alignment: .leading, spacing: 13) {
                HStack {
                    Label(compatible == true ? L("Firmware compatible avec cet appareil") : compatible == false ? L("Ce firmware ne correspond pas à l’appareil") : L("Connectez un appareil pour vérifier la compatibilité"),
                          systemImage: compatible == true ? "checkmark.circle" : compatible == false ? "xmark.circle" : "info.circle")
                        .font(.system(size: 13, weight: .medium)).foregroundStyle(compatible == true ? Palette.mint : compatible == false ? Palette.red : Palette.secondary)
                    Spacer()
                }
                Text(L("Modèles : \(firmware.supportedProductTypes.joined(separator: ", "))")).font(.system(size: 11)).foregroundStyle(Palette.secondary).textSelection(.enabled)
                Rectangle().fill(Palette.line).frame(height: 1)
                Label(L("Signature Apple : vérifiée par le moteur lors de la restauration."), systemImage: "network")
                    .font(.system(size: 11)).foregroundStyle(Palette.secondary)
                Text(L("La compatibilité locale ne garantit pas qu’Apple autorise encore cette version."))
                    .font(.system(size: 10)).foregroundStyle(Palette.secondary)
                if let source = model.firmwareSourceRelease {
                    Label(source.signed ? L("Version indiquée signée dans le catalogue au téléchargement.") : L("Version indiquée non signée : restauration standard indisponible."),
                          systemImage: source.signed ? "checkmark.seal" : "exclamationmark.circle")
                        .font(.system(size: 11)).foregroundStyle(source.signed ? Palette.accent : Palette.amber)
                }
                DisclosureGroup(L("Empreinte SHA-256")) {
                    Text(firmware.sha256).font(.system(size: 10, design: .monospaced)).textSelection(.enabled).padding(.top, 7)
                }.font(.system(size: 10)).foregroundStyle(Palette.secondary)
            }
        }
    }
    private var progress: some View {
        Surface(padding: 30) {
            VStack(alignment: .leading, spacing: 22) {
                HStack(spacing: 22) {
                    GlassIcon(systemName: model.restorationComplete ? "checkmark.circle.fill" : model.restorationFailed ? "exclamationmark.circle.fill" : "arrow.triangle.2.circlepath",
                                 size: 77, color: model.restorationComplete ? Palette.mint : model.restorationFailed ? Palette.red : Palette.accent)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.restorePhase).font(.system(size: 26, weight: .light)).tracking(-0.5)
                        Text(model.restorationComplete ? L("L’appareil peut encore terminer son démarrage. Gardez-le connecté jusqu’à l’écran d’accueil ou de configuration.") : model.restorationFailed ? L("Consultez le journal, puis vérifiez le câble et le firmware avant un nouvel essai.") : L("Gardez l’appareil connecté. Cette opération peut prendre plusieurs minutes."))
                            .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                    }
                }
                Label((model.activeRestoreMode ?? model.restoreMode) == .preserveData ? L("Conservation des données") : L("Effacement complet"),
                      systemImage: (model.activeRestoreMode ?? model.restoreMode) == .preserveData ? "lock.shield" : "trash")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle((model.activeRestoreMode ?? model.restoreMode) == .preserveData ? Palette.accent : Palette.red)
                    .padding(.horizontal, 14).padding(.vertical, 10)
                    .background(((model.activeRestoreMode ?? model.restoreMode) == .preserveData ? Palette.accent : Palette.red).opacity(0.10), in: Capsule())
                if let progress = model.restoreProgress {
                    ProgressView(value: progress).tint(Palette.accent)
                    Text(L("Progression de la phase en cours : \(Int(progress * 100)) %"))
                        .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                } else if model.isRestoring { ProgressView().progressViewStyle(.linear).tint(Palette.accent) }
                if model.isRestoring {
                    Label(L("L’application reste ouverte pendant l’écriture du firmware."), systemImage: "info.circle")
                        .font(.system(size: 11)).foregroundStyle(Palette.secondary)
                    Text(L("Si macOS demande d’autoriser l’appareil, cliquez sur « Autoriser » et gardez le câble branché."))
                        .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } else if model.restorationComplete, model.device == nil {
                    Text(L("Votre appareil peut encore redémarrer. Gardez-le connecté le temps qu’il réapparaisse dans iTelier."))
                        .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                DisclosureGroup(L("Journal du moteur · peut contenir des informations techniques")) {
                    ScrollView {
                        Text(model.sanitizedLog(model.logs.joined(separator: "\n")))
                            .font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(14)
                    }.frame(height: 240).background(Palette.deep.opacity(0.45), in: RoundedRectangle(cornerRadius: 14))
                        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.line)).padding(.top, 10)
                }.font(.system(size: 11))
                if model.restorationComplete {
                    Button(L("Revenir à mon appareil")) { model.restorationComplete = false; model.page = .overview; Task { await model.refresh() } }.buttonStyle(PrimaryButtonStyle())
                }
                if model.restorationFailed {
                    HStack {
                        Button(L("Revoir les prérequis")) { model.restorationFailed = false; Task { await model.recheckAfterInterruption() } }.buttonStyle(PrimaryButtonStyle())
                        Button(L("Rapport d’incident…")) { model.openSupportReport() }.buttonStyle(QuietButtonStyle())
                    }
                }
            }
        }
    }
    private func step(_ number: Int, _ title: String, active: Bool) -> some View {
        HStack(spacing: 8) {
            Text(String(number)).font(.system(size: 12, weight: .medium)).frame(width: 30, height: 30)
                .background(active ? Palette.accent : Palette.card, in: Circle()).foregroundStyle(active ? Palette.canvas : Palette.secondary)
                .overlay(Circle().stroke(active ? Palette.accent : Palette.line))
            Text(title).font(.system(size: 12, weight: active ? .medium : .regular)).foregroundStyle(active ? Palette.ink : Palette.secondary).fixedSize()
        }
    }
}

struct RestoreConfirmation: View {
    @EnvironmentObject private var model: AppModel
    private var preservesData: Bool { model.confirmationMode == .preserveData }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            GlassIcon(systemName: preservesData ? "arrow.triangle.2.circlepath" : "exclamationmark.triangle.fill", size: 63, color: preservesData ? Palette.accent : Palette.red)
                .accessibilityHidden(true)
            Text(preservesData ? L("Réinstaller en conservant les données ?") : L("Effacer et restaurer cet appareil ?")).font(.system(size: 26, weight: .light)).tracking(-0.6)
            Text(preservesData
                ? L("Le mode de mise à jour sera imposé. Il ne garantit pas l’absence de perte de données : conservez une sauvegarde récente. En cas d’échec, l’opération s’arrête sans relance en mode effacement.")
                : L("Toutes les données seront effacées. La restauration peut échouer si Apple ne signe plus ce firmware. Le verrouillage d’activation restera applicable."))
                .font(.system(size: 13)).foregroundStyle(Palette.secondary).lineSpacing(5)
            Surface(padding: 16) {
                VStack(alignment: .leading, spacing: 10) {
                    LabeledContent("Mode", value: model.confirmationMode?.title ?? "—")
                    LabeledContent(L("Appareil"), value: model.confirmationDevice?.name ?? L("Aucun"))
                    LabeledContent(L("Modèle"), value: model.confirmationDevice?.productType ?? "—")
                    LabeledContent("ECID", value: model.confirmationDevice?.ecid.map { "••••\($0.suffix(6))" } ?? "—")
                    LabeledContent("Firmware", value: model.confirmationFirmware.map { "\($0.version) (\($0.build))" } ?? "—")
                    Text(model.confirmationFirmware?.url.lastPathComponent ?? "").font(.system(size: 10)).foregroundStyle(Palette.secondary).lineLimit(2)
                }.font(.system(size: 12))
            }
            Toggle(preservesData ? L("Je confirme la réinstallation et le risque de perte de données.") : L("Je confirme l’effacement de l’appareil sélectionné."), isOn: $model.operationAcknowledged)
                .toggleStyle(.checkbox).font(.system(size: 12))
            HStack {
                Button(L("Revenir")) { model.showConfirmation = false }.buttonStyle(QuietButtonStyle())
                Spacer()
                Button { Task { await model.beginRestore() } } label: { Text(preservesData ? L("Réinstaller et conserver") : L("Effacer et restaurer")) }
                    .buttonStyle(PrimaryButtonStyle(destructive: !preservesData))
                    .disabled(!model.canConfirmRestore || !model.operationAcknowledged)
            }
        }.padding(30).frame(width: 560).foregroundStyle(Palette.ink).background(Palette.canvas)
            
            .interactiveDismissDisabled(false)
    }
}
