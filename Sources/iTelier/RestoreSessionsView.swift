import SwiftUI
import iTelierCore

struct RestoreSessionsView: View {
    @EnvironmentObject private var model: AppModel
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !model.devices.isEmpty {
                Surface(padding: 20) {
                    VStack(alignment: .leading, spacing: 13) {
                        Text(L("Choisissez l’appareil à restaurer")).font(.system(size: 18, weight: .medium))
                        Text(L("Vous pouvez lancer la restauration d’un autre appareil sans attendre la fin des opérations en cours."))
                            .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), alignment: .leading)], alignment: .leading, spacing: 10) {
                            ForEach(model.devices) { device in
                                let active = model.activeRestoreSessions.contains { $0.snapshot.target?.matches(device) == true }
                                Button { model.selectDevice(device.id) } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: device.symbolName).font(.system(size: 20))
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(device.name).fontWeight(.medium).lineLimit(1)
                                            Text("\(device.productType) · ••\((device.ecid ?? device.id).suffix(6))")
                                                .font(.system(size: 10)).foregroundStyle(Palette.secondary)
                                            if active { Text(L("Restauration en cours")).font(.system(size: 10)).foregroundStyle(Palette.accent) }
                                        }
                                        Spacer(minLength: 0)
                                        if device.id == model.selectedDeviceID { Image(systemName: "checkmark.circle.fill") }
                                    }.padding(13).frame(maxWidth: .infinity, alignment: .leading)
                                        .background(device.id == model.selectedDeviceID ? Palette.accent.opacity(0.10) : Palette.card.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
                                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(device.id == model.selectedDeviceID ? Palette.accent : Palette.line))
                                        .contentShape(Rectangle())
                                }.buttonStyle(.plain).disabled(model.isBackupBusy || model.isRefreshing)
                            }
                        }
                    }
                }
            }
            if !model.restoreSessions.isEmpty {
                HStack {
                    Text(L("Restaurations")).font(.system(size: 22, weight: .light))
                    Spacer()
                    Text(L("\(model.activeRestoreSessions.count) en cours")).foregroundStyle(Palette.secondary)
                }
                ForEach(model.restoreSessions) { session in
                    sessionCard(session)
                }
            }
        }
    }

    private func sessionCard(_ session: RestoreSession) -> some View {
        let target = session.snapshot.target
        let complete = session.snapshot.completion == .confirmed
        let color = session.isActive ? Palette.accent : complete ? Palette.mint : Palette.amber
        return Surface(padding: 24) {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 16) {
                    GlassIcon(systemName: session.isActive ? "arrow.triangle.2.circlepath" : complete ? "checkmark.circle.fill" : "exclamationmark.circle.fill", size: 54, color: color)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(target?.name ?? L("Appareil à vérifier")).font(.system(size: 21, weight: .medium))
                        if let target {
                            Text("\(target.productType) · \(DeviceFamily(identifier: target.productType).systemName) \(target.firmwareVersion) (\(target.firmwareBuild)) · ECID ••\(target.ecid.suffix(6))")
                                .font(.system(size: 11)).foregroundStyle(Palette.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                    if let mode = target?.mode {
                        Label(mode.title, systemImage: mode == .preserveData ? "lock.shield" : "trash")
                            .font(.system(size: 11)).foregroundStyle(mode == .preserveData ? Palette.accent : Palette.red)
                    }
                }
                Text(session.phase).font(.system(size: 16, weight: .medium)).foregroundStyle(color)
                if session.isActive {
                    if let fraction = session.snapshot.progress {
                        ProgressView(value: fraction).tint(color)
                        Text(L("Progression de la phase en cours : \(Int(fraction * 100)) %")).font(.system(size: 11)).foregroundStyle(Palette.secondary)
                    } else { ProgressView().progressViewStyle(.linear).tint(color) }
                    Text(L("Gardez cet appareil connecté jusqu’à la fin de l’installation et de son démarrage."))
                        .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                } else if complete {
                    Text(L("L’appareil peut encore terminer son démarrage. Gardez-le connecté jusqu’à l’écran d’accueil ou de configuration."))
                        .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                } else if session.needsReview {
                    HStack {
                        Text(L("Vérifiez cet appareil avant de réessayer. Les autres restaurations continuent."))
                            .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                        Spacer()
                        Button(L("Vérifier cet appareil")) {
                            Task {
                                if target != nil { await model.recheckRestore(session.id) }
                                else { await model.recheckAfterInterruption() }
                            }
                        }.buttonStyle(QuietButtonStyle()).disabled(model.isRefreshing || model.isBackupBusy || model.isDemo)
                    }
                } else {
                    Text(L("Appareil vérifié. Vous pouvez préparer un nouvel essai."))
                        .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                }
                DisclosureGroup(L("Journal de cet appareil")) {
                    ScrollView {
                        Text(model.sanitizedLog(session.snapshot.log.joined(separator: "\n")))
                            .font(.system(size: 10, design: .monospaced)).textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                    }.frame(height: 160).background(Palette.deep.opacity(0.4), in: RoundedRectangle(cornerRadius: 12)).padding(.top, 8)
                }.font(.system(size: 11)).foregroundStyle(Palette.secondary)
            }
        }
    }
}
