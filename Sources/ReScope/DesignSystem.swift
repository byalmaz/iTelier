import AppKit
import SwiftUI
import ReScopeCore

// Use the stable property wrapper. SDK 27 also exports a State macro whose
// plugin is absent from some Command Line Tools installations.
typealias ViewState<Value> = SwiftUI.State<Value>

enum Palette {
    private static func adaptive(_ dark: UInt32, _ light: UInt32, darkAlpha: CGFloat = 1, lightAlpha: CGFloat = 1) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let hex = isDark ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 255) / 255,
                           green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255,
                           alpha: isDark ? darkAlpha : lightAlpha)
        })
    }
    static let ink = adaptive(0xF7F4FC, 0x282237)
    static let secondary = adaptive(0xC6C1D8, 0x625B73)
    static let accent = adaptive(0x43D6F1, 0x087E94)
    static let canvas = adaptive(0x1C1533, 0xF5F3FA)
    static let sidebar = canvas
    static let card = adaptive(0xFFFFFF, 0xFFFFFF, darkAlpha: 0.11, lightAlpha: 0.70)
    static let surfaceTop = adaptive(0xFFFFFF, 0xFFFFFF, darkAlpha: 0.13, lightAlpha: 0.90)
    static let surfaceBottom = adaptive(0xFFFFFF, 0xFFFFFF, darkAlpha: 0.08, lightAlpha: 0.55)
    static let line = adaptive(0xFFFFFF, 0x47375F, darkAlpha: 0.18, lightAlpha: 0.16)
    static let mint = adaptive(0x86E7B9, 0x23784F)
    static let amber = adaptive(0xFFD476, 0x945C05)
    static let red = adaptive(0xFF9DAA, 0xB82D49)
    static let yellow = Color(red: 1, green: 215 / 255, blue: 49 / 255)
    static let violet = adaptive(0xAA91EF, 0x7957BA)
    static let deep = adaptive(0x130F25, 0xEAE6F2)
    static let backgroundTop = adaptive(0x302652, 0xEDE8F9)
    static let closeBackground = adaptive(0xFFFFFF, 0x282237, darkAlpha: 0.14, lightAlpha: 0.09)
    static let onDestructive = adaptive(0x1C1533, 0xFFFFFF)
    static let onAction = Color(red: 28 / 255, green: 21 / 255, blue: 51 / 255)
}

struct PrimaryButtonStyle: ButtonStyle {
    var destructive = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .semibold))
            .padding(.horizontal, 23).padding(.vertical, 13)
            .foregroundStyle(enabled ? (destructive ? Palette.onDestructive : Palette.onAction) : Palette.secondary.opacity(0.65))
            .background(enabled ? (destructive ? Palette.red : Palette.yellow) : Palette.card, in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(enabled ? Color.white.opacity(0.14) : Palette.line.opacity(0.5), lineWidth: 1))
            .shadow(color: enabled ? (destructive ? Palette.red : Palette.yellow).opacity(0.12) : .clear, radius: 12, y: 4)
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .contentShape(RoundedRectangle(cornerRadius: 12))
    }
}
struct CloseGlyph: View {
    var body: some View {
        Image(systemName: "xmark").font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Palette.secondary)
            .frame(width: 30, height: 30)
            .background(Palette.closeBackground, in: Circle())
            .contentShape(Circle())
    }
}

