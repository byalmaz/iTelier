import SwiftUI
import ReScopeCore

struct FaceIDTestView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @ViewState private var test: FaceIDTest

    init(report: DiagnosticReport) {
        _test = ViewState(initialValue: FaceIDTest(report: report))
    }

    private var available: Bool { test.matches(model.device) && !model.busy }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 13) {
                GlassIcon(systemName: "faceid", size: 47, color: Palette.accent)
                VStack(alignment: .leading, spacing: 5) {
                    Text(L("Test Face ID")).font(.system(size: 25, weight: .light))
                    Text(test.device.name).font(.system(size: 12)).foregroundStyle(Palette.secondary)
                }
                Spacer()
                Button { dismiss() } label: { CloseGlyph() }
                    .buttonStyle(.plain).accessibilityLabel(L("Fermer le test Face ID"))
            }
            if model.isDemo {
                Label(L("Aperçu : ce test utilise un appareil fictif."), systemImage: "sparkles")
                    .font(.system(size: 12)).foregroundStyle(Palette.amber)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if test.phase == .completed { resultContent }
                    else { instructionContent }
                    Surface(padding: 16) {
                        Label(L("Le résultat de déverrouillage est confirmé par vous. iTelier ne déclenche pas Face ID depuis le Mac et ne recueille aucune donnée de votre visage."), systemImage: "info.circle")
                            .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                            .fixedSize(horizontal: false, vertical: true).lineSpacing(4)
                    }
                }.padding(.horizontal, 2).padding(.bottom, 4)
            }
            actions
        }
        .padding(28).frame(width: 710, height: 675)
        .foregroundStyle(Palette.ink).background(Palette.canvas)
        .onChange(of: model.device?.id) { _ in if !test.matches(model.device) { dismiss() } }
        .onChange(of: model.device?.productType) { _ in if !test.matches(model.device) { dismiss() } }
        .onChange(of: model.device?.mode) { _ in if !test.matches(model.device) { dismiss() } }
        .onChange(of: model.device?.ecid) { _ in if !test.matches(model.device) { dismiss() } }
    }

    private var instructionContent: some View {
        VStack(spacing: 20) {
            GlassIcon(systemName: "faceid", size: 126, color: Palette.accent)
                .padding(.top, 10)
            Text(test.phase == .ready ? L("Vérifiez Face ID sur votre appareil") : L("Regardez l’écran de votre appareil"))
                .font(.system(size: 25, weight: .light)).multilineTextAlignment(.center)
            VStack(alignment: .leading, spacing: 14) {
                instruction(1, L("Si le code est demandé, saisissez-le une fois avant de commencer."))
                instruction(2, L("Verrouillez l’appareil avec le bouton latéral, puis réveillez l’écran."))
                instruction(3, L("Regardez l’écran. Le cadenas doit s’ouvrir sans saisir votre code."))
            }.frame(maxWidth: .infinity, alignment: .leading)
            if test.phase == .testing {
                Text(L("Le cadenas s’est-il ouvert avec Face ID ?"))
                    .font(.system(size: 15, weight: .medium)).padding(.top, 4)
            } else {
                Text(L("Pour un iPhone ou un iPad équipé de Face ID."))
                    .font(.system(size: 12)).foregroundStyle(Palette.secondary)
            }
        }.frame(maxWidth: .infinity)
    }

    private func instruction(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(String(number)).font(.system(size: 11, weight: .semibold))
                .frame(width: 23, height: 23).background(Palette.accent.opacity(0.12), in: Circle())
                .foregroundStyle(Palette.accent)
            Text(text).font(.system(size: 13)).lineSpacing(4).fixedSize(horizontal: false, vertical: true)
        }
    }

    private var resultContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 22) {
                GlassIcon(systemName: "faceid", size: 87, color: resultColor)
                VStack(alignment: .leading, spacing: 8) {
                    Text(resultTitle).font(.system(size: 26, weight: .light))
                    Label(L("Résultat confirmé par vous"), systemImage: "person.crop.circle.badge.checkmark")
                        .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                }
            }
            if test.result != .unlocked {
                Text(test.result == .notConfigured
                    ? L("Vérifiez Réglages > Face ID et code sur l’appareil pour configurer Face ID ou activer le déverrouillage.")
                    : L("Vérifiez que la caméra TrueDepth est dégagée et que Face ID est activé pour le déverrouillage. Un code demandé ne signifie pas forcément une panne."))
                    .font(.system(size: 13)).foregroundStyle(Palette.secondary).lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Surface(padding: 0) {
                VStack(spacing: 0) {
                    HStack {
                        Text(L("Identification du visage")).font(.system(size: 13, weight: .medium))
                        Spacer()
                        Label(resultTitle, systemImage: test.result == .unlocked ? "checkmark.circle.fill" : "minus.circle")
                            .font(.system(size: 12)).foregroundStyle(resultColor)
                    }.padding(18)
                    ForEach(test.components) { component in
                        Rectangle().fill(Palette.line.opacity(0.5)).frame(height: 1).padding(.horizontal, 18)
                        componentRow(component)
                    }
                }
            }
            Text(L("Un identifiant lu indique que l’appareil communique cette information. Il ne certifie pas le fonctionnement du composant. Le capteur de proximité n’est pas évalué par ce test."))
                .font(.system(size: 11)).foregroundStyle(Palette.secondary).lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func componentRow(_ component: FaceIDComponentReading) -> some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(AppLocalization.label(component.title)).font(.system(size: 13, weight: .medium))
                if let identifier = component.identifier {
                    Text(model.visible(identifier, sensitive: true)).font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Palette.secondary).textSelection(.enabled)
                }
            }
            Spacer()
            if component.status == .read {
                Label(L("Identifiant lu"), systemImage: "doc.text.magnifyingglass")
                    .font(.system(size: 12)).foregroundStyle(Palette.accent)
            } else { StatusBadge(status: component.status) }
        }.padding(18)
    }

    private var resultTitle: String {
        switch test.result {
        case .unlocked: return L("Déverrouillage réussi")
        case .failed: return L("Déverrouillage non réussi")
        case .notConfigured: return L("Face ID non configuré ou indisponible")
        case nil: return L("Test non effectué")
        }
    }
    private var resultColor: Color { test.result == .unlocked ? Palette.mint : Palette.amber }

    @ViewBuilder private var actions: some View {
        if test.phase == .testing {
            VStack(spacing: 10) {
                HStack(spacing: 12) {
                    Button(L("Non, le cadenas reste fermé")) { confirm(.failed) }.buttonStyle(QuietButtonStyle())
                    Spacer()
                    Button(L("Oui, Face ID m’a reconnu")) { confirm(.unlocked) }.buttonStyle(PrimaryButtonStyle())
                }
                Button(L("Face ID n’est pas configuré")) { confirm(.notConfigured) }
                    .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(Palette.secondary)
            }.disabled(!available)
        } else {
            HStack {
                Button(L("Fermer")) { dismiss() }.buttonStyle(QuietButtonStyle())
                Spacer()
                Button(test.phase == .ready ? L("Commencer le test") : L("Recommencer")) {
                    if !test.begin(on: model.device) { dismiss() }
                }.buttonStyle(PrimaryButtonStyle()).disabled(!available)
            }
        }
    }

    private func confirm(_ result: FaceIDTestResult) {
        guard available, test.confirm(result, on: model.device) else { dismiss(); return }
    }
}
