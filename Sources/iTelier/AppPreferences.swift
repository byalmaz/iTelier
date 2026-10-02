import iTelierCore
import AppKit
import SwiftUI

enum AppAppearance: String, CaseIterable, Identifiable {
    case dark, light, system
    var id: String { rawValue }
    var title: String { switch self { case .dark: return L("Sombre"); case .light: return L("Clair"); case .system: return L("Système") } }
    var colorScheme: ColorScheme? { switch self { case .dark: return .dark; case .light: return .light; case .system: return nil } }
}
enum AppLanguage: String, CaseIterable, Identifiable {
    case french = "fr", english = "en"
    var id: String { rawValue }
    var title: String { self == .french ? "Français" : "English" }
    var locale: Locale { Locale(identifier: rawValue) }
}
extension AppModel {
    func applyAppearance() {
        switch appearance {
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        case .system: NSApp.appearance = nil
        }
    }
    func offerOnboardingIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: "onboardingCompleted"), !busy,
              !recoveryRequired, !interruptionNotice, !showSettings, !showConfirmation else { return }
        showOnboarding = true
    }
    func finishOnboarding() {
        UserDefaults.standard.set(true, forKey: "onboardingCompleted")
        showOnboarding = false
    }
}
