import SwiftUI
import AppKit
import UniformTypeIdentifiers
import iTelierCore

func storageColor(_ id: String) -> Color {
    switch id {
    case "free": return Palette.line.opacity(0.7)
    case "PhotoUsage", "CameraUsage": return Palette.mint
    case "MobileApplicationUsage": return Palette.violet
    case "ApplicationDocumentsUsage": return Palette.accent
    case "system": return Palette.secondary
    case "CalendarUsage", "NotesUsage": return Palette.amber
    case "VoicemailUsage": return Palette.red
    default: return Palette.accent
    }
}

struct StorageBar: View {
    let information: DeviceInformation?
    var body: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                ForEach(information?.storageSegments ?? []) { segment in
                    Rectangle().fill(storageColor(segment.id))
                        .frame(width: geometry.size.width * Double(segment.bytes) / Double(information?.storageTotal ?? 1))
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.line.opacity(0.4)).clipShape(RoundedRectangle(cornerRadius: 6))
        }.frame(height: 16).accessibilityHidden(true)
    }
}

struct StorageDetailView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let target: DeviceSnapshot
    @ViewState private var section = 0
    private var hardware: StorageHardware { information?.storageHardware ?? StorageHardware() }
    private var information: DeviceInformation? {
        guard let info = model.deviceInformation, info.device.id == target.id, info.device.ecid == target.ecid else { return nil }
        return info
    }
    private var segments: [StorageSegment] { information?.storageSegments ?? [] }
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text(L("Stockage")).font(.system(size: 27, weight: .light))
                Spacer()
                Button { dismiss() } label: { CloseGlyph() }.buttonStyle(.plain).keyboardShortcut(.cancelAction).accessibilityLabel(L("Fermer"))
            }
            HStack(alignment: .firstTextBaseline) {
                Text(information?.storageFree.map { L("\(localizedByteCount($0)) disponibles") } ?? L("Non exposé"))
                    .font(.system(size: 28, weight: .light))
                Spacer()
                if let used = information?.storageUsed, let total = information?.storageTotal {
                    Text(L("\(localizedByteCount(used)) utilisés sur \(localizedByteCount(total))")).font(.system(size: 13)).foregroundStyle(Palette.secondary)
                }
            }
            Picker(L("Section"), selection: $section) {
                Text(L("Répartition")).tag(0)
                Text(L("Mémoire flash")).tag(1)
                Text(L("Caractéristiques techniques")).tag(2)
            }.pickerStyle(.segmented)
            ScrollView {
            if section == 0 {
            Surface(padding: 16) {
                Label(L("Répartition communiquée par l’appareil. Les catégories absentes restent regroupées dans l’espace utilisé."), systemImage: "info.circle")
                    .font(.system(size: 12)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 38) {
                ZStack {
                    Circle().stroke(Palette.line.opacity(0.4), lineWidth: 38)
                    ForEach(segments.indices, id: \.self) { index in
                        let start = segments.prefix(index).reduce(0.0) { $0 + Double($1.bytes) } / Double(information?.storageTotal ?? 1)
                        let end = start + Double(segments[index].bytes) / Double(information?.storageTotal ?? 1)
                        Circle().trim(from: start, to: end).stroke(storageColor(segments[index].id), style: StrokeStyle(lineWidth: 38))
                            .rotationEffect(.degrees(-90))
                    }
                    VStack(spacing: 6) {
                        Text(information?.storageFree.map(localizedByteCount) ?? "—").font(.system(size: 23, weight: .medium))
                        Text(L("Disponible")).font(.system(size: 12)).foregroundStyle(Palette.secondary)
                    }
                }.frame(width: 235, height: 235).padding(20).accessibilityHidden(true)
                VStack(spacing: 12) {
                    ForEach(segments) { segment in
                        HStack {
                            Circle().fill(storageColor(segment.id)).frame(width: 8, height: 8)
                            Text(segment.title).foregroundStyle(Palette.secondary)
                            Spacer()
                            Text(localizedByteCount(segment.bytes)).fontWeight(.medium).monospacedDigit()
                        }.font(.system(size: 13))
                    }
                    Divider().overlay(Palette.line)
                    HStack {
                        Text(L("Espace purgeable")).foregroundStyle(Palette.secondary)
                        Spacer()
                        Text(L("Non exposé"))
                    }.font(.system(size: 12))
                    Text(L("L’espace purgeable ne peut pas être déduit de l’espace libre. Consultez les réglages de stockage sur l’appareil pour les catégories non communiquées."))
                        .font(.system(size: 10)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity)
            }.padding(.top, 20)
            } else if section == 1 {
                Surface(padding: 22) {
                    VStack(spacing: 14) {
                        hardwareRow(L("Fournisseur"), hardware.vendor)
                        hardwareRow(L("Type de stockage"), hardware.cellType)
                        hardwareRow(L("Modèle de stockage"), hardware.model)
                        hardwareRow(L("Modèle de puce"), hardware.text("Controller Characteristics.chip-id"))
                        hardwareRow(L("Version du micrologiciel"), hardware.firmware)
                        hardwareRow(L("Nom de la mémoire NAND"), hardware.flashName)
                        hardwareRow(L("Version MSP"), hardware.text("Controller Characteristics.msp-version"))
                        HStack {
                            Text(L("Numéro de série")).foregroundStyle(Palette.secondary)
                            Spacer()
                            Text(hardware.serial ?? L("Non exposé")).textSelection(.enabled)
                            if let serial = hardware.serial { CopyValueButton(value: serial, name: L("Numéro de série")) }
                        }.font(.system(size: 12))
                    }
                }
            } else {
                Surface(padding: 22) {
                    VStack(spacing: 14) {
                        hardwareRow(L("Interface"), hardware.text("Physical Interconnect"))
                        hardwareRow(L("Révision NVMe"), hardware.text("NVMe Revision Supported"))
                        hardwareRow(L("Lecture maximale par transfert"), bytes("IOMaximumByteCountRead"))
                        hardwareRow(L("Écriture maximale par transfert"), bytes("IOMaximumByteCountWrite"))
                        hardwareRow(L("Segment maximal en lecture"), bytes("IOMaximumSegmentByteCountRead"))
                        hardwareRow(L("Segment maximal en écriture"), bytes("IOMaximumSegmentByteCountWrite"))
                        hardwareRow(L("Nombre maximal de segments lus"), hardware.text("IOMaximumSegmentCountRead"))
                        hardwareRow(L("Nombre maximal de segments écrits"), hardware.text("IOMaximumSegmentCountWrite"))
                        hardwareRow(L("Alignement minimal"), bytes("IOMinimumSegmentAlignmentByteCount"))
                        hardwareRow(L("Seuil de saturation"), bytes("IOMinimumSaturationByteCount"))
                        hardwareRow(L("Taille d’entrée/sortie préférée"), bytes("Controller Characteristics.Preferred IO Size"))
                    }
                }
            }
            }.frame(maxWidth: .infinity, maxHeight: .infinity)
            HStack {
                Text(model.isDemo ? L("Appareil d’exemple") : target.name).font(.system(size: 11)).foregroundStyle(Palette.secondary)
                Spacer()
                if model.isReadingDeviceInformation {
                    ProgressView().controlSize(.small)
                    Text(L("Lecture des catégories et de la mémoire…")).font(.system(size: 11)).foregroundStyle(Palette.secondary)
                }
                Button(L("Actualiser")) { Task { await model.refreshDeviceInformation(target, storageDetails: true) } }
                    .buttonStyle(QuietButtonStyle()).disabled(model.busy || !model.devices.contains { $0.id == target.id } || target.mode != .normal)
            }
            if let error = model.deviceInformationError { Text(error).font(.system(size: 10)).foregroundStyle(Palette.amber) }
        }.padding(26).frame(width: 900, height: 680).foregroundStyle(Palette.ink).background(Palette.canvas)
            .task {
                while model.isReadingDeviceInformation && !Task.isCancelled { try? await Task.sleep(for: .milliseconds(100)) }
                guard !Task.isCancelled else { return }
                await model.refreshDeviceInformation(target, storageDetails: true)
            }
    }
    private func bytes(_ key: String) -> String? { hardware.number(key).map { L("\($0) octets") } }
    private func hardwareRow(_ title: String, _ value: String?) -> some View {
        HStack(spacing: 18) {
            Text(title).foregroundStyle(Palette.secondary)
            Spacer(minLength: 8)
            Text(value ?? L("Non exposé")).fontWeight(.medium).textSelection(.enabled).multilineTextAlignment(.trailing)
        }.font(.system(size: 12)).padding(.vertical, 3)
            .overlay(alignment: .bottom) { Rectangle().fill(Palette.line.opacity(0.4)).frame(height: 0.5).offset(y: 7) }
    }
}