struct QuietButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(enabled ? Palette.ink : Palette.secondary.opacity(0.55))
            .padding(.horizontal, 16).padding(.vertical, 11)
            .background(LinearGradient(colors: [Palette.surfaceTop, Palette.violet.opacity(configuration.isPressed ? 0.18 : 0.08)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).stroke(Palette.line.opacity(enabled ? 1 : 0.5), lineWidth: 1))
            .contentShape(RoundedRectangle(cornerRadius: 11))
    }
}
struct Surface<Content: View>: View {
    var padding: CGFloat = 22
    @ViewBuilder let content: Content
    var body: some View {
        content.padding(padding).frame(maxWidth: .infinity, alignment: .leading)
            .background(LinearGradient(colors: [Palette.surfaceTop, Palette.surfaceBottom], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 20))
            .overlay(RoundedRectangle(cornerRadius: 20).stroke(Palette.line, lineWidth: 1))
            .shadow(color: .black.opacity(0.12), radius: 18, y: 8)
    }
}
struct Eyebrow: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10, weight: .semibold)).tracking(1.7)
            .foregroundStyle(Palette.secondary)
    }
}
struct StatusBadge: View {
    let status: CheckStatus
    var title: String {
        switch status {
        case .read: return L("Lu")
        case .verified: return L("Comparé")
        case .attention: return L("À examiner")
        case .unavailable: return L("Non exposé")
        case .unsupported: return L("Non pris en charge")
        case .readFailed: return L("Lecture échouée")
        case .manual: return L("Test manuel")
        }
    }
    var color: Color {
        switch status {
        case .read: return Palette.accent
        case .verified: return Palette.mint
        case .attention: return Palette.amber
        case .unavailable, .unsupported, .manual: return Palette.secondary
        case .readFailed: return Palette.amber
        }
    }
    var symbol: String {
        switch status {
        case .read: return "doc.text.magnifyingglass"
        case .verified: return "checkmark.circle.fill"
        case .attention: return "exclamationmark.circle.fill"
        case .unavailable: return "minus.circle"
        case .unsupported: return "nosign"
        case .readFailed: return "exclamationmark.arrow.triangle.2.circlepath"
        case .manual: return "hand.tap"
        }
    }
    var body: some View {
        Label(title, systemImage: symbol).font(.system(size: 11, weight: .medium))
            .foregroundStyle(color).padding(.horizontal, 9).padding(.vertical, 6)
            .background(color.opacity(0.11), in: Capsule())
            .overlay(Capsule().stroke(color.opacity(0.20), lineWidth: 1))
    }
}
struct ReferenceMatchBadge: View {
    let match: ReferenceMatch
    var title: String {
        switch match {
        case .same: return L("Identique")
        case .different: return L("Écart")
        case .unreadable: return L("Non comparable")
        case .initial: return L("Relevé initial")
        }
    }
    var body: some View {
        let color = match == .same ? Palette.mint : match == .different ? Palette.amber : Palette.secondary
        Label(title, systemImage: match == .same ? "equal.circle" : match == .different ? "exclamationmark.circle" : "minus.circle")
            .font(.system(size: 10, weight: .medium)).foregroundStyle(color)
            .padding(.horizontal, 8).padding(.vertical, 6)
            .background(color.opacity(0.11), in: Capsule()).overlay(Capsule().stroke(color.opacity(0.20)))
    }
}

extension CheckCategory {
    var title: String {
        switch self {
        case .identity: return L("Identité de l’appareil")
        case .battery: return L("Batterie")
        case .components: return L("Pièces et capteurs")
        case .security: return L("Activation et sécurité")
        case .connectivity: return L("Connectivité")
        }
    }
    var symbol: String {
        switch self {
        case .identity: return "iphone"
        case .battery: return "battery.75percent"
        case .components: return "cpu"
        case .security: return "lock.shield"
        case .connectivity: return "wifi"
        }
    }
    static var displayOrder: [CheckCategory] { [.identity, .battery, .components, .connectivity, .security] }
}
extension DeviceMode {
    var title: String {
        switch self {
        case .normal: return L("Mode normal")
        case .recovery: return L("Récupération")
        case .dfu: return L("Mode DFU")
        }
    }
}
extension DiagnosticReport {
    var available: Int { items.filter { $0.actual != nil && [.read, .verified, .attention].contains($0.status) }.count }
    var attention: Int { items.filter { $0.status == .attention || $0.referenceMatch == .different }.count }
    var manual: Int { items.filter { $0.status == .manual }.count }
    var unavailable: Int { items.filter { [.unavailable, .unsupported, .readFailed].contains($0.status) }.count }
    var readFailures: Int { sources?.filter { $0.status == .readFailed }.count ?? 0 }
    var summary: String {
        readFailures > 0 ? L("Lecture partielle · \(readFailures) source\(readFailures > 1 ? "s" : "") à relancer") : attention > 0 ? L("\(attention) point\(attention > 1 ? "s" : "") à examiner")
            : L("Lecture terminée")
    }
}

