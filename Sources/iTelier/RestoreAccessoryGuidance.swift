import SwiftUI
import iTelierCore

/// Aide facultative : le réglage appartient à macOS et reste choisi par l’utilisateur.
struct RestoreAccessoryGuidance: View {
    var body: some View {
        Surface(padding: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Label(L("Moins d’interruptions pendant la restauration"), systemImage: "cable.connector")
                    .font(.system(size: 14, weight: .medium))
                Text(L("L’appareil se reconnecte plusieurs fois. macOS peut demander son autorisation à chaque étape."))
                    .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                DisclosureGroup(L("Configurer les connexions sur ce Mac")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text(L("Dans Réglages Système > Confidentialité et sécurité > Accessoires, choisissez « Autoriser automatiquement au déverrouillage », puis gardez votre Mac déverrouillé."))
                            .fixedSize(horizontal: false, vertical: true).lineSpacing(3)
                        Text(L("Ce réglage concerne tous les accessoires connectés à ce Mac. iTelier ne le modifie pas."))
                            .foregroundStyle(Palette.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 16) {
                            Link(L("Ouvrir les réglages macOS"), destination: URL(string: "x-apple.systempreferences:com.apple.preference.security")!)
                                .buttonStyle(QuietButtonStyle())
                            Link(L("Aide Apple"), destination: URL(string: "https://support.apple.com/fr-fr/102282")!)
                                .foregroundStyle(Palette.accent)
                        }
                    }.padding(.top, 10)
                }.font(.system(size: 12)).tint(Palette.accent)
            }
        }
    }
}
