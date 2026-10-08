import SwiftUI
import AppKit
import UniformTypeIdentifiers
import iTelierCore

/// Batterie horizontale vectorielle : remplissage proportionnel à la charge, vert, orange
/// ou rouge selon le niveau, éclair pendant la charge. Lisible de 60 à 260 points de large.
struct BatteryGauge: View {
    let percent: Int?
    let charging: Bool
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    static let green = Color(red: 52 / 255, green: 199 / 255, blue: 89 / 255)
    static let orange = Color(red: 1, green: 159 / 255, blue: 10 / 255)
    static let red = Color(red: 1, green: 69 / 255, blue: 58 / 255)

    private var fraction: CGFloat { CGFloat(min(100, max(0, percent ?? 0))) / 100 }
    private var fill: Color {
        guard let percent else { return Palette.secondary }
        if charging || percent > 20 { return Self.green }
        return percent > 10 ? Self.orange : Self.red
    }

    var body: some View {
        GeometryReader { geometry in
            let height = geometry.size.height
            let nub = max(3, height * 0.09)
            let gap = max(1.5, height * 0.035)
            let width = geometry.size.width - nub - gap
            let border = max(1.5, height * 0.035)
            let inset = max(2.5, height * 0.08)
            let radius = height * 0.26
            HStack(spacing: gap) {
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: radius, style: .continuous).fill(Palette.secondary.opacity(0.13))
                    if percent != nil {
                        RoundedRectangle(cornerRadius: max(1, radius - inset), style: .continuous)
                            .fill(LinearGradient(colors: [fill.opacity(0.85), fill], startPoint: .top, endPoint: .bottom))
                            .overlay(RoundedRectangle(cornerRadius: max(1, radius - inset), style: .continuous)
                                .fill(LinearGradient(colors: [.white.opacity(0.32), .white.opacity(0)], startPoint: .top, endPoint: .center)))
                            .frame(width: max(height * 0.14, (width - 2 * inset) * fraction))
                            .padding(inset)
                            .animation(reduceMotion ? nil : .easeOut(duration: 0.6), value: fraction)
                    }
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .strokeBorder(Palette.secondary.opacity(0.5), lineWidth: border)
                    if charging {
                        Image(systemName: "bolt.fill")
                            .font(.system(size: height * 0.52, weight: .heavy))
                            .foregroundStyle(.white)
                            .shadow(color: .black.opacity(0.4), radius: max(0.5, height * 0.03))
                            .frame(maxWidth: .infinity)
                    }
                }.frame(width: width)
                RoundedRectangle(cornerRadius: nub / 2, style: .continuous)
                    .fill(Palette.secondary.opacity(0.5))
                    .frame(width: nub, height: height * 0.36)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        guard let percent else { return L("Niveau de charge non exposé") }
        return charging ? L("Niveau de charge \(percent) %, en charge") : L("Niveau de charge \(percent) %")
    }
}

/// Valeurs formatées de la fenêtre Batterie et de son export. Une lecture absente reste absente.
struct BatteryFigures {
    let information: DeviceInformation?
    var metrics: BatteryMetrics { information?.metrics ?? BatteryMetrics() }

    func measure(_ value: Double?, _ unit: String, digits: Int = 0) -> String? {
        value.map { $0.formatted(.number.locale(AppLocalization.locale).precision(.fractionLength(digits))) + " " + unit }
    }
    var percentText: String { information?.batteryPercent.map { "\($0) %" } ?? "—" }
    var health: Double? { metrics.declaredHealth ?? metrics.estimatedHealth }
    var healthTitle: String { metrics.declaredHealth != nil ? L("Capacité maximale déclarée") : L("Capacité maximale estimée") }
    // Apple recommande une intervention sous 80 % de la capacité d’origine.
    var healthColor: Color { (health ?? 100) >= 80 ? Palette.mint : Palette.amber }

    var state: (title: String, symbol: String) {
        switch information?.powerState {
        case .charging?: return (L("En charge"), "bolt.fill")
        case .full?: return (L("Chargée, sur secteur"), "powerplug.fill")
        case .pluggedNotCharging?: return (L("Sur secteur, sans recharge"), "powerplug")
        case .onBattery?: return (L("Sur batterie"), "battery.75percent")
        case nil: return (L("État de charge non exposé"), "questionmark.circle")
        }
    }
    /// Puissance sans signe dans le résumé : le sens est déjà donné par l’état.
    var stateLine: String {
        guard information?.powerState != nil, let watts = metrics.watts, let power = measure(abs(watts), "W", digits: 2) else { return state.title }
        return state.title + " · " + power
    }
    var capacitySummary: String? {
        guard let full = measure(metrics.fullCapacity, "mAh"), let design = measure(metrics.designCapacity, "mAh") else { return nil }
        return L("\(full) sur \(design) de conception")
    }
    var cyclesSummary: String? { metrics.cycles.map { L("\($0) cycles de charge") } }

