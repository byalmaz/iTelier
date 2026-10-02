import AppKit
import SwiftUI
import ReScopeCore

struct ActivityView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if model.activity.isEmpty {
                Surface {
                    VStack(spacing: 22) {
                        GlassIcon(systemName: "clock.arrow.circlepath", size: 116, color: Palette.violet)
                            .padding(.bottom, 6).accessibilityHidden(true)
                        Text(L("Le début d’une nouvelle session.")).font(.system(size: 28, weight: .light))
                        Text(L("Vos vérifications, analyses IPSW et restaurations apparaîtront ici."))
                            .font(.system(size: 13)).foregroundStyle(Palette.secondary)
                    }.frame(maxWidth: .infinity).padding(.vertical, 58)
                }
            } else {
                Surface {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(model.activity) { entry in
                            HStack(alignment: .top, spacing: 15) {
                                Image(systemName: entry.symbol).font(.system(size: 18)).foregroundStyle(Palette.accent)
                                    .frame(width: 43, height: 43).background(Palette.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Palette.accent.opacity(0.18)))
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(AppLocalization.label(entry.title)).font(.system(size: 14, weight: .medium))
                                    Text(model.sanitizedLog(entry.message)).font(.system(size: 12)).foregroundStyle(Palette.secondary).lineSpacing(3)
                                }
                                Spacer()
                                Text(entry.date.uiFormatted(date: .omitted, time: .shortened)).font(.system(size: 11)).foregroundStyle(Palette.secondary)
                            }.padding(.vertical, 17)
                            if entry.id != model.activity.last?.id { Rectangle().fill(Palette.line.opacity(0.65)).frame(height: 1) }
                        }
                    }
                }
            }
            if !model.logs.isEmpty {
                Surface {
                    DisclosureGroup(L("Journal de la dernière restauration")) {
                        Text(model.sanitizedLog(model.logs.joined(separator: "\n")))
                            .font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 15)
                    }
                }
            }
            Button(L("Signaler un problème…")) { model.openSupportReport() }.buttonStyle(QuietButtonStyle())
            Label(L("Un journal de sécurité local permet de retrouver une opération interrompue. Les rapports d’incident restent sur votre Mac jusqu’à votre partage."), systemImage: "lock")
                .font(.system(size: 11)).foregroundStyle(Palette.secondary)
        }
        .foregroundStyle(Palette.ink)
    }
}

struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @ViewState private var showVisionGuide = false
    @ViewState private var isRefreshingSettings = false
    @ViewState private var refreshMessage: String?
    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                GlassIcon(systemName: "gearshape.fill", size: 48, color: Palette.violet)
                    .accessibilityHidden(true)
                Text(L("Configuration")).font(.system(size: 28, weight: .light)).tracking(-0.6)
                Spacer()
                Button { dismiss() } label: { CloseGlyph() }.buttonStyle(.plain).accessibilityLabel(L("Fermer la configuration"))
            }
            Surface(padding: 18) {
                VStack(alignment: .leading, spacing: 16) {
                    Text(L("Personnalisation")).font(.system(size: 15, weight: .medium))
                    Picker(L("Apparence"), selection: $model.appearance) {
                        ForEach(AppAppearance.allCases) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented)
                    Picker(L("Langue"), selection: $model.language) {
                        ForEach(AppLanguage.allCases) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented).disabled(model.busy)
                    Text(L("Les menus macOS suivent la langue choisie au prochain lancement."))
                        .font(.system(size: 11)).foregroundStyle(Palette.secondary)
                    Button(L("Revoir la visite guidée")) {
                        dismiss()
                        Task { @MainActor in
                            try? await Task.sleep(nanoseconds: 350_000_000)
                            model.showOnboarding = true
                        }
                    }.buttonStyle(QuietButtonStyle()).disabled(model.busy)
                }
            }
            Button(L("Guide de restauration Vision Pro")) { showVisionGuide = true }.buttonStyle(QuietButtonStyle())
            DisclosureGroup(L("Infos · À propos d’iTelier")) {
                VStack(alignment: .leading, spacing: 13) {
                    Text(L("Conçue en Belgique 🇧🇪")).font(.system(size: 22, weight: .light))
                    Text(L("Vos appareils. Vos données. Votre liberté.")).font(.system(size: 14, weight: .medium))
                    Text(L("iTelier est une alternative libre et open source pour gérer vos appareils Apple depuis votre Mac. Vérifier, télécharger, restaurer et sauvegarder : les fonctions essentielles, sans abonnement."))
                    Text(L("Un projet indépendant, pensé pour une interface soignée, des opérations transparentes et des données qui restent sous votre contrôle. Vous pouvez étudier, modifier et partager le code d’iTelier sous licence MIT."))
                    Text(L("iTelier s’appuie sur libimobiledevice, libirecovery et idevicerestore. Les catalogues sont fournis par IPSW.me et AppleDB ; les firmwares sont téléchargés depuis les serveurs Apple."))
                    Text(L("Les outils intégrés et les illustrations Apple conservent leurs licences et droits respectifs. iTelier n’est pas affilié à Apple."))
                        .font(.system(size: 11))
                    Text("Version \(model.appVersion)").font(.system(size: 11, design: .monospaced))
                }.font(.system(size: 12)).foregroundStyle(Palette.secondary).lineSpacing(4)
                    .padding(.top, 14).fixedSize(horizontal: false, vertical: true)
            }.font(.system(size: 15, weight: .medium)).padding(.vertical, 6)
            Text(L("Les outils de détection USB, de diagnostic et de restauration IPSW sont inclus dans iTelier."))
                .font(.system(size: 12)).foregroundStyle(Palette.secondary).lineSpacing(4)
            Surface(padding: 16) {
                VStack(spacing: 14) {
                    ForEach(model.tools) { tool in
                        HStack(spacing: 11) {
                            Image(systemName: tool.isInstalled ? "checkmark.circle.fill" : "minus.circle")
                                .foregroundStyle(tool.isInstalled ? Palette.mint : Palette.secondary)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(toolLabel(tool.name)).font(.system(size: 12, weight: .medium))
                                Text(tool.name).font(.system(size: 10, design: .monospaced)).foregroundStyle(Palette.secondary)
                            }
                            Spacer()
                            Text(tool.path?.contains("/Contents/Helpers/") == true ? L("Inclus dans l’app") : tool.isInstalled ? L("Disponible") : L("À installer")).font(.system(size: 11)).foregroundStyle(Palette.secondary)
                        }
                    }
                }
            }
            HStack {
                Link(L("Projet libimobiledevice"), destination: URL(string: "https://libimobiledevice.org/")!)
                Spacer()
                Link(L("Moteur de restauration"), destination: URL(string: "https://github.com/libimobiledevice/idevicerestore#building")!)
            }.font(.system(size: 11))
            Rectangle().fill(Palette.line).frame(height: 1)
            VStack(alignment: .leading, spacing: 10) {
                Text(L("Dossier des fichiers IPSW")).font(.system(size: 14, weight: .medium))
                HStack {
                    Label(model.downloadFolderLabel, systemImage: "folder").font(.system(size: 12)).lineLimit(2).textSelection(.enabled)
                    Spacer()
                    Button(L("Ouvrir")) { model.revealDownloadDirectory() }.buttonStyle(QuietButtonStyle())
                    Button(L("Modifier…")) { model.chooseDownloadDirectory() }.buttonStyle(QuietButtonStyle()).disabled(model.busy)
                }
                Text(L("Créé automatiquement au premier téléchargement. Aucun choix de dossier à chaque fois."))
                    .font(.system(size: 11)).foregroundStyle(Palette.secondary)
            }
            Rectangle().fill(Palette.line).frame(height: 1)
            VStack(alignment: .leading, spacing: 10) {
                Text(L("Restauration par défaut")).font(.system(size: 14, weight: .medium))
                Toggle(L("Conserver les données de l’appareil"), isOn: Binding(
                    get: { model.defaultRestoreMode == .preserveData },
                    set: { model.setDefaultRestoreMode($0 ? .preserveData : .erase) }
                )).toggleStyle(.checkbox).font(.system(size: 12)).disabled(!model.canChangeRestoreMode)
                Text(L("Ce choix est mémorisé après fermeture et appliqué dans Restaurer. Vous pouvez le modifier dans Restaurer pour la session en cours."))
                    .font(.system(size: 11)).foregroundStyle(Palette.secondary).lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                Text(model.defaultRestoreMode == .preserveData
                    ? L("Conservation des données proposée. Une sauvegarde récente reste nécessaire.")
                    : L("Effacement complet proposé. Toutes les données seront supprimées si vous confirmez la restauration."))
                    .font(.system(size: 11)).foregroundStyle(model.defaultRestoreMode == .preserveData ? Palette.secondary : Palette.amber)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Rectangle().fill(Palette.line).frame(height: 1)
            Toggle(L("Afficher les numéros de série dans les rapports et leurs exports"), isOn: $model.revealIdentifiers)
                .toggleStyle(.checkbox).font(.system(size: 12))
            Text(L("Par défaut, numéros de série, ECID et adresses réseau sont masqués. Les journaux techniques du moteur peuvent contenir d’autres données."))
                .font(.system(size: 11)).foregroundStyle(Palette.secondary).lineSpacing(3)
            HStack {
                Button(model.isDemo ? L("Quitter l’aperçu") : L("Explorer avec un appareil d’exemple")) { model.toggleDemo(); dismiss() }
                    .buttonStyle(QuietButtonStyle()).disabled(model.busy)
                Spacer()
                Button {
                    isRefreshingSettings = true
                    refreshMessage = nil
                    Task { await refreshSettings() }
                } label: {
                    HStack(spacing: 8) {
                        if isRefreshingSettings { ProgressView().controlSize(.small) }
                        Text(isRefreshingSettings ? L("Actualisation…") : L("Actualiser"))
                    }
                }.buttonStyle(QuietButtonStyle())
                    .disabled(model.busy || isRefreshingSettings)
                    .help(L("Revérifier les outils et la connexion USB de l’appareil"))
            }
            if let refreshMessage {
                Text(refreshMessage).font(.system(size: 11)).foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Text(L("iTelier \(model.appVersion) · Open source")).font(.system(size: 10)).foregroundStyle(Palette.secondary)
                Spacer()
                Button(L("Signaler un problème…")) { model.openSupportReport() }.buttonStyle(.plain).font(.system(size: 12))
            }
        }.padding(30).frame(maxWidth: .infinity, alignment: .leading)
        }.sheet(isPresented: $showVisionGuide) { VisionProGuideView() }
        .frame(width: 680, height: 740).foregroundStyle(Palette.ink).background(Palette.canvas)
            
    }
    private func refreshSettings() async {
        defer { isRefreshingSettings = false }
        model.tools = DeviceService.toolStatus()
        let available = model.tools.filter(\.isInstalled).count
        let toolsSummary = L("\(available)/\(model.tools.count) outils disponibles.")
        if model.isDemo {
            refreshMessage = L("\(toolsSummary) Quittez l’aperçu pour détecter votre appareil USB.")
            return
        }
        // Reuse an ongoing automatic discovery instead of starting a competing USB read.
        if model.isRefreshing {
            do {
                while model.isRefreshing { try await Task.sleep(nanoseconds: 100_000_000) }
            } catch { return }
        } else {
            guard model.canRefreshDevices else {
                refreshMessage = L("Une opération est en cours. Réessayez lorsqu’elle sera terminée.")
                return
            }
            await model.refresh()
        }
        let connection = model.connectionIssue?.title
            ?? (model.devices.isEmpty ? L("Aucun appareil détecté") : model.devices.count == 1 ? L("1 appareil détecté") : L("\(model.devices.count) appareils détectés"))
        refreshMessage = L("Actualisé à \(Date().uiFormatted(date: .omitted, time: .standard)). \(toolsSummary) \(connection).")
    }
    private func toolLabel(_ name: String) -> String {
        switch name {
        case "idevice_id": return L("Détection USB")
        case "ideviceinfo": return L("Informations de l’appareil")
        case "idevicediagnostics": return L("Diagnostic de la batterie")
        case "irecovery": return L("Détection récupération / DFU")
        case "idevicerestore": return L("Restauration IPSW")
        default: return name
        }
    }
}
