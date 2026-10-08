import iTelierCore
import AppKit
import SwiftUI

struct CopyValueButton: View {
    let value: String
    let name: String
    var iconOnly = false
    @ViewState private var feedback: String?
    @ViewState private var copyGeneration = 0

    var body: some View {
        Button {
            let clipboard = NSPasteboard.general
            clipboard.clearContents()
            feedback = clipboard.setString(value, forType: .string) ? L("Copié") : L("Échec")
            copyGeneration += 1
        } label: {
            Group {
                if iconOnly {
                    Image(systemName: feedback == L("Copié") ? "checkmark" : feedback == L("Échec") ? "exclamationmark" : "doc.on.doc")
                } else {
                    Label(feedback ?? L("Copier"), systemImage: feedback == L("Copié") ? "checkmark" : "doc.on.doc")
                }
            }
                .font(.system(size: iconOnly ? 12 : 10, weight: .medium))
                .frame(width: iconOnly ? 26 : 60, height: 26)
                .foregroundStyle(Palette.accent)
                .background(Palette.accent.opacity(0.10), in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(feedback == L("Échec") ? L("La copie a échoué. Réessayez.") : L("Copier la valeur complète : ") + name)
        .accessibilityLabel((feedback ?? L("Copier")) + " : " + name)
        .task(id: copyGeneration) {
            guard copyGeneration > 0 else { return }
            do { try await Task.sleep(nanoseconds: 2_000_000_000) }
            catch { return }
            feedback = nil
        }
    }
}