    var capacityRows: [(String, String?)] {
        let ratio = measure(metrics.estimatedHealth, "%")
        return [(L("Charge actuelle mesurée"), measure(metrics.currentCapacity, "mAh")),
                (L("Capacité à pleine charge"), measure(metrics.fullCapacity, "mAh").map { full in ratio.map { "\(full) (\($0))" } ?? full }),
                (L("Capacité de conception"), measure(metrics.designCapacity, "mAh")),
                (L("Cycles de charge"), metrics.cycles.map(String.init))]
    }
    var powerRows: [(String, String?)] {
        [(L("État"), information?.powerState == nil ? nil : state.title),
         (L("Intensité instantanée"), measure(metrics.amperage, "mA")),
         (L("Tension"), measure(metrics.voltage, "mV")),
         (L("Puissance calculée"), measure(metrics.watts, "W", digits: 2)),
         (L("Niveau critique"), metrics.isCritical.map { $0 ? L("Oui") : L("Non") })]
    }
}

/// Contenu de la fenêtre Batterie, sans état de l’app : même rendu en aperçu et en direct.
struct BatteryPanel: View {
    let information: DeviceInformation?
    private var figures: BatteryFigures { BatteryFigures(information: information) }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            summary.frame(width: 290)
            Rectangle().fill(Palette.line).frame(width: 1).padding(.horizontal, 30)
            details.frame(maxWidth: .infinity, alignment: .topLeading)
        }
    }

    private var summary: some View {
        VStack(spacing: 0) {
            BatteryGauge(percent: information?.batteryPercent, charging: information?.powerState == .charging)
                .frame(width: 214, height: 98).padding(.top, 12)
            Text(figures.percentText)
                .font(.system(size: 48, weight: .semibold, design: .rounded)).monospacedDigit()
                .padding(.top, 18)
            Label(figures.stateLine, systemImage: figures.state.symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(information?.powerState == .charging ? BatteryGauge.green : Palette.secondary)
                .padding(.top, 2)
            healthCard.padding(.top, 26)
        }.frame(maxWidth: .infinity)
    }

    private var healthCard: some View {
        Surface(padding: 16) {
            VStack(alignment: .leading, spacing: 9) {
                HStack(alignment: .firstTextBaseline) {
                    Text(figures.healthTitle).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.secondary)
                    Spacer(minLength: 8)
                    Text(figures.measure(figures.health, "%") ?? L("Non exposé"))
                        .font(.system(size: figures.health == nil ? 13 : 22, weight: .semibold)).monospacedDigit()
                        .foregroundStyle(figures.health == nil ? Palette.secondary : figures.healthColor)
                }
                Capsule().fill(Palette.line).frame(height: 6)
                    .overlay(alignment: .leading) {
                        GeometryReader { geometry in
                            Capsule().fill(figures.healthColor)
                                .frame(width: geometry.size.width * CGFloat(min(100, figures.health ?? 0)) / 100)
                        }
                    }
                    .accessibilityHidden(true)
                if let summary = figures.capacitySummary {
                    Text(summary).font(.system(size: 11)).foregroundStyle(Palette.secondary)
                }
                if let cycles = figures.cyclesSummary {
                    Text(cycles).font(.system(size: 11)).foregroundStyle(Palette.secondary)
                }
                Text(L("À comparer avec Réglages > Batterie sur l’appareil. Le niveau de charge ne mesure pas la santé de la batterie."))
                    .font(.system(size: 10)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
            }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(L("Données techniques")).font(.system(size: 17, weight: .semibold)).padding(.bottom, 14)
            group(L("Capacité"), figures.capacityRows)
            group(L("Alimentation"), figures.powerRows).padding(.top, 18)
            HStack(spacing: 10) {
                Text(L("Série de la batterie")).foregroundStyle(Palette.secondary)
                Spacer(minLength: 8)
                Text(figures.metrics.serial ?? L("Non exposé")).fontWeight(.semibold).textSelection(.enabled)
                if let serial = figures.metrics.serial { CopyValueButton(value: serial, name: L("Série de la batterie")) }
            }.font(.system(size: 13)).padding(.top, 16)
            Text(L("Une mesure absente reste non exposée. Ces informations ne certifient pas l’origine de la batterie."))
                .font(.system(size: 10)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true).padding(.top, 12)
        }
    }

    private func group(_ title: String, _ rows: [(String, String?)]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Eyebrow(text: title).padding(.bottom, 4)
            ForEach(rows.indices, id: \.self) { index in
                HStack {
                    Text(rows[index].0).foregroundStyle(Palette.secondary)
                    Spacer(minLength: 12)
                    Text(rows[index].1 ?? L("Non exposé")).fontWeight(.semibold).monospacedDigit()
                        .foregroundStyle(rows[index].1 == nil ? Palette.secondary : Palette.ink)
                        .textSelection(.enabled)
                }
                .font(.system(size: 13)).padding(.vertical, 6)
                .overlay(alignment: .bottom) {
                    if index < rows.count - 1 { Rectangle().fill(Palette.line).frame(height: 0.5) }
                }
            }
        }
    }
}

