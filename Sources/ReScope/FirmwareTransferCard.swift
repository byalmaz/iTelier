import ReScopeCore
import SwiftUI

/// One card follows the IPSW from transfer through verification.
struct FirmwareTransferCard: View {
    let version: String
    let details: String
    let host: String?
    let size: String
    let fraction: Double?
    let isPaused: Bool
    let isVerifying: Bool
    var isCheckingExisting: Bool = false
    let isCancelling: Bool
    let onTogglePause: () -> Void
    let onCancel: () -> Void

    private var title: String {
        if isCancelling { return L("Annulation…") }
        if isCheckingExisting { return L("Vérification des fichiers locaux") }
        if isVerifying { return L("Vérification de l’IPSW") }
        return isPaused ? L("Téléchargement en pause") : L("Téléchargement de l’IPSW")
    }
    private var accent: Color { isPaused ? Palette.amber : Palette.accent }

    var body: some View {
        Surface(padding: 22) {
            VStack(alignment: .leading, spacing: 17) {
                HStack(spacing: 14) {
                    GlassIcon(systemName: isVerifying ? "doc.badge.gearshape" : isPaused ? "pause.fill" : "arrow.down",
                              size: 40, color: accent).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(title).font(.system(size: 20, weight: .medium))
                        Text(version + " · " + details)
                            .font(.system(size: 11)).foregroundStyle(Palette.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 16)
                    if !isVerifying, let fraction {
                        Text(fraction.formatted(.percent.precision(.fractionLength(0))))
                            .font(.system(size: 25, weight: .light, design: .rounded))
                            .monospacedDigit().foregroundStyle(accent)
                    }
                }
                Group {
                    if isVerifying || fraction == nil {
                        ProgressView().progressViewStyle(.linear)
                    } else {
                        ProgressView(value: fraction ?? 0).progressViewStyle(.linear)
                    }
                }.tint(accent).accessibilityLabel(isVerifying ? L("Vérification du fichier") : L("Téléchargement de l’IPSW"))
                HStack(alignment: .center, spacing: 20) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text(isCheckingExisting ? L("Recherche d’un IPSW déjà téléchargé…") : isVerifying ? L("Contrôle de l’intégrité et de la compatibilité…") : size)
                            .font(.system(size: 12, weight: .medium)).monospacedDigit()
                        Text(isCheckingExisting ? L("Un fichier compatible sera réutilisé sans téléchargement.")
                             : isPaused ? L("Reprenez ici en gardant l’app ouverte.")
                             : isVerifying ? L("Le fichier sera proposé pour la restauration une fois validé.")
                             : host.map { L("Depuis Apple · \($0)") } ?? L("Depuis les serveurs Apple"))
                            .font(.system(size: 11)).foregroundStyle(Palette.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    if !isVerifying {
                        Button(action: onTogglePause) {
                            Label(isPaused ? L("Reprendre") : L("Pause"), systemImage: isPaused ? "play.fill" : "pause.fill")
                        }.buttonStyle(QuietButtonStyle()).disabled(isCancelling)
                    }
                    Button(L("Annuler"), action: onCancel)
                        .buttonStyle(.plain).font(.system(size: 12, weight: .medium))
                        .foregroundStyle(Palette.secondary).disabled(isCancelling)
                        .help(isVerifying ? L("Arrêter la vérification du fichier") : L("Annuler et supprimer le téléchargement partiel"))
                }
            }
        }
    }
}
