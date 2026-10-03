import SwiftUI
import iTelierCore

struct WorkspaceView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ViewState private var hoveredPage: WorkspacePage?
    @ViewState private var settingsHovered = false
    @ViewState private var showDeviceSelector = false
    var body: some View {
        HStack(spacing: 0) {
            sidebar
            VStack(spacing: 0) {
                header
                if model.interruptionNotice || model.recoveryRequired || model.safetyStorageError != nil { SafetyNoticeView() }
                if model.isDemo {
                    HStack(spacing: 7) {
                        Image(systemName: "sparkles")
                        Text(L("Aperçu · données fictives · opérations sur les appareils désactivées"))
                        Spacer()
                        Button(L("Quitter l’aperçu")) { model.toggleDemo() }.buttonStyle(.plain).fontWeight(.medium)
                    }.font(.system(size: 11)).foregroundStyle(Palette.accent)
                        .padding(.horizontal, 30).padding(.vertical, 10)
                        .background(Palette.accent.opacity(0.055))
                }
                ScrollView {
                    if !model.isDemo, !model.isRestoring, !model.restorationComplete,
                       model.device == nil, let issue = model.connectionIssue {
                        Surface(padding: 18) {
                            HStack(alignment: .top, spacing: 13) {
                                Image(systemName: "cable.connector").foregroundStyle(Palette.amber).font(.system(size: 22))
                                VStack(alignment: .leading, spacing: 7) {
                                    Text(issue.title).font(.system(size: 14, weight: .medium))
                                    Text(issue.message).font(.system(size: 12)).foregroundStyle(Palette.secondary)
                                        .fixedSize(horizontal: false, vertical: true).lineSpacing(3)
                                    HStack(spacing: 16) {
                                        Button(L("Réessayer")) { Task { await model.refresh() } }
                                            .disabled(!model.canRefreshDevices)
                                        Link(L("Aide Apple"), destination: URL(string: "https://support.apple.com/fr-fr/108643")!)
                                    }.buttonStyle(.plain).foregroundStyle(Palette.accent).font(.system(size: 12, weight: .medium)).padding(.top, 3)
                                }
                                Spacer(minLength: 0)
                            }
                        }.padding(.horizontal, 30).padding(.top, 16)
                            .frame(maxWidth: 1250).frame(maxWidth: .infinity)
                    }
                    Group {
                        switch model.page {
                        case .overview: OverviewView()
                        case .restore: RestoreView()
                        case .backups: BackupsView()
                        case .check: CheckView()
                        case .activity: ActivityView()
                        }
                    }.padding(.horizontal, 30).padding(.top, 20).padding(.bottom, 28)
                        .frame(maxWidth: 1250, alignment: .topLeading).frame(maxWidth: .infinity)
                }.id(model.page)
                footer
            }
        }
        .background {
            ZStack {
                LinearGradient(colors: [Palette.backgroundTop, Palette.canvas, Palette.deep], startPoint: .topLeading, endPoint: .bottomTrailing)
                RadialGradient(colors: [Palette.violet.opacity(0.08), .clear], center: .topTrailing, startRadius: 20, endRadius: 650)
            }.ignoresSafeArea()
        }
        .overlay(alignment: .topTrailing) {
            if showDeviceSelector {
                ZStack(alignment: .topTrailing) {
                    Color.black.opacity(0.001).onTapGesture { showDeviceSelector = false }
                    Surface(padding: 14) {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text(L("Appareils connectés")).font(.system(size: 13, weight: .semibold))
                                Spacer()
                                Button { showDeviceSelector = false } label: { CloseGlyph() }
                                    .buttonStyle(.plain).accessibilityLabel(L("Fermer la sélection"))
                            }
                            ScrollView {
                                VStack(spacing: 5) {
                                    ForEach(model.devices) { device in
                                        Button {
                                            model.selectDevice(device.id); showDeviceSelector = false
                                        } label: {
                                            HStack(spacing: 10) {
                                                Image(systemName: device.symbolName)
                                                VStack(alignment: .leading, spacing: 4) {
                                                    Text(device.name).lineLimit(1)
                                                    Text("\(device.mode.title) · ••\((device.ecid ?? device.id).suffix(6))")
                                                        .font(.system(size: 10)).foregroundStyle(Palette.secondary)
                                                }
                                                Spacer()
                                                if device.id == model.selectedDeviceID { Image(systemName: "checkmark").foregroundStyle(Palette.accent) }
                                            }.padding(10).frame(maxWidth: .infinity, alignment: .leading)
                                                .background(device.id == model.selectedDeviceID ? Palette.accent.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 10))
                                                .contentShape(Rectangle())
                                        }.buttonStyle(.plain).disabled(model.isBackupBusy || model.isRefreshing)
                                    }
                                }
                            }.frame(height: min(210, CGFloat(max(1, model.devices.count)) * 58))
                        }
                    }.frame(width: 340).background(Palette.canvas, in: RoundedRectangle(cornerRadius: 20))
                        .padding(.trailing, 30).padding(.top, 95)
                }
            }
        }
        .font(.system(size: 13))
        .foregroundStyle(Palette.ink)
        
        .tint(Palette.accent)
        .sheet(item: $model.backupToRestore) { backup in BackupRestoreConfirmation(backup: backup).environmentObject(model) }
        .sheet(item: $model.informationDevice) { target in DeviceInformationView(target: target).environmentObject(model) }
        .sheet(isPresented: $model.showVisionProGuide) { VisionProGuideView() }
        .sheet(isPresented: $model.showOnboarding) { OnboardingView().environmentObject(model) }
        .sheet(isPresented: $model.showSettings) { SettingsView().environmentObject(model) }
        .sheet(isPresented: $model.showConfirmation) { RestoreConfirmation().environmentObject(model) }
        .sheet(isPresented: $model.showFirmwareBrowser) { FirmwareBrowserView().environmentObject(model) }
        .sheet(isPresented: $model.showRestorePreparation) { RestorePreparationView().environmentObject(model) }
        .sheet(isPresented: $model.showSupportReport) { SupportReportView().environmentObject(model) }
        .alert("iTelier", isPresented: Binding(get: { model.alert != nil }, set: { if !$0 { model.alert = nil } })) {
            Button(L("Compris")) { model.alert = nil }
            Button(L("Rapport…")) { model.openSupportReport() }
        } message: { Text(model.alert ?? "") }
        .task {
            model.offerOnboardingIfNeeded()
            while !Task.isCancelled {
                await model.refresh(automatic: true)
                try? await Task.sleep(nanoseconds: 8_000_000_000)
            }
        }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                GlassIcon(systemName: "viewfinder.circle.fill", size: 30, color: Palette.accent)
                Text("iTelier").font(.system(size: 21, weight: .medium)).tracking(-0.6)
            }.padding(.top, 49).padding(.horizontal, 25).padding(.bottom, 41)
            VStack(spacing: 12) {
                ForEach(WorkspacePage.allCases) { page in
                    Button { model.page = page } label: {
                        HStack(spacing: 13) {
                            GlassIcon(systemName: page.symbol, size: 27, color: page == .restore ? Palette.violet : page == .check ? Palette.accent : (page == .activity || page == .backups) ? Palette.mint : Palette.violet)
                                .compositingGroup()
                                .saturation(hoveredPage == page || model.page == page ? 1 : 0)
                                .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: hoveredPage == page || model.page == page)
                            Text(page.title).font(.system(size: 13, weight: .medium))
                            Spacer(minLength: 0)
                            if page == .restore && model.isRestoring { ProgressView().controlSize(.mini) }
                        }.foregroundStyle(model.page == page ? Palette.ink : Palette.secondary)
                            .padding(.horizontal, 12).padding(.vertical, 13)
                            .contentShape(RoundedRectangle(cornerRadius: 14))
                    }.buttonStyle(.plain)
                        .onHover { hovering in
                            if hovering { hoveredPage = page }
                            else if hoveredPage == page { hoveredPage = nil }
                        }
                        // Keep the visual footprint, with a 3-point inset for clicks and hover.
                        .padding(3)
                        .background {
                            if model.page == page {
                                RoundedRectangle(cornerRadius: 17)
                                    .fill(LinearGradient(colors: [Palette.violet.opacity(0.25), Palette.violet.opacity(0.09)], startPoint: .topLeading, endPoint: .bottomTrailing))
                                    .overlay(RoundedRectangle(cornerRadius: 17).stroke(LinearGradient(colors: [Color(red: 0.78, green: 0.46, blue: 0.86).opacity(0.65), Palette.violet.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)))
                                    .allowsHitTesting(false)
                            }
                        }
                        .accessibilityAddTraits(model.page == page ? .isSelected : [])
                }
            }.padding(.horizontal, 14)
            Spacer(minLength: 25)
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 7) {
                    Circle().fill(model.device != nil ? Palette.accent : Palette.secondary.opacity(0.6)).frame(width: 5, height: 5)
                    Text(model.isDemo ? L("Appareil d’exemple") : model.device != nil ? L("Appareil connecté") : L("En attente d’un appareil"))
                        .font(.system(size: 10))
                }
                if let device = model.device {
                    HStack(spacing: 8) {
                        Text(device.name).font(.system(size: 13, weight: .medium)).foregroundStyle(Palette.ink).lineLimit(1).help(device.name)
                        Spacer(minLength: 0)
                        Button { model.informationDevice = device } label: {
                            Image(systemName: "info.circle").font(.system(size: 16)).frame(width: 27, height: 27).contentShape(Circle())
                        }.buttonStyle(.plain).foregroundStyle(Palette.accent)
                            .accessibilityLabel(L("Informations de l’appareil")).help(L("Informations de l’appareil"))
                    }
                    Text("\(device.family.systemName) \(device.osVersion ?? "—")").font(.system(size: 11)).lineLimit(1)
                    if let serial = device.serialNumber, !serial.isEmpty {
                        HStack(spacing: 4) {
                            Text("SN \(serial)").font(.system(size: 10, design: .monospaced)).lineLimit(1).minimumScaleFactor(0.8).textSelection(.enabled)
                            Spacer(minLength: 0)
                            CopyValueButton(value: serial, name: L("Numéro de série"))
                        }
                    } else { Text(L("SN indisponible")).font(.system(size: 10)) }
                }
                Text(L("USB · local · open source")).font(.system(size: 10)).foregroundStyle(Palette.secondary.opacity(0.65))
            }.foregroundStyle(Palette.secondary).padding(.horizontal, 27).padding(.bottom, 31)
            Button { model.showSettings = true } label: {
                HStack(spacing: 13) {
                    GlassIcon(systemName: "slider.horizontal.3", size: 25, color: Palette.violet)
                        .compositingGroup()
                        .saturation(settingsHovered ? 1 : 0)
                        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: settingsHovered)
                    Text(L("Configuration")).font(.system(size: 12))
                    Spacer(minLength: 0)
                }.foregroundStyle(Palette.secondary)
                    .padding(.horizontal, 12).padding(.vertical, 13)
                    .contentShape(RoundedRectangle(cornerRadius: 14))
            }.buttonStyle(.plain)
                .onHover { settingsHovered = $0 }
                .padding(3)
                .padding(.horizontal, 14).padding(.bottom, 12)
            HStack {
                Text("iTelier \(model.appVersion)").font(.system(size: 10))
                Spacer()
                Image(systemName: "lock").font(.system(size: 10))
            }.foregroundStyle(Palette.secondary.opacity(0.45)).padding(.horizontal, 27).padding(.bottom, 24)
        }.frame(width: 226)
            .background(Color.white.opacity(0.018))
            .overlay(alignment: .trailing) { Rectangle().fill(Palette.line.opacity(0.4)).frame(width: 1) }
    }
    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 10) {
                Text(model.page.title).font(.system(size: 41, weight: .light)).tracking(-1.2)
                Text(model.page.subtitle).font(.system(size: 12)).foregroundStyle(Palette.secondary)
            }
            Spacer()
            if !model.devices.isEmpty {
                Button { showDeviceSelector.toggle() } label: {
                    HStack(spacing: 8) {
                        Image(systemName: model.device?.symbolName ?? "iphone")
                        Text(model.device?.name ?? L("Choisir l’appareil")).lineLimit(1)
                        Image(systemName: "chevron.down").font(.system(size: 8, weight: .medium))
                    }.font(.system(size: 11)).foregroundStyle(Palette.secondary)
                        .padding(.horizontal, 13).padding(.vertical, 10).contentShape(Rectangle())
                }.buttonStyle(.plain).disabled(model.isBackupBusy || model.isRefreshing)
            }
            Button { Task { await model.refresh() } } label: {
                if model.isRefreshing { ProgressView().controlSize(.small).frame(width: 18, height: 18) }
                else { Image(systemName: "arrow.clockwise").frame(width: 18, height: 18) }
            }.buttonStyle(.plain).foregroundStyle(Palette.secondary)
                .help(L("Actualiser les appareils (⌘R)")).accessibilityLabel(L("Actualiser les appareils"))
                .disabled(!model.canRefreshDevices)
        }.padding(.horizontal, 30).padding(.top, 48).padding(.bottom, 23)
    }
    private var footer: some View {
        HStack(spacing: 6) {
            Image(systemName: "lock").font(.system(size: 9))
            Text(L("Vos rapports restent sur votre Mac."))
            Spacer()
            Button(model.isDemo ? L("Aperçu actif") : L("Explorer l’interface")) { model.toggleDemo() }
                .buttonStyle(.plain).foregroundStyle(Palette.secondary).disabled(model.busy)
        }.font(.system(size: 10)).foregroundStyle(Palette.secondary.opacity(0.55))
            .padding(.horizontal, 30).padding(.vertical, 14)
    }
}

