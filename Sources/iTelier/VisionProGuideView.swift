import AppKit
import SwiftUI
import iTelierCore

struct VisionProGuideView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 18) {
                GlassIcon(systemName: "visionpro", size: 64, color: Palette.violet)
                VStack(alignment: .leading, spacing: 5) {
                    Text(L("Restaurer Apple Vision Pro")).font(.system(size: 26, weight: .light))
                    Text(L("Avec Apple Configurator")).foregroundStyle(Palette.secondary)
                }
            }
            Text(L("iTelier propose le catalogue visionOS et le téléchargement des IPSW. La restauration du casque se fait avec Apple Configurator et un Developer Strap compatible."))
                .fixedSize(horizontal: false, vertical: true)
            Surface(padding: 18) {
                VStack(alignment: .leading, spacing: 14) {
                    Label(L("Un Developer Strap est nécessaire, avec une version compatible M5 pour le casque M5."), systemImage: "cable.connector")
                    Label(L("Ouvrez le guide Apple pour connecter le casque et passer en mode récupération."), systemImage: "book")
                    Label(L("Dans Configurator, sélectionnez le casque puis Actions > Avancées > Restaurer."), systemImage: "arrow.triangle.2.circlepath")
                }.font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
            }
            Text(L("La restauration directe et la sauvegarde locale de Vision Pro ne sont pas prises en charge par iTelier. Ne comptez pas sur une conservation des données lors de cette procédure."))
                .font(.system(size: 12)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
            Link(L("Lire la procédure Apple"), destination: URL(string: "https://support.apple.com/guide/apple-configurator-mac/apd819aacb61/mac")!)
            HStack {
                Button(L("Fermer")) { dismiss() }.buttonStyle(QuietButtonStyle())
                Spacer()
                Button(L("Ouvrir Apple Configurator")) {
                    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.configurator.ui") {
                        NSWorkspace.shared.openApplication(at: url, configuration: .init())
                    } else {
                        NSWorkspace.shared.open(URL(string: "https://apps.apple.com/app/apple-configurator/id1037126344")!)
                    }
                }.buttonStyle(PrimaryButtonStyle())
            }
        }.padding(30).frame(width: 630).foregroundStyle(Palette.ink).background(Palette.canvas)
    }
}
