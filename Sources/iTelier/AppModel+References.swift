import AppKit
import iTelierCore

extension AppModel {
    private var referenceStore: CheckReferenceStore {
        CheckReferenceStore(directory: FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("iTelier/References", isDirectory: true))
    }

    func loadCheckReference() {
        checkReference = nil
        referenceError = nil
        guard let report else { return }
        do { checkReference = try referenceStore.load(for: report.device, demo: isDemo) }
        catch { referenceError = L("Référence non chargée : ") + UserFacingError.presentation(for: error, operation: .deviceCheck).message }
    }

    func saveCheckReference() {
        guard let report, !busy else { return }
        do {
            let reference = try CheckReference.capture(report, demo: isDemo)
            try referenceStore.save(reference, for: report.device, demo: isDemo)
            checkReference = reference
            referenceError = nil
            addActivity(L("Référence enregistrée"), L("Ce Check servira de relevé de comparaison pour cet appareil. Il ne constitue pas une référence d’usine."), symbol: "doc.badge.clock")
        } catch { referenceError = UserFacingError.presentation(for: error, operation: .deviceCheck).message }
    }

    func importCheckReference() {
        guard let report, !busy else { return }
        isManagingReference = true
        defer { isManagingReference = false }
        let panel = NSOpenPanel()
        panel.title = L("Importer un rapport iTelier comme référence")
        panel.message = L("Choisissez un rapport JSON du même appareil, exporté avec les numéros de série visibles.")
        panel.prompt = L("Utiliser comme référence")
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        do {
            let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
            guard size <= 1_048_576 else { throw ReferenceError.invalidFile }
            let reference = try CheckReference.importReport(Data(contentsOf: url), for: report, demo: isDemo)
            try referenceStore.save(reference, for: report.device, demo: isDemo)
            checkReference = reference
            referenceError = nil
            addActivity(L("Référence importée"), L("Un rapport du même appareil a été chargé pour la comparaison. Son origine d’usine n’est pas certifiée."), symbol: "doc.badge.arrow.up")
        } catch { referenceError = UserFacingError.presentation(for: error, operation: .deviceCheck).message }
    }
}
