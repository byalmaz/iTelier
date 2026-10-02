import SwiftUI
import iTelierCore

struct DeviceInformationView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let target: DeviceSnapshot
    @ViewState private var showAll = false
    @ViewState private var resourceSheet: ResourceSheet?
    private enum ResourceSheet: String, Identifiable { case battery, storage; var id: String { rawValue } }

    private var information: DeviceInformation? {
        guard let value = model.deviceInformation, value.device.id == target.id, value.device.ecid == target.ecid else { return nil }
        return value
    }
    private var device: DeviceSnapshot { information?.device ?? model.devices.first(where: { $0.id == target.id }) ?? target }
    private var connected: Bool { model.devices.contains { $0.id == target.id && $0.ecid == target.ecid } }
    private var selected: Bool { model.device?.id == target.id }
    private var modelName: String { SystemDeviceArtwork.match(device)?.modelName ?? device.productType }
    private func value(_ keys: String...) -> String? {
        for key in keys {
            if let value = device.values[key]?.trimmingCharacters(in: .whitespacesAndNewlines), !value.isEmpty { return value }
        }
        return nil
    }

    var body: some View {
        VStack(spacing: 20) {
            HStack {
                Text(L("Informations de l’appareil")).font(.system(size: 27, weight: .light)).tracking(-0.5)
                Spacer()
                Button { dismiss() } label: { CloseGlyph() }.buttonStyle(.plain)
                    .accessibilityLabel(L("Fermer la fiche de l’appareil")).keyboardShortcut(.cancelAction)
            }
            ScrollView {
                HStack(alignment: .top, spacing: 22) {
                    sidebar.frame(width: 195)
                    VStack(alignment: .leading, spacing: 18) {
                        identity
                        HStack(alignment: .top, spacing: 16) {
                            storage.frame(maxWidth: .infinity)
                            battery.frame(width: 220)
                        }
                        if !connected {
                            Label(L("Appareil déconnecté · dernières informations disponibles"), systemImage: "cable.connector.slash")
                                .font(.system(size: 11)).foregroundStyle(Palette.amber)
                        }
                        if let error = model.deviceInformationError {
                            Text(error).font(.system(size: 11)).foregroundStyle(Palette.amber).fixedSize(horizontal: false, vertical: true)
                        }
                        ForEach(information?.warnings ?? [], id: \.self) { warning in
                            Text(warning).font(.system(size: 11)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    }.frame(maxWidth: .infinity)
                }.padding(.bottom, 5)
            }
            HStack(spacing: 10) {
                if model.isReadingDeviceInformation {
                    ProgressView().controlSize(.small)
                    Text(L("Lecture des informations de l’appareil")).font(.system(size: 11))
                } else if let information {
                    Text(L("Dernière lecture : \(information.date.uiFormatted(date: .omitted, time: .standard))"))
                        .font(.system(size: 11)).foregroundStyle(Palette.secondary)
                } else {
                    Text(L("Informations disponibles à la connexion")).font(.system(size: 11)).foregroundStyle(Palette.secondary)
                }
                Spacer()
                Button(L("Actualiser")) { Task { await model.refreshDeviceInformation(target) } }
                    .buttonStyle(QuietButtonStyle()).disabled(model.busy || !connected || device.mode != .normal)
            }
        }.padding(26).frame(width: 940, height: 680).foregroundStyle(Palette.ink).background(Palette.canvas)
            .task(id: target.id) { await model.refreshDeviceInformation(target) }
            .sheet(item: $resourceSheet) { resource in
                switch resource {
                case .battery: BatteryDetailView(target: target).environmentObject(model)
                case .storage: StorageDetailView(target: target).environmentObject(model)
                }
            }
    }

    private var sidebar: some View {
        VStack(spacing: 16) {
            ConnectedDeviceArtwork(device: device).frame(width: 190, height: 245)
            Text(device.name).font(.system(size: 20, weight: .medium)).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Text(modelName).font(.system(size: 12)).foregroundStyle(Palette.secondary).multilineTextAlignment(.center)
            Text("\(device.family.systemName) \(device.osVersion ?? "—")").font(.system(size: 12)).foregroundStyle(Palette.secondary)
            Label(connected ? device.mode.title : L("Déconnecté"), systemImage: connected ? "cable.connector" : "cable.connector.slash")
                .font(.system(size: 11)).foregroundStyle(connected ? Palette.accent : Palette.secondary)
            Rectangle().fill(Palette.line).frame(height: 1).padding(.vertical, 4)
            Eyebrow(text: L("Actions rapides"))
            action(L("Vérifier l’appareil"), symbol: "checkmark.shield", page: .check)
            action(L("Sauvegardes"), symbol: "externaldrive.badge.timemachine", page: .backups)
            action(L("Restaurer"), symbol: "arrow.triangle.2.circlepath", page: .restore)
            action(L("Activité"), symbol: "clock.arrow.circlepath", page: .activity)
        }
    }
    private func action(_ title: String, symbol: String, page: WorkspacePage) -> some View {
        Button {
            model.page = page
            dismiss()
        } label: {
            Label(title, systemImage: symbol).frame(maxWidth: .infinity, alignment: .leading)
        }.buttonStyle(QuietButtonStyle()).disabled(!selected)
    }
    private var identity: some View {
        Surface(padding: 20) {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Eyebrow(text: L("Identité de l’appareil"))
                    Spacer()
                    Button(showAll ? L("Réduire") : L("Tout afficher")) { showAll.toggle() }
                        .buttonStyle(.plain).font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.accent)
                }.padding(.bottom, 14)
                row(L("Nom"), device.name)
                row(L("Modèle"), modelName)
                row(L("Système"), device.osVersion.map { "\(device.family.systemName) \($0)" })
                row(L("Numéro de série"), device.serialNumber, copy: true)
                row("IMEI", value("InternationalMobileEquipmentIdentity"), copy: true)
                if let secondIMEI = value("InternationalMobileEquipmentIdentity2", "InternationalMobileEquipmentIdentity2.0") { row("IMEI 2", secondIMEI, copy: true) }
                row(L("Numéro de téléphone"), value("PhoneNumber"), copy: true)
                if let secondPhone = value("PhoneNumber2") { row(L("Numéro de téléphone 2"), secondPhone, copy: true) }
                row(L("Opérateur"), device.carrierDescription)
                row(L("Compte Apple (masqué)"), device.maskedAppleAccount)
                if showAll {
                    row(L("Identifiant du modèle"), device.productType)
                    row(L("Build du système"), device.buildVersion)
                    row(L("Carte matérielle"), device.hardwareModel)
                    row(L("Référence commerciale"), value("ModelNumber"))
                    row(L("Région commerciale"), value("RegionInfo"))
                    row("ECID", device.ecid, copy: true)
                    row("UDID", device.mode == .normal ? device.id : nil, copy: true)
                    row(L("État d’activation"), value("ActivationState"))
                }
                Text(L("Seules les informations communiquées par l’appareil sont affichées."))
                    .font(.system(size: 10)).foregroundStyle(Palette.secondary).padding(.top, 13)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
    private func row(_ title: String, _ value: String?, copy: Bool = false) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Text(title).font(.system(size: 12)).foregroundStyle(Palette.secondary).frame(width: 130, alignment: .leading)
            Spacer(minLength: 0)
            Text(value ?? L("Non exposé")).font(.system(size: 12, weight: value == nil ? .regular : .medium))
                .foregroundStyle(value == nil ? Palette.secondary : Palette.ink).multilineTextAlignment(.trailing)
                .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            if copy, let value { CopyValueButton(value: value, name: title) }
        }.padding(.vertical, 8)
            .overlay(alignment: .bottom) { Rectangle().fill(Palette.line.opacity(0.35)).frame(height: 0.5) }
    }
    private var storage: some View {
        Button { resourceSheet = .storage } label: {
            Surface(padding: 18) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Eyebrow(text: L("Stockage"))
                        Spacer()
                        Text(L("Détails")).font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.accent)
                    }
                    HStack(alignment: .firstTextBaseline, spacing: 5) {
                        Text(information?.storageUsed.map(localizedByteCount) ?? "—").font(.system(size: 23, weight: .light)).monospacedDigit()
                        Text(L("utilisés")).font(.system(size: 11)).foregroundStyle(Palette.secondary)
                    }
                    StorageBar(information: information)
                    HStack {
                        HStack(spacing: 5) {
                            Circle().fill(Palette.accent).frame(width: 6, height: 6)
                            Text(L("Espace utilisé"))
                        }
                        Spacer(minLength: 4)
                        Text(information?.storageFree.map { L("\(localizedByteCount($0)) disponibles") } ?? L("Non exposé"))
                    }.font(.system(size: 10)).foregroundStyle(Palette.secondary)
                }.frame(maxWidth: .infinity, minHeight: 120, maxHeight: 120, alignment: .topLeading)
            }.contentShape(RoundedRectangle(cornerRadius: 20))
        }.buttonStyle(.plain).accessibilityLabel(L("Afficher les détails du stockage"))
    }
    private var battery: some View {
        Button { resourceSheet = .battery } label: {
            Surface(padding: 18) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Eyebrow(text: L("Batterie"))
                        Spacer()
                        Text(L("Détails")).font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.accent)
                    }
                    HStack(spacing: 14) {
                        Text(information?.batteryPercent.map { "\($0) %" } ?? "—")
                            .font(.system(size: 27, weight: .light)).monospacedDigit()
                        Spacer(minLength: 0)
                        BatteryGauge(percent: information?.batteryPercent, charging: information?.isCharging == true)
                            .frame(width: 65, height: 28)
                    }.frame(height: 36)
                    Spacer(minLength: 0)
                    Text(information?.isCharging == true ? L("Batterie en charge") : information?.isCharging == false ? L("Niveau de charge") : L("Non exposé"))
                        .font(.system(size: 11)).foregroundStyle(Palette.secondary)
                }.frame(maxWidth: .infinity, minHeight: 120, maxHeight: 120, alignment: .topLeading)
            }.contentShape(RoundedRectangle(cornerRadius: 20))
        }.buttonStyle(.plain).accessibilityLabel(L("Afficher les détails de la batterie"))
    }
}