struct BatteryDetailView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    let target: DeviceSnapshot
    @ViewState private var continuous = false
    @ViewState private var exportError: String?
    private var information: DeviceInformation? {
        guard let info = model.deviceInformation, info.device.id == target.id, info.device.ecid == target.ecid else { return nil }
        return info
    }
    private var connected: Bool { model.devices.contains { $0.id == target.id && $0.ecid == target.ecid } }
    private var canRead: Bool { connected && target.mode == .normal && !model.busy }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(L("Batterie")).font(.system(size: 27, weight: .light))
                    Text(model.isDemo ? L("Appareil d’exemple") : target.name).font(.system(size: 12)).foregroundStyle(Palette.secondary)
                }
                Spacer()
                Button(L("Exporter")) { export() }.buttonStyle(QuietButtonStyle()).disabled(information == nil)
                Button { dismiss() } label: { CloseGlyph() }.buttonStyle(.plain).keyboardShortcut(.cancelAction).accessibilityLabel(L("Fermer"))
            }
            BatteryPanel(information: information)
            VStack(alignment: .leading, spacing: 5) {
                if !connected { Text(L("Appareil déconnecté · dernières informations disponibles")).foregroundStyle(Palette.amber) }
                if let error = model.deviceInformationError ?? exportError { Text(error).foregroundStyle(Palette.amber) }
                if let warning = information?.warnings.first { Text(warning).foregroundStyle(Palette.secondary) }
            }.font(.system(size: 10)).lineLimit(3)
            Spacer(minLength: 0)
            HStack(spacing: 10) {
                Toggle(L("Mises à jour continues"), isOn: $continuous).toggleStyle(.switch).controlSize(.small)
                    .disabled(!connected || target.mode != .normal)
                Text(L("Toutes les 15 s")).font(.system(size: 10)).foregroundStyle(Palette.secondary)
                Spacer()
                if let date = information?.date {
                    Text(L("Dernière lecture : \(date.uiFormatted(date: .omitted, time: .standard))")).font(.system(size: 10)).foregroundStyle(Palette.secondary)
                }
                if model.isReadingDeviceInformation { ProgressView().controlSize(.small) }
                Button(L("Actualiser")) { Task { await model.refreshDeviceInformation(target, batteryDetails: true) } }
                    .buttonStyle(QuietButtonStyle()).disabled(!canRead)
            }
        }.padding(26).frame(width: 880, height: 660).foregroundStyle(Palette.ink).background(Palette.canvas)
            .task {
                // The parent sheet may still be completing its initial overview read.
                while model.isReadingDeviceInformation && !Task.isCancelled { try? await Task.sleep(for: .milliseconds(100)) }
                guard !Task.isCancelled else { return }
                await model.refreshDeviceInformation(target, batteryDetails: true)
            }
            .task(id: continuous) {
                guard continuous else { return }
                while !Task.isCancelled {
                    do { try await Task.sleep(for: .seconds(15)) } catch { return }
                    if canRead { await model.refreshDeviceInformation(target, batteryDetails: true) }
                }
            }
    }

    private func export() {
        guard let information else { return }
        let figures = BatteryFigures(information: information)
        let panel = NSSavePanel(); panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "iTelier-battery.txt"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let header = "iTelier · " + L("Batterie") + "\n" + (model.isDemo ? L("Appareil d’exemple") : target.productType) + "\n" + information.date.uiFormatted(date: .abbreviated, time: .standard)
        let rows = [(L("Niveau de charge"), information.batteryPercent.map { "\($0) %" }),
                    (L("Capacité maximale déclarée"), figures.measure(figures.metrics.declaredHealth, "%")),
                    (L("Capacité maximale estimée"), figures.measure(figures.metrics.estimatedHealth, "%"))]
            + figures.capacityRows + figures.powerRows
        let text = header + "\n\n" + rows.map { $0.0 + ": " + ($0.1 ?? L("Non exposé")) }.joined(separator: "\n")
            + "\n\n" + L("Les numéros de série ne sont pas inclus dans cet export.")
        do { try text.write(to: url, atomically: true, encoding: .utf8); exportError = nil }
        catch { exportError = UserFacingError.presentation(for: error, operation: .idle).message }
    }
}