/// A shared vector icon: tinted glass, a refractive edge and a crisp SF Symbol.
/// All icon sizes stay upright and face forward.
struct GlassIcon: View {
    let systemName: String
    var size: CGFloat = 58
    var color: Color = Palette.violet
    var phoneDuo = false
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    private var edge: AngularGradient {
        AngularGradient(colors: [.white.opacity(0.95), color, Palette.violet,
                                Palette.amber.opacity(0.85), .white.opacity(0.90), color, .white.opacity(0.95)],
                        center: .center, startAngle: .degrees(-135), endAngle: .degrees(225))
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.255, style: .continuous)
        ZStack {
            // The offset rim gives the transparent tile a visible thickness.
            shape.fill(LinearGradient(colors: [color.opacity(0.85), Palette.deep, Palette.violet.opacity(0.8)],
                                      startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(shape.strokeBorder(edge, lineWidth: max(1, size * 0.022)))
                .offset(x: size * 0.025, y: size * 0.045)
            shape.fill(reduceTransparency ? Palette.canvas : Palette.canvas.opacity(0.60))
            shape.fill(LinearGradient(colors: [.white.opacity(0.32), color.opacity(0.28),
                                               color.opacity(0.08), Palette.violet.opacity(0.40)],
                                      startPoint: .topLeading, endPoint: .bottomTrailing))
            if !reduceTransparency {
                ZStack {
                    Ellipse().fill(color.opacity(0.58))
                        .frame(width: size * 0.90, height: size * 0.52)
                        .blur(radius: size * 0.19).offset(x: -size * 0.28, y: size * 0.32)
                    Ellipse().fill(Palette.amber.opacity(0.42))
                        .frame(width: size * 0.54, height: size * 0.84)
                        .blur(radius: size * 0.18).offset(x: size * 0.43, y: -size * 0.17)
                    Ellipse().fill(.white.opacity(0.20))
                        .frame(width: size * 1.45, height: size * 0.76)
                        .rotationEffect(.degrees(-35)).offset(x: -size * 0.22, y: -size * 0.48)
                }.frame(width: size, height: size).clipShape(shape)
            }
            shape.strokeBorder(edge, lineWidth: contrast == .increased ? 2 : max(0.8, size * 0.013))
            shape.inset(by: size * 0.038)
                .strokeBorder(LinearGradient(colors: [.white.opacity(0.52), .clear, .white.opacity(0.13)],
                                             startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: max(0.5, size * 0.006))
            Group {
                if phoneDuo {
                    ZStack {
                        // Charnière à gauche, écran large et caméra dans le coin droit.
                        Capsule().fill(.white.opacity(0.65))
                            .frame(width: size * 0.012, height: size * 0.54)
                            .offset(x: -size * 0.224)
                        UnevenRoundedRectangle(topLeadingRadius: size * 0.018,
                                               bottomLeadingRadius: size * 0.018,
                                               bottomTrailingRadius: size * 0.075,
                                               topTrailingRadius: size * 0.075)
                            .strokeBorder(.white, lineWidth: size * 0.019)
                            .frame(width: size * 0.40, height: size * 0.57)
                        Circle().fill(.white)
                            .frame(width: size * 0.028, height: size * 0.028)
                            .offset(x: size * 0.139, y: -size * 0.222)
                        Capsule().fill(.white)
                            .frame(width: size * 0.14, height: size * 0.012)
                            .offset(y: size * 0.242)
                    }
                } else {
                    Image(systemName: systemName)
                }
            }.symbolRenderingMode(.monochrome)
                .font(.system(size: size * 0.51, weight: .medium))
                .foregroundStyle(.white)
                .shadow(color: color.opacity(0.85), radius: size * 0.075)
                .shadow(color: Palette.deep.opacity(0.50), radius: size * 0.015, y: size * 0.025)
        }
        .frame(width: size, height: size)
        .shadow(color: color.opacity(0.15), radius: size * 0.22, y: size * 0.08)
        .shadow(color: .black.opacity(0.24), radius: size * 0.09, y: size * 0.10)
        .frame(width: size * 1.25, height: size * 1.25)
        .accessibilityHidden(true)
    }
}

struct GlowRing: View {
    var size: CGFloat = 184
    var lineWidth: CGFloat = 4
    var color: Color = Palette.accent

    var body: some View {
        ZStack {
            Circle()
                .stroke(color.opacity(0.32), lineWidth: lineWidth * 7)
                .blur(radius: lineWidth * 5)
            Circle()
                .stroke(color.opacity(0.50), lineWidth: lineWidth * 2.5)
                .blur(radius: lineWidth * 1.5)
            Circle()
                .stroke(AngularGradient(colors: [color.opacity(0.65), color, .white.opacity(0.92), color, color.opacity(0.65)], center: .center, startAngle: .degrees(-90), endAngle: .degrees(270)), lineWidth: lineWidth)
            Circle()
                .stroke(Color.white.opacity(0.18), lineWidth: 0.7)
                .padding(lineWidth * 1.5)
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
