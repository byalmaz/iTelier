import AppKit
import SwiftUI
import iTelierCore

@main
struct iTelierApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var startup = AppStartup()
    var body: some Scene {
        WindowGroup {
            Group {
            if let model = startup.model {
            WorkspaceView()
                .environmentObject(model)
                .preferredColorScheme(model.appearance.colorScheme)
                .environment(\.locale, model.language.locale)
                .frame(minWidth: 1060, minHeight: 740)
                .onAppear { NSApp.setActivationPolicy(.regular) }
            } else {
                ProgressView(L("Ouverture d’iTelier…"))
                    .frame(minWidth: 1060, minHeight: 740)
            }
            }
            .task { await startup.prepare() }
        }
        .defaultSize(width: 1180, height: 810)
        .windowStyle(.hiddenTitleBar)
        .commands {
            if let model = startup.model {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button(L("Configuration…")) { model.showSettings = true }
                    .keyboardShortcut(",", modifiers: .command)
            }
            CommandMenu(L("Appareil")) {
                Button(L("Actualiser")) { Task { await model.refresh() } }
                    .keyboardShortcut("r", modifiers: .command)
                    .disabled(!model.canRefreshDevices)
                Button(L("Vérifier l’appareil")) { Task { await model.runCheck() } }
                    .keyboardShortcut("k", modifiers: .command)
                    .disabled(model.device == nil || model.busy)
                Button(L("Choisir un IPSW…")) { model.page = .restore; model.chooseFirmware() }
                    .keyboardShortcut("o", modifiers: .command)
                    .disabled(!model.canInspect)
                Button(L("Choisir une version…")) { model.openFirmwareBrowser() }
                    .keyboardShortcut("o", modifiers: [.command, .shift])
                    .disabled(model.busy || model.showSettings || model.showConfirmation)
                Divider()
                ForEach(Array(WorkspacePage.allCases.enumerated()), id: \.element.id) { index, page in
                    Button(page.title) { model.page = page }
                        .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                }
            }
            }
        }
    }
}

@MainActor
private final class AppStartup: ObservableObject {
    @Published var model: AppModel?
    private var started = false

    func prepare() async {
        guard !started else { return }
        started = true
        do {
            try await Task.detached { try LegacyAppMigration.prepare() }.value
            model = AppModel()
        } catch {
            let alert = NSAlert()
            alert.messageText = L("Vos données locales n’ont pas pu être déplacées.")
            alert.informativeText = error.localizedDescription + "\n\n" + L("Fermez l’ancienne version, puis rouvrez iTelier. Vos données restent conservées.")
            alert.runModal()
            exit(EXIT_FAILURE)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static var restorationActive = false
    static var backupActive = false
    static var onCleanExit: (() -> Void)?
    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? { DockMenuController.shared.menu() }
    func applicationWillTerminate(_ notification: Notification) { Self.onCleanExit?() }
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)
    }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Le moteur ne doit pas être arrêté au milieu d’une écriture.
        if Self.restorationActive || Self.backupActive || RestoreHost.isRunning || BackupHost.isRunning {
            let alert = NSAlert()
            alert.messageText = L("Une opération sur l’appareil est en cours.")
            alert.informativeText = L("Gardez iTelier ouvert et l’appareil connecté jusqu’à la fin de l’opération.")
            alert.addButton(withTitle: L("Laisser l’opération se terminer"))
            alert.runModal()
            NSApp.activate(ignoringOtherApps: true)
            for window in NSApp.windows where window.canBecomeMain { window.makeKeyAndOrderFront(nil) }
            return .terminateCancel
        }
        return .terminateNow
    }
}
