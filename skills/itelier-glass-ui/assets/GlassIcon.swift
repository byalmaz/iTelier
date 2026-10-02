import SwiftUI

enum GlassPalette {
    static let ink = Color(red: 247 / 255, green: 244 / 255, blue: 252 / 255)
    static let secondary = Color(red: 198 / 255, green: 193 / 255, blue: 216 / 255)
    static let accent = Color(red: 67 / 255, green: 214 / 255, blue: 241 / 255)
    static let canvas = Color(red: 28 / 255, green: 21 / 255, blue: 51 / 255)
    static let sidebar = canvas
    static let card = Color.white.opacity(0.11)
    static let line = Color.white.opacity(0.18)
    static let mint = Color(red: 134 / 255, green: 231 / 255, blue: 185 / 255)
    static let amber = Color(red: 255 / 255, green: 212 / 255, blue: 118 / 255)
    static let red = Color(red: 255 / 255, green: 157 / 255, blue: 170 / 255)
    static let yellow = Color(red: 255 / 255, green: 215 / 255, blue: 49 / 255)
    static let violet = Color(red: 170 / 255, green: 145 / 255, blue: 239 / 255)
    static let deep = Color(red: 19 / 255, green: 15 / 255, blue: 37 / 255)
}

/// A shared vector icon: tinted glass, a refractive edge and a crisp SF Symbol.
/// All icon sizes stay upright and face forward.
struct GlassIcon: View {
    let systemName: String
    var size: CGFloat = 58
    var color: Color = GlassPalette.violet
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    private var edge: AngularGradient {
        AngularGradient(colors: [.white.opacity(0.95), color, GlassPalette.violet,
                                GlassPalette.amber.opacity(0.85), .white.opacity(0.90), color, .white.opacity(0.95)],
                        center: .center, startAngle: .degrees(-135), endAngle: .degrees(225))
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.255, style: .continuous)
        ZStack {
            // The offset rim gives the transparent tile a visible thickness.
            shape.fill(LinearGradient(colors: [color.opacity(0.85), GlassPalette.deep, GlassPalette.violet.opacity(0.8)],
                                      startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay(shape.strokeBorder(edge, lineWidth: max(1, size * 0.022)))
                .offset(x: size * 0.025, y: size * 0.045)
            shape.fill(reduceTransparency ? GlassPalette.canvas : GlassPalette.canvas.opacity(0.60))
            shape.fill(LinearGradient(colors: [.white.opacity(0.32), color.opacity(0.28),
                                               color.opacity(0.08), GlassPalette.violet.opacity(0.40)],
                                      startPoint: .topLeading, endPoint: .bottomTrailing))
            if !reduceTransparency {
                ZStack {
                    Ellipse().fill(color.opacity(0.58))
                        .frame(width: size * 0.90, height: size * 0.52)
                        .blur(radius: size * 0.19).offset(x: -size * 0.28, y: size * 0.32)
                    Ellipse().fill(GlassPalette.amber.opacity(0.42))
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
            Image(systemName: systemName).symbolRenderingMode(.monochrome)
                .font(.system(size: size * 0.51, weight: .medium))
                .foregroundStyle(.white)
                .shadow(color: color.opacity(0.85), radius: size * 0.075)
                .shadow(color: GlassPalette.deep.opacity(0.50), radius: size * 0.015, y: size * 0.025)
        }
        .frame(width: size, height: size)
        .shadow(color: color.opacity(0.15), radius: size * 0.22, y: size * 0.08)
        .shadow(color: .black.opacity(0.24), radius: size * 0.09, y: size * 0.10)
        .frame(width: size * 1.25, height: size * 1.25)
        .accessibilityHidden(true)
    }
}

