import SwiftUI
import iTelierCore

struct FirmwareBrowserView: View {
    @EnvironmentObject private var model: AppModel
    @ViewState private var search = ""
    @ViewState private var showVisionGuide = false
    @ViewState private var family = "iPhone"
    @ViewState private var signedOnly = false
    @ViewState private var channel: ReleaseChannel = .all
    @ViewState private var selectedReleaseID: String?

    private enum ReleaseChannel: Hashable { case all, publicRelease, beta }

    private var selectedDevice: FirmwareDevice? {
        model.catalogDevices.first { $0.identifier == model.catalogDeviceIdentifier }
    }

    private var filteredDevices: [FirmwareDevice] {
        let query = search.trimmingCharacters(in: .whitespacesAndNewlines)
        return model.catalogDevices.filter { device in
            device.identifier.hasPrefix(family)
                && (query.isEmpty || device.name.localizedCaseInsensitiveContains(query)
                    || device.identifier.localizedCaseInsensitiveContains(query))
        }
    }

    private var visibleReleases: [FirmwareRelease] {
        model.catalogReleases.filter {
            (!signedOnly || $0.signed) && (channel == .all || (channel == .beta ? $0.isBeta : !$0.isBeta))
        }.sorted(by: FirmwareCatalog.newestFirst)
    }

    private var selectedRelease: FirmwareRelease? {
        visibleReleases.first {
            $0.id == selectedReleaseID && $0.identifier == model.catalogDeviceIdentifier
                && $0.identifier.hasPrefix(family)
        }
    }

    private var canDownload: Bool {
        selectedRelease != nil && !model.busy
            && !model.isLoadingCatalog && !model.isDownloadingFirmware
    }

    private var selectedIsVisionPro: Bool {
        selectedRelease.map { DeviceFamily(identifier: $0.identifier) == .visionPro } ?? false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            header
            HStack(alignment: .top, spacing: 20) {
                Surface(padding: 14) { devicePane }
                    .frame(width: 220)
                releasePane
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }.frame(maxHeight: .infinity)
            Rectangle().fill(Palette.line).frame(height: 1)
            footer
        }
        .padding(24)
        .frame(width: 860, height: 600)
        .foregroundStyle(Palette.ink)
        .background(Palette.canvas)
        
