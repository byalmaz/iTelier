import SwiftUI
import iTelierCore

struct CheckView: View {
    @EnvironmentObject private var model: AppModel
    @ViewState private var category: CheckCategory?
    @ViewState private var selectedItem: CheckItem?
    @ViewState private var faceIDReport: DiagnosticReport?
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if let device = model.device, FaceIDTest.supportsGuidedTest(device) {
                Surface(padding: 18) {
                    HStack(spacing: 16) {
                        GlassIcon(systemName: "faceid", size: 48, color: Palette.accent).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(L("Test Face ID")).font(.system(size: 17, weight: .medium))
                            Text(L("Vérifiez le déverrouillage et consultez les informations disponibles sur TrueDepth."))
                                .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                        }
                        Spacer()
                        Button(L("Commencer le test")) {
                            Task {
                                if model.currentReport == nil { await model.runCheck() }
                                if let report = model.currentReport, report.device.id == device.id {
                                    faceIDReport = report
                                }
                            }
                        }.buttonStyle(QuietButtonStyle()).disabled(model.busy)
                    }
                }
            }
            if let report = model.currentReport {
                summary(report)
                referencePanel(report)
                if let sources = report.sources, !sources.isEmpty {
                    Surface(padding: 18) {
                        DisclosureGroup(L("Sources consultées · \(sources.count)")) {
                            VStack(alignment: .leading, spacing: 12) {
                                ForEach(sources) { source in
                                    VStack(alignment: .leading, spacing: 5) {
                                        HStack { Text(AppLocalization.label(source.title)).font(.system(size: 12, weight: .medium)); Spacer(); StatusBadge(status: source.status) }
                                        Text(AppLocalization.label(source.detail)).font(.system(size: 11)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }.padding(.top, 14)
                        }.font(.system(size: 12))
                    }
                }
                HStack(spacing: 7) {
                    filter(L("Tout"), category: nil)
                    ForEach(CheckCategory.displayOrder, id: \.rawValue) { value in
                        filter(value == .identity ? L("Identité") : value == .components ? L("Pièces") : value == .security ? L("Sécurité") : value.title, category: value)
                    }
                    Spacer(minLength: 0)
                }
                VStack(spacing: 0) {
                    HStack(spacing: 12) {
                        Text(L("ÉLÉMENT")).frame(maxWidth: .infinity, alignment: .leading)
                        Text(L("VALEUR LUE")).frame(width: 222, alignment: .leading)
                        Text(L("RÉFÉRENCE")).frame(width: 105, alignment: .leading)
                        Text(L("RÉSULTAT")).frame(width: 126, alignment: .leading)
                    }.font(.system(size: 10, weight: .medium)).tracking(1)
                        .foregroundStyle(Palette.secondary).padding(.horizontal, 22).padding(.vertical, 17)
                    ForEach(CheckCategory.displayOrder, id: \.rawValue) { group in
                        let items = report.items.filter { $0.category == group && (category == nil || category == group) }
                        if !items.isEmpty {
                            HStack(spacing: 7) {
                                Image(systemName: group.symbol)
                                Text(group.title).fontWeight(.medium)
                                Spacer()
                            }.font(.system(size: 11)).foregroundStyle(Palette.secondary)
                                .padding(.horizontal, 22).padding(.vertical, 12)
                                .background(Palette.canvas.opacity(0.35))
                            ForEach(items) { item in
                                checkRow(item)
                            }
                        }
                    }
                }.background(Palette.card, in: RoundedRectangle(cornerRadius: 24))
                    .clipShape(RoundedRectangle(cornerRadius: 24))
                    .overlay(RoundedRectangle(cornerRadius: 24).stroke(Color.white.opacity(0.16)))
                    .shadow(color: Palette.deep.opacity(0.15), radius: 20, y: 8)
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "info.circle")
                    Text(L("Une valeur lue ne prouve pas l’origine d’une pièce. Une référence absente reste absente : aucun score d’authenticité n’est calculé."))
                        .lineSpacing(3)
                }.font(.system(size: 12)).foregroundStyle(Palette.secondary)
            } else {
                Surface {
                    VStack(spacing: 22) {
                        GlassIcon(systemName: "checkmark.shield.fill", size: 118, color: Palette.accent)
                            .padding(.bottom, 6).accessibilityHidden(true)
                        Text(model.isChecking ? L("Lecture de l’appareil…") : L("Un état des lieux, sans deviner."))
                            .font(.system(size: 28, weight: .light)).tracking(-0.5)
                        Text(model.device == nil
                             ? L("Connectez votre appareil en USB pour lire son identité,\nsa batterie et les informations accessibles.")
                             : model.device?.mode != .normal
                             ? L("Redémarrez l’appareil en mode normal, déverrouillez-le\net acceptez « Faire confiance » pour lancer une vérification.")
                             : L("Le rapport distingue les données lues, les points à examiner\net les contrôles à effectuer directement sur votre appareil."))
                            .multilineTextAlignment(.center).font(.system(size: 13)).foregroundStyle(Palette.secondary).lineSpacing(5)
                        if model.isChecking { ProgressView().padding(8) }
                        else {
                            Button { Task { await model.runCheck() } } label: { Label(L("Lancer la vérification"), systemImage: "magnifyingglass") }
                                .buttonStyle(PrimaryButtonStyle())
                                .disabled(model.device == nil || model.device?.mode != .normal || model.busy)
                        }
                    }.frame(maxWidth: .infinity).padding(.vertical, 48)
                }
            }
        }
        .foregroundStyle(Palette.ink)
        .sheet(isPresented: Binding(get: { faceIDReport != nil }, set: { if !$0 { faceIDReport = nil } })) {
            if let faceIDReport { FaceIDTestView(report: faceIDReport).environmentObject(model) }
        }
        .sheet(item: $selectedItem) { item in
            VStack(alignment: .leading, spacing: 18) {
                HStack {
                    GlassIcon(systemName: item.category.symbol, size: 45, color: Palette.accent)
                        .accessibilityHidden(true)
                    Text(AppLocalization.label(item.title)).font(.system(size: 24, weight: .light))
                    Spacer()
                    Button { selectedItem = nil } label: { CloseGlyph() }.buttonStyle(.plain).accessibilityLabel(L("Fermer le détail"))
                }
                HStack {
                    StatusBadge(status: item.status)
                    if let match = item.referenceMatch { ReferenceMatchBadge(match: match) }
                }
                Rectangle().fill(Palette.line).frame(height: 1)
                HStack(alignment: .top, spacing: 12) {
                    Text(L("Valeur lue"))
                    Text(model.checkValue(item)).textSelection(.enabled)
                    if let value = copyValue(item) {
                        CopyValueButton(value: value, name: item.title).id(value)
                    }
                }
                LabeledContent(L("Référence"), value: item.expected.map { model.visible($0, sensitive: item.sensitive) } ?? L("Aucune référence disponible"))
                if let reference = model.checkReference, item.expected != nil {
                    Text(reference.origin.title + " · " + reference.date.uiFormatted(date: .abbreviated, time: .shortened))
                        .font(.system(size: 11)).foregroundStyle(Palette.secondary)
                    Text(L("Référence de comparaison enregistrée, sans certification d’origine usine."))
                        .font(.system(size: 11)).foregroundStyle(Palette.secondary)
                }
                if let source = item.source, !source.isEmpty {
                    Text(L("Source : ") + source).font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.secondary).textSelection(.enabled)
                }
                Text(L("Méthode et limites")).font(.system(size: 13, weight: .medium)).padding(.top, 7)
                Text(AppLocalization.label(item.detail)).font(.system(size: 13)).foregroundStyle(Palette.secondary).lineSpacing(5).textSelection(.enabled)
                Spacer(minLength: 8)
                HStack { Spacer(); Button(L("Fermer")) { selectedItem = nil }.buttonStyle(QuietButtonStyle()) }
            }.padding(28).frame(width: 530, alignment: .leading)
                .foregroundStyle(Palette.ink).background(Palette.canvas)
                
        }
    }
    private func referencePanel(_ report: DiagnosticReport) -> some View {
        Surface(padding: 18) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "doc.badge.clock").foregroundStyle(Palette.accent).font(.system(size: 22))
                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.checkReference == nil ? L("Ajouter une référence de comparaison") : L("Référence de comparaison"))
                            .font(.system(size: 15, weight: .medium))
                        if let reference = model.checkReference {
                            Text(reference.origin.title + " · " + reference.date.uiFormatted(date: .abbreviated, time: .shortened))
                                .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                            let same = report.items.filter { $0.referenceMatch == .same }.count
                            let different = report.items.filter { $0.referenceMatch == .different }.count
                            let initial = report.items.contains { $0.referenceMatch == .initial }
                            Text(initial ? L("Relevé initial enregistré. Relancez le Check pour comparer une nouvelle lecture.")
                                 : L("\(same) \(same == 1 ? "valeur identique" : "valeurs identiques") · \(different) \(different > 1 ? "écarts" : "écart") · \(reference.values.count) valeurs de référence"))
                                .font(.system(size: 12)).foregroundStyle(different > 0 ? Palette.amber : Palette.accent)
                        }
                        Text(L("Enregistrez ce Check ou importez un ancien rapport du même appareil. Les références sont conservées sur ce Mac et rechargées aux prochains contrôles. Les mesures évolutives et tests manuels ne sont pas comparés. L’origine usine des pièces n’est pas certifiée."))
                            .font(.system(size: 11)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true).lineSpacing(3)
                    }
                    Spacer(minLength: 0)
                }
                HStack(spacing: 12) {
                    Button(model.checkReference == nil ? L("Enregistrer ce Check") : L("Remplacer par ce Check")) { model.saveCheckReference() }
                        .buttonStyle(QuietButtonStyle()).disabled(model.busy)
                    Button(L("Importer un rapport…")) { model.importCheckReference() }
                        .buttonStyle(QuietButtonStyle()).disabled(model.busy)
                }
                if let error = model.referenceError {
                    Text(error).font(.system(size: 12)).foregroundStyle(Palette.amber).fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private func resultTitle(_ item: CheckItem) -> String {
        item.referenceMatch.map { ReferenceMatchBadge(match: $0).title } ?? StatusBadge(status: item.status).title
    }

    private func copyValue(_ item: CheckItem) -> String? {
        guard item.id == "serial" || item.id == "ecid" || item.id.hasPrefix("imei") || item.id.hasSuffix("-serial"),
              let value = item.actual, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        // Copy the complete source value, independently of its visual masking or truncation.
        return value
    }

    private func checkRow(_ item: CheckItem) -> some View {
        HStack(spacing: 12) {
            Button {
                if item.id == "face-id" || item.id == "faceid" { faceIDReport = model.currentReport }
                else { selectedItem = item }
            } label: {
                Text(AppLocalization.label(item.title)).font(.system(size: 13, weight: .regular))
                    .frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain).help(L("Voir la source et les limites du contrôle"))
            HStack(spacing: 12) {
                Button { selectedItem = item } label: {
                    Text(model.checkValue(item))
                        .font(.system(size: 12, design: item.sensitive ? .monospaced : .default))
                        .foregroundStyle(item.actual == nil ? Palette.secondary : Palette.ink)
                        .frame(maxWidth: .infinity, alignment: .leading).lineLimit(2).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel(item.title + " : " + model.checkValue(item))
                if let value = copyValue(item) {
                    CopyValueButton(value: value, name: item.title).id(value)
                } else {
                    Color.clear.frame(width: 60, height: 26)
                }
            }.frame(width: 222, alignment: .leading)
            Button { selectedItem = item } label: {
                HStack(spacing: 12) {
                    Text(item.expected.map { model.visible($0, sensitive: item.sensitive) } ?? "—")
                        .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                        .frame(width: 105, alignment: .leading).lineLimit(1)
                    Group {
                        if let match = item.referenceMatch { ReferenceMatchBadge(match: match) }
                        else { StatusBadge(status: item.status) }
                    }.frame(width: 126, alignment: .leading)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityLabel(L("Détails : ") + item.title + ", " + resultTitle(item))
        }.padding(.horizontal, 22).padding(.vertical, 15)
            .overlay(alignment: .bottom) { Rectangle().fill(Palette.line.opacity(0.5)).frame(height: 1).padding(.horizontal, 22) }
    }

    private func summary(_ report: DiagnosticReport) -> some View {
        Surface(padding: 24) {
            VStack(alignment: .leading, spacing: 20) {
                HStack(spacing: 18) {
                    GlassIcon(systemName: report.attention > 0 ? "exclamationmark.shield.fill" : "doc.text.magnifyingglass",
                                 size: 65, color: report.attention > 0 ? Palette.amber : Palette.accent)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(report.summary).font(.system(size: 27, weight: .light)).tracking(-0.5)
                        Text(L("Contrôle partiel · \(report.date.uiFormatted(date: .abbreviated, time: .shortened))"))
                            .font(.system(size: 11)).foregroundStyle(Palette.secondary)
                    }
                    Spacer()
                    Button { Task { await model.runCheck() } } label: {
                        if model.isChecking { ProgressView().controlSize(.small) }
                        else { Image(systemName: "arrow.clockwise").foregroundStyle(Palette.ink).font(.system(size: 14)) }
                    }.buttonStyle(.plain).help(L("Relancer la vérification")).accessibilityLabel(L("Relancer la vérification")).disabled(model.busy)
                }
                HStack(spacing: 25) {
                    count(report.available, L("Données disponibles"), color: Palette.accent)
                    count(report.attention, L("Points à examiner"), color: Palette.amber)
                    count(report.manual + report.unavailable, L("Non lus / manuels"), color: Palette.secondary)
                    Spacer(minLength: 0)
                    VStack(alignment: .trailing, spacing: 12) {
                        Toggle(L("Afficher les numéros de série"), isOn: $model.revealIdentifiers).toggleStyle(.switch).controlSize(.mini)
                            .font(.system(size: 10)).fixedSize()
                        Button { model.exportReport() } label: { Label(L("Exporter le rapport"), systemImage: "square.and.arrow.up") }
                            .buttonStyle(QuietButtonStyle()).help(model.revealIdentifiers ? L("L’export contiendra les numéros de série") : L("Les numéros de série seront masqués"))
                    }
                }
            }
        }
    }
    private func count(_ number: Int, _ title: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(String(number)).font(.system(size: 35, weight: .light)).foregroundStyle(color)
            Text(title).font(.system(size: 11)).foregroundStyle(Palette.secondary)
        }
    }
    private func filter(_ title: String, category value: CheckCategory?) -> some View {
        Button { category = value } label: {
            Text(title).font(.system(size: 12, weight: .medium)).padding(.horizontal, 14).padding(.vertical, 10)
                .foregroundStyle(category == value ? Palette.accent : Palette.secondary)
                .background(category == value ? Palette.accent.opacity(0.16) : Palette.card.opacity(0.6), in: Capsule())
                .overlay(Capsule().stroke(category == value ? Palette.accent.opacity(0.5) : Palette.line, lineWidth: 1))
        }.buttonStyle(.plain)
    }
}