struct OverviewView: View {
    @EnvironmentObject private var model: AppModel
    @ViewState private var selectedHelp: OverviewHelpTopic?
    var body: some View {
        VStack(alignment: .leading, spacing: 23) {
            GeometryReader { geometry in
                HStack(spacing: 18) {
                    deviceCard.frame(width: geometry.size.width * 0.38)
                    actionCard(title: L("Restaurer"), symbol: "arrow.triangle.2.circlepath", color: Palette.violet,
                               description: L("Choisissez la version du système à installer, ou utilisez un fichier déjà téléchargé."),
                               button: L("Choisir une version"), primary: true, helpTopic: .restore) { model.openFirmwareBrowser() }
                    actionCard(title: L("Vérifier"), symbol: "checkmark.shield.fill", color: Palette.accent,
                               description: L("Faites le point sur son identité, sa batterie et les données accessibles."),
                               button: model.currentReport == nil ? L("Lancer un Check") : L("Voir mon rapport"), primary: false, helpTopic: .check) {
                        if model.currentReport != nil { model.page = .check }
                        else { Task { await model.runCheck() } }
                    }
                }.frame(height: 340)
            }.frame(height: 340)
            HStack {
                Text(L("Votre appareil en détail")).font(.system(size: 12)).foregroundStyle(Palette.secondary)
                Spacer()
                Button(L("Tout afficher")) { model.informationDevice = model.device }.buttonStyle(.plain)
                    .font(.system(size: 12, weight: .medium)).disabled(model.device == nil)
            }.padding(.top, 3)
            HStack(alignment: .top, spacing: 18) {
                Surface(padding: 21) {
                    VStack(alignment: .leading, spacing: 19) {
                        HStack(spacing: 14) {
                            GlassIcon(systemName: "iphone.gen3", size: 38, color: Palette.violet)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(model.device?.name ?? L("Votre appareil Apple")).font(.system(size: 17, weight: .medium))
                                Text(model.device?.mode.title ?? L("Connectez votre appareil en USB.")).font(.system(size: 11)).foregroundStyle(Palette.secondary)
                            }
                            Spacer()
                        }
                        Divider().overlay(Palette.line)
                        HStack(spacing: 26) {
                            detail(L("Modèle"), model.device?.productType ?? "—")
                            detail(L("Système"), model.device?.osVersion ?? "—")
                            detail(L("Numéro de série"), model.visible(model.device?.serialNumber, sensitive: true))
                        }
                        if model.device == nil {
                            Button { Task { await model.refresh() } } label: { Label(L("Rechercher mon appareil"), systemImage: "cable.connector") }
                                .buttonStyle(QuietButtonStyle()).disabled(!model.canRefreshDevices)
                        }
                    }
                }.frame(maxWidth: .infinity)
                Surface(padding: 21) {
                    HStack(alignment: .center, spacing: 18) {
                        GlassIcon(systemName: model.currentReport?.attention ?? 0 > 0 ? "battery.25percent" : "doc.text.magnifyingglass", size: 47, color: model.currentReport?.attention ?? 0 > 0 ? Palette.yellow : Palette.accent)
                        VStack(alignment: .leading, spacing: 9) {
                            Text(model.currentReport?.summary ?? L("Un diagnostic qui explique.")).font(.system(size: 18, weight: .light))
                            Text(model.currentReport.map { L("\($0.available) données disponibles · \($0.manual + $0.unavailable) contrôles non automatisés.") } ?? L("Les données absentes restent indiquées. Chaque contrôle précise ses limites."))
                                .font(.system(size: 12)).foregroundStyle(Palette.secondary).lineSpacing(4)
                            Button(L("Consulter les contrôles")) { model.page = .check }.buttonStyle(.plain)
                                .font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.accent)
                        }
                    }.padding(.vertical, 8)
                }.frame(maxWidth: .infinity)
            }
        }
        .sheet(item: $selectedHelp) { topic in OverviewHelpView(topic: topic) }
    }
    private var deviceCard: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 20)
                .fill(LinearGradient(colors: [Palette.accent.opacity(0.16), Palette.surfaceTop, Palette.surfaceBottom], startPoint: .topTrailing, endPoint: .bottomLeading))
            ZStack {
                ConnectedDeviceArtwork(device: model.device).frame(width: 260, height: 260).scaleEffect(0.86)
            }.frame(width: 260, height: 268).offset(x: 110, y: -7)
            VStack(alignment: .leading, spacing: 9) {
                Text(model.isDemo ? L("Appareil d’exemple") : L("Votre appareil")).font(.system(size: 12)).foregroundStyle(Palette.secondary)
                Text(model.device == nil ? L("À connecter") : L("Connecté")).font(.system(size: 25, weight: .light)).foregroundStyle(Palette.accent)
                Text(model.device?.mode.title ?? L("En USB sur votre Mac")).font(.system(size: 11)).foregroundStyle(Palette.secondary)
                Spacer(minLength: 120)
                VStack(alignment: .leading, spacing: 9) {
                    Text(SystemDeviceArtwork.match(model.device)?.modelName ?? model.device?.productType ?? L("Votre appareil Apple"))
                        .font(.system(size: 16, weight: .medium)).lineLimit(1)
                    HStack {
                        Text(model.device?.name ?? L("Prêt dès la connexion")).lineLimit(1)
                        Spacer(minLength: 0)
                        Text(model.device?.osVersion.map { "\(model.device?.family.systemName ?? "iOS") \($0)" } ?? "")
                    }.font(.system(size: 10)).foregroundStyle(Palette.secondary)
                    Capsule().fill(Color.black.opacity(0.18)).frame(height: 5)
                        .overlay(alignment: .leading) { Capsule().fill(Palette.accent).frame(width: model.device == nil ? 0 : 36, height: 5) }
                }
            }.padding(22)
        }.clipShape(RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Palette.line, lineWidth: 1))
    }
    private func actionCard(title: String, symbol: String, color: Color, description: String, button: String, primary: Bool, helpTopic: OverviewHelpTopic, action: @escaping () -> Void) -> some View {
        Surface(padding: 22) {
            VStack(spacing: 12) {
                HStack {
                    Spacer()
                    Button { selectedHelp = helpTopic } label: {
                        Image(systemName: "info.circle.fill").font(.system(size: 13))
                            .frame(width: 28, height: 28).contentShape(Circle())
                    }.buttonStyle(.plain).foregroundStyle(Palette.secondary)
                        .accessibilityLabel(helpTopic.accessibilityLabel).help(helpTopic.accessibilityLabel)
                }
                GlassIcon(systemName: symbol, size: 74, color: color)
                    .frame(width: 106, height: 85).padding(.top, 3)
                Text(title).font(.system(size: 21, weight: .light))
                Text(description).multilineTextAlignment(.center).font(.system(size: 13)).foregroundStyle(Palette.secondary).lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                Button(action: action) {
                    HStack { Spacer(minLength: 0); Text(button).lineLimit(1); Spacer(minLength: 0) }
                }.buttonStyle(PrimaryButtonStyle()).disabled(!primary && (model.device == nil || model.busy))
            }.frame(height: 296)
        }.frame(maxWidth: .infinity)
    }
    private func detail(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(label).font(.system(size: 10)).foregroundStyle(Palette.secondary)
            Text(value).font(.system(size: 11, weight: .medium)).lineLimit(1)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private enum OverviewHelpTopic: String, Identifiable {
    case restore, check
    var id: String { rawValue }
    var title: String { self == .restore ? L("Restaurer") : L("Vérifier") }
    var symbol: String { self == .restore ? "arrow.triangle.2.circlepath" : "checkmark.shield.fill" }
    var color: Color { self == .restore ? Palette.violet : Palette.accent }
    var accessibilityLabel: String {
        self == .restore ? L("Informations sur la restauration") : L("Informations sur la vérification")
    }
    var message: String {
        self == .restore
            ? L("Choisissez une version du système dans le catalogue ou un fichier déjà téléchargé. L’app vous guide ensuite dans les options disponibles pour votre appareil.")
            : L("Retrouvez les informations de votre appareil, l’état de sa batterie et les contrôles disponibles. Vous pouvez garder un rapport pour comparer vos prochains relevés.")
    }
    var detail: String {
        self == .restore
            ? L("Avant de réinstaller le système, gardez une sauvegarde récente. L’option de conservation des données ne garantit pas leur récupération si l’installation échoue.")
            : L("Une information manquante reste indiquée. Le Check ne modifie pas votre appareil et ne certifie pas l’origine de ses pièces.")
    }
}

private struct OverviewHelpView: View {
    let topic: OverviewHelpTopic
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 14) {
                GlassIcon(systemName: topic.symbol, size: 42, color: topic.color).accessibilityHidden(true)
                Text(topic.title).font(.system(size: 23, weight: .light))
                Spacer()
                Button { dismiss() } label: { CloseGlyph() }
                    .buttonStyle(.plain).accessibilityLabel(L("Fermer l’aide")).keyboardShortcut(.cancelAction)
            }
            Text(topic.message).fixedSize(horizontal: false, vertical: true)
            Text(topic.detail).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button(L("Compris")) { dismiss() }.buttonStyle(QuietButtonStyle())
            }
        }.font(.system(size: 13)).lineSpacing(4).padding(26).frame(width: 480)
            .foregroundStyle(Palette.ink).background(Palette.canvas)
    }
}
