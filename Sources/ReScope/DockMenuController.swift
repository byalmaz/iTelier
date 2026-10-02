import AppKit
import ReScopeCore

@MainActor
final class DockMenuController: NSObject {
    static let shared = DockMenuController()
    weak var model: AppModel?

    func menu() -> NSMenu? {
        guard let model else { return nil }
        let menu = NSMenu(); menu.autoenablesItems = false
        if model.devices.isEmpty {
            add(L("En attente d’un appareil"), to: menu, enabled: false)
        } else {
            for device in model.devices {
                let title = "\(device.name) · \(device.family.systemName) \(device.osVersion ?? "—")"
                let item = add(title, to: menu, action: #selector(selectDevice(_:)), enabled: !model.isRestoring && !model.isBackupBusy)
                item.representedObject = device.id
                item.state = device.id == model.selectedDeviceID ? .on : .off
                item.image = NSImage(systemSymbolName: device.symbolName, accessibilityDescription: nil)
            }
        }
        menu.addItem(.separator())
        if model.isDownloadingFirmware {
            add(model.isDownloadPaused ? L("Téléchargement en pause") : model.isInspecting ? L("Vérification de l’IPSW") : L("Téléchargement depuis Apple"), to: menu, enabled: false)
            if let fraction = model.downloadFraction, !model.isInspecting { add("\(Int(fraction * 100)) %", to: menu, enabled: false) }
            add(model.isDownloadPaused ? L("Reprendre") : L("Pause"), to: menu, action: #selector(toggleDownload), enabled: !model.isInspecting && !model.isCancellingFirmware)
            add(L("Annuler"), to: menu, action: #selector(cancelDownload), enabled: !model.isCancellingFirmware)
            menu.addItem(.separator())
        }
        if model.isRestoring {
            let mode = model.activeRestoreMode ?? model.restoreMode
            add(mode == .preserveData ? L("Conservation des données") : L("Effacement complet"), to: menu, enabled: false)
            add(model.restorePhase, to: menu, enabled: false)
            if let fraction = model.restoreProgress { add("\(Int(fraction * 100)) %", to: menu, enabled: false) }
            let pause = add(L("Pause indisponible pendant la restauration"), to: menu, enabled: false)
            pause.toolTip = L("L’écriture du firmware doit se poursuivre sans interruption.")
            menu.addItem(.separator())
        }
        for page in WorkspacePage.allCases {
            let item = add(page.title, to: menu, action: #selector(navigate(_:)))
            item.representedObject = page.rawValue
            item.image = NSImage(systemSymbolName: page.symbol, accessibilityDescription: nil)
        }
        menu.addItem(.separator())
        add(L("Actualiser les appareils"), to: menu, action: #selector(refresh), enabled: model.canRefreshDevices)
        add(L("Configuration…"), to: menu, action: #selector(settings))
        return menu
    }
    @discardableResult private func add(_ title: String, to menu: NSMenu, action: Selector? = nil, enabled: Bool = true) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self; item.isEnabled = enabled && action != nil
        menu.addItem(item); return item
    }
    private func reveal() {
        NSApp.activate(ignoringOtherApps: true)
        for window in NSApp.windows where window.canBecomeMain {
            if window.isMiniaturized { window.deminiaturize(nil) }
            window.makeKeyAndOrderFront(nil)
        }
    }
    @objc private func navigate(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let page = WorkspacePage(rawValue: raw) else { return }
        model?.page = page; reveal()
    }
    @objc private func selectDevice(_ sender: NSMenuItem) {
        guard let model, !model.isRestoring, !model.isBackupBusy, let id = sender.representedObject as? String else { return }
        model.selectDevice(id); reveal()
    }
    @objc private func toggleDownload() { model?.toggleDownloadPause() }
    @objc private func cancelDownload() { model?.cancelFirmwareDownload() }
    @objc private func settings() { model?.showSettings = true; reveal() }
    @objc private func refresh() { Task { await model?.refresh() } }
}
