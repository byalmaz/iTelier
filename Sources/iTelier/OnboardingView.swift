import SwiftUI
import iTelierCore

struct OnboardingView: View {
    @EnvironmentObject private var model: AppModel
    @ViewState private var step = 0
    private let pages: [(String, String, String, String)] = [
        (L("Bienvenue dans iTelier"), L("Vos appareils Apple, à portée de main."), L("Faites connaissance avec iTelier. Retrouvez vos appareils Apple, prenez soin de vos données et découvrez les possibilités qui s’offrent à vous."), "cable.connector"),
        (L("Un regard clair sur votre appareil"), L("Vue d’ensemble et vérification"), L("Retrouvez le modèle, le système et les informations accessibles. Lancez un Check, copiez un numéro de série et conservez un relevé pour vos prochaines comparaisons."), "checkmark.shield.fill"),
        (L("La bonne version, au bon endroit"), L("Télécharger et restaurer"), L("Choisissez votre firmware dans le catalogue. iTelier vérifie les IPSW déjà présents, télécharge depuis Apple et permet de mettre le téléchargement en pause. Choisissez ensuite de conserver les données ou d’effacer l’appareil avant confirmation."), "arrow.down.doc.fill"),
        (L("Vos sauvegardes, sur votre Mac"), L("Sauvegardes locales"), L("Créez une sauvegarde, choisissez son emplacement et consultez celles déjà disponibles. Le chiffrement protège vos données : conservez précieusement votre mot de passe."), "externaldrive.badge.timemachine"),
        (L("Gardez le fil"), L("Activité et assistance"), L("Suivez la progression des opérations dans l’app. En cas d’erreur ou d’interruption, vous pouvez consulter puis partager un rapport depuis Configuration. Aucun rapport n’est envoyé automatiquement."), "clock.arrow.circlepath"),
        (L("À votre image"), L("Conçue en Belgique 🇧🇪"), L("Choisissez le thème sombre, clair ou système et votre langue dans Configuration. iTelier est un projet libre, sans abonnement, conçu pour vous laisser la main sur vos appareils. Cette visite reste accessible dans les réglages."), "slider.horizontal.3")
    ]
    var body: some View {
        VStack(spacing: 28) {
            HStack {
                Text("iTelier").font(.system(size: 16, weight: .semibold))
                Spacer()
                Picker(L("Langue"), selection: $model.language) {
                    ForEach(AppLanguage.allCases) { Text($0.title).tag($0) }
                }.frame(width: 130).labelsHidden()
                Button { model.finishOnboarding() } label: { CloseGlyph() }
                    .buttonStyle(.plain).accessibilityLabel(L("Fermer la visite")).keyboardShortcut(.cancelAction)
            }
            HStack(spacing: 38) {
                ZStack {
                    RoundedRectangle(cornerRadius: 32).fill(LinearGradient(colors: [Palette.accent.opacity(0.12), Palette.violet.opacity(0.17)], startPoint: .topLeading, endPoint: .bottomTrailing))
                    VStack(spacing: 26) {
                        GlassIcon(systemName: pages[step].3, size: 116, color: step == 3 ? Palette.mint : Palette.accent)
                        HStack(spacing: 12) {
                            Image(systemName: "iphone"); Image(systemName: "ipad"); Image(systemName: "visionpro")
                        }.font(.system(size: 25, weight: .ultraLight)).foregroundStyle(Palette.secondary)
                        Text(L("USB · local · open source")).font(.system(size: 11)).foregroundStyle(Palette.secondary)
                    }
                }.frame(width: 260, height: 300).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 18) {
                    Eyebrow(text: pages[step].1)
                    Text(pages[step].0).font(.system(size: 31, weight: .light)).tracking(-0.6)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(pages[step].2).font(.system(size: 14)).foregroundStyle(Palette.secondary).lineSpacing(6)
                        .fixedSize(horizontal: false, vertical: true)
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack(spacing: 8) {
                ForEach(pages.indices, id: \.self) { index in
                    Capsule().fill(index == step ? Palette.accent : Palette.secondary.opacity(0.3))
                        .frame(width: index == step ? 26 : 6, height: 6)
                }.accessibilityHidden(true)
                Text("\(step + 1) / \(pages.count)").font(.system(size: 11)).foregroundStyle(Palette.secondary).padding(.leading, 6)
                Spacer()
                if step == 0 {
                    Button(L("Plus tard")) { model.finishOnboarding() }.buttonStyle(QuietButtonStyle())
                } else {
                    Button(L("Précédent")) { step -= 1 }.buttonStyle(QuietButtonStyle())
                }
                Button(step == 0 ? L("Commencer la visite") : step == pages.count - 1 ? L("C’est parti") : L("Suivant")) {
                    if step == pages.count - 1 { model.finishOnboarding() } else { step += 1 }
                }.buttonStyle(PrimaryButtonStyle()).keyboardShortcut(.defaultAction)
            }
        }.padding(30).frame(width: 820).foregroundStyle(Palette.ink).background(Palette.canvas)
            .interactiveDismissDisabled()
    }
}