        .sheet(isPresented: $showVisionGuide) { VisionProGuideView() }
        .tint(Palette.accent)
        .onAppear { syncFamily(model.catalogDeviceIdentifier); selectFirstVisibleRelease() }
        .onChange(of: model.catalogDeviceIdentifier) { identifier in
            selectedReleaseID = nil
            syncFamily(identifier)
        }
        .onChange(of: family) { family in
            guard let identifier = model.catalogDeviceIdentifier, !identifier.hasPrefix(family) else { return }
            selectedReleaseID = nil
            model.clearCatalogSelection()
        }
        .onChange(of: visibleReleases.map(\.id)) { _ in selectFirstVisibleRelease() }
    }

    private var header: some View {
        HStack(spacing: 15) {
            GlassIcon(systemName: "arrow.down.doc.fill", size: 44, color: Palette.accent)
            VStack(alignment: .leading, spacing: 5) {
                Text(L("Choisir une version")).font(.system(size: 28, weight: .light))
                Text(L("Les fichiers IPSW sont téléchargés depuis les serveurs Apple."))
                    .font(.system(size: 12)).foregroundStyle(Palette.secondary)
            }
            Spacer()
            Button { refresh() } label: { Image(systemName: "arrow.clockwise") }
                .buttonStyle(QuietButtonStyle())
                .accessibilityLabel(L("Actualiser le catalogue"))
                .help(L("Actualiser les versions et leur état de signature"))
                .disabled(model.isLoadingCatalog || model.busy || model.isDownloadingFirmware)
            Button { model.showFirmwareBrowser = false } label: {
                CloseGlyph()
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L("Fermer le catalogue"))
            .keyboardShortcut(.cancelAction)
        }
    }

    private var devicePane: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(L("MODÈLE")).font(.system(size: 10, weight: .medium)).tracking(1.4)
                .foregroundStyle(Palette.secondary)
            Picker(L("Famille d’appareils"), selection: $family) {
                Text("iPhone").tag("iPhone")
                Text("iPad").tag("iPad")
                Text("Vision Pro").tag("RealityDevice")
            }.pickerStyle(.segmented).labelsHidden()
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").foregroundStyle(Palette.secondary)
                TextField(L("Modèle ou identifiant"), text: $search).textFieldStyle(.plain)
                    .accessibilityLabel(L("Rechercher un modèle"))
            }.font(.system(size: 11)).padding(10)
                .background(Palette.deep.opacity(0.30), in: RoundedRectangle(cornerRadius: 9))
                .overlay(RoundedRectangle(cornerRadius: 9).stroke(Palette.line))
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 5) {
                    if model.catalogDevices.isEmpty && model.isLoadingCatalog {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text(L("Chargement des modèles…")).font(.system(size: 11)).foregroundStyle(Palette.secondary)
                        }.padding(.vertical, 16)
                    } else if filteredDevices.isEmpty {
                        Text(model.catalogDevices.isEmpty ? L("Le catalogue n’est pas disponible.") : L("Aucun modèle ne correspond à votre recherche."))
                            .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                            .padding(.vertical, 16)
                    } else {
                        ForEach(filteredDevices) { device in deviceRow(device) }
                    }
                }
            }.frame(maxHeight: .infinity)
        }.frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private func deviceRow(_ device: FirmwareDevice) -> some View {
        let selected = device.identifier == model.catalogDeviceIdentifier
        return Button {
            selectedReleaseID = nil
            Task { await model.selectCatalogDevice(device.identifier) }
        } label: {
            HStack(spacing: 7) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(device.name).font(.system(size: 12, weight: .medium))
                        .foregroundStyle(selected ? Palette.ink : Palette.secondary)
                        .multilineTextAlignment(.leading)
                    Text(device.identifier).font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(Palette.secondary)
                }
                Spacer(minLength: 0)
                if selected {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .semibold)).foregroundStyle(Palette.accent)
                }
            }
            .padding(.horizontal, 10).padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Palette.accent.opacity(0.12) : Color.clear, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(selected ? Palette.accent.opacity(0.30) : Color.clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.busy || model.isDownloadingFirmware)
        .accessibilityLabel("\(device.name), \(device.identifier)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var releasePane: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selectedDevice?.name ?? model.catalogDeviceIdentifier ?? L("Choisissez un modèle"))
                        .font(.system(size: 22, weight: .light)).lineLimit(1)
                    if let updated = model.catalogUpdatedAt {
                        Text(L("IPSW.me + AppleDB · actualisé \(updated.uiFormatted(date: .abbreviated, time: .shortened))"))
                            .font(.system(size: 10)).foregroundStyle(Palette.secondary)
                    }
                }
                Spacer(minLength: 8)
                if model.isLoadingCatalog { ProgressView().controlSize(.small).padding(.top, 5) }
            }
            HStack(spacing: 14) {
                Picker("Versions", selection: $channel) {
                    Text(L("Toutes")).tag(ReleaseChannel.all)
                    Text(L("Publiques")).tag(ReleaseChannel.publicRelease)
                    Text(L("Bêtas")).tag(ReleaseChannel.beta)
                }.pickerStyle(.segmented).labelsHidden()
                Toggle(L("Signées uniquement"), isOn: $signedOnly)
                    .toggleStyle(.checkbox).font(.system(size: 11)).fixedSize()
            }
            ForEach(model.catalogWarnings, id: \.self) { warning in
                notice(warning, symbol: "exclamationmark.triangle", color: Palette.amber)
            }
            if let connected = model.device, let identifier = model.catalogDeviceIdentifier,
               identifier != connected.productType {
                notice(L("Le modèle choisi diffère de l’appareil connecté. Connectez l’appareil correspondant avant de restaurer ce fichier."), symbol: "info.circle", color: Palette.secondary)
            }
            if family == "RealityDevice" {
                Button(L("Guide de restauration Vision Pro")) { showVisionGuide = true }.buttonStyle(QuietButtonStyle())
            }
            if let error = model.catalogError {
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "wifi.exclamationmark").foregroundStyle(Palette.amber)
                    Text(error).font(.system(size: 12)).foregroundStyle(Palette.secondary).lineLimit(4)
                    Spacer(minLength: 4)
                    Button(L("Réessayer")) { refresh() }.buttonStyle(.plain).foregroundStyle(Palette.accent)
                        .font(.system(size: 12, weight: .medium)).disabled(model.isLoadingCatalog)
                }.padding(12).background(Palette.card, in: RoundedRectangle(cornerRadius: 12))
            }
            if model.catalogDeviceIdentifier == nil {
                if model.isLoadingCatalog {
                    emptyState(L("Chargement du catalogue…"), detail: L("Recherche des modèles iPhone, iPad et Vision Pro disponibles."), symbol: "network")
                } else if model.catalogError != nil {
                    emptyState(L("Catalogue indisponible"), detail: L("Vérifiez votre connexion Internet, puis réessayez."), symbol: "wifi.exclamationmark")
                } else {
                    emptyState(L("Choisissez votre appareil Apple."), detail: model.device == nil
                        ? L("Vous pouvez télécharger un firmware avant de connecter votre appareil.")
                        : L("Sélectionnez le modèle correspondant dans la liste."), symbol: "iphone.and.ipad")
                }
            } else if visibleReleases.isEmpty {
                if model.isLoadingCatalog {
                    emptyState(L("Chargement des versions…"), detail: L("Recherche des firmwares disponibles pour ce modèle."), symbol: "network")
                } else if model.catalogError != nil {
                    emptyState(L("Catalogue indisponible"), detail: L("Vérifiez votre connexion Internet, puis réessayez."), symbol: "wifi.exclamationmark")
                } else {
                    emptyState(L("Aucune version pour ces filtres"),
                               detail: L("Choisissez Toutes ou désactivez le filtre Signées uniquement. Certains anciens fichiers ne sont plus disponibles chez Apple."), symbol: "doc.text.magnifyingglass")
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 8) {
                        ForEach(visibleReleases) { release in releaseRow(release) }
                    }.padding(1)
                }.frame(maxHeight: .infinity)
            }
        }.frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private func releaseRow(_ release: FirmwareRelease) -> some View {
        let selected = release.id == selectedReleaseID
        return Button { selectedReleaseID = release.id } label: {
            HStack(spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 19)).foregroundStyle(selected ? Palette.accent : Palette.secondary.opacity(0.65))
                VStack(alignment: .leading, spacing: 5) {
                    Text("\(DeviceFamily(identifier: release.identifier).systemName) \(release.displayVersion)")
                        .font(.system(size: 18, weight: .light)).foregroundStyle(Palette.ink)
                    Text("\(release.isBeta ? "Bêta · " : "")Build \(release.buildID) · \(release.releaseDate.map { $0.uiFormatted(date: .abbreviated, time: .omitted) } ?? "Date non publiée")")
                        .font(.system(size: 11)).foregroundStyle(Palette.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 6) {
                    signatureBadge(release.signed)
                    Text(sizeLabel(release)).font(.system(size: 11)).foregroundStyle(Palette.secondary)
                }
            }
            .padding(13).frame(maxWidth: .infinity, alignment: .leading)
            .background(selected ? Palette.accent.opacity(0.09) : Palette.card.opacity(0.55), in: RoundedRectangle(cornerRadius: 13))
            .overlay(RoundedRectangle(cornerRadius: 13).stroke(selected ? Palette.accent.opacity(0.50) : Palette.line.opacity(0.7)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.isLoadingCatalog || model.busy || model.isDownloadingFirmware)
        .accessibilityLabel("\(DeviceFamily(identifier: release.identifier).systemName) \(release.displayVersion), build \(release.buildID), \(release.signed ? L("signée") : L("non signée")), \(sizeLabel(release))")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var footer: some View {
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                if let release = selectedRelease, !release.signed {
                    Label(L("Version non signée : téléchargement possible, restauration standard impossible."), systemImage: "exclamationmark.triangle")
                        .font(.system(size: 12)).foregroundStyle(Palette.amber).fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(selectedRelease.map { "\($0.displayVersion) · build \($0.buildID) · \(sizeLabel($0))" } ?? L("Sélectionnez une version à télécharger."))
                        .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                }
                Text(L("Téléchargement direct dans \(model.downloadFolderLabel)."))
                    .font(.system(size: 11)).foregroundStyle(Palette.secondary)
                Text(L("L’IPSW déjà présent est vérifié et réutilisé. Sinon, il est téléchargé avant confirmation."))
                    .font(.system(size: 11)).foregroundStyle(Palette.secondary)
            }.frame(maxWidth: .infinity, alignment: .leading)
            Button {
                if let release = selectedRelease { model.startFirmwareDownload(release) }
            } label: { Label(L("Télécharger"), systemImage: "arrow.down") }
                .buttonStyle(QuietButtonStyle()).disabled(!canDownload)
            Button {
                if selectedIsVisionPro { showVisionGuide = true }
                else if let release = selectedRelease { model.startFirmwareDownload(release, prepareRestore: true) }
            } label: { Label(selectedIsVisionPro ? L("Avec Apple Configurator") : L("Restaurer…"), systemImage: "arrow.triangle.2.circlepath") }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(selectedIsVisionPro ? model.busy : (!canDownload || selectedRelease.map { !model.canPrepareRestore($0) } != false))
                .help(L("Nécessite une version signée et l’appareil correspondant connecté. Une confirmation sera demandée avant toute écriture."))
        }
    }

    private func signatureBadge(_ signed: Bool) -> some View {
        let color = signed ? Palette.mint : Palette.amber
        return Label(signed ? L("Signée") : L("Non signée"), systemImage: signed ? "checkmark.seal" : "exclamationmark.circle")
            .font(.system(size: 10, weight: .medium)).foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(Palette.deep.opacity(0.35), in: Capsule())
            .overlay(Capsule().stroke(color.opacity(0.25)))
            .help(L("État indiqué par le catalogue. Apple vérifie la signature lors d’une restauration."))
    }

    private func notice(_ text: String, symbol: String, color: Color) -> some View {
        Label(text, systemImage: symbol).font(.system(size: 11)).foregroundStyle(color)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func emptyState(_ title: String, detail: String, symbol: String) -> some View {
        VStack(spacing: 14) {
            GlassIcon(systemName: symbol, size: 60, color: Palette.violet)
            Text(title).font(.system(size: 21, weight: .light)).multilineTextAlignment(.center)
            Text(detail).font(.system(size: 12)).foregroundStyle(Palette.secondary)
                .multilineTextAlignment(.center).lineSpacing(4)
        }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Palette.card.opacity(0.55), in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Palette.line))
    }

    private func sizeLabel(_ release: FirmwareRelease) -> String {
        release.fileSize > 0
            ? localizedByteCount( release.fileSize)
            : L("Taille non publiée")
    }

    private func syncFamily(_ identifier: String?) {
        if identifier?.hasPrefix("RealityDevice") == true { family = "RealityDevice" }
        else if identifier?.hasPrefix("iPad") == true { family = "iPad" }
        else if identifier?.hasPrefix("iPhone") == true { family = "iPhone" }
    }

    private func selectFirstVisibleRelease() {
        if !visibleReleases.contains(where: { $0.id == selectedReleaseID }) {
            selectedReleaseID = visibleReleases.first?.id
        }
    }

    private func refresh() {
        Task {
            if model.catalogDevices.isEmpty { await model.loadCatalogDevices() }
            else { await model.refreshCatalog() }
        }
    }
}
