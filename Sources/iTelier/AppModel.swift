import AppKit
import Combine
import Foundation
import iTelierCore
import UniformTypeIdentifiers

enum WorkspacePage: String, CaseIterable, Identifiable {
    case overview, restore, backups, check, activity
    var id: String { rawValue }
    var title: String {
        switch self {
        case .overview: return L("Vue d’ensemble")
        case .restore: return L("Restaurer")
        case .backups: return L("Sauvegardes")
        case .check: return L("Vérification")
        case .activity: return L("Activité")
        }
    }
    var symbol: String {
        switch self {
        case .overview: return "square.grid.2x2"
        case .restore: return "arrow.triangle.2.circlepath"
        case .backups: return "externaldrive.badge.timemachine"
        case .check: return "checkmark.shield"
        case .activity: return "clock.arrow.circlepath"
        }
    }
    var subtitle: String {
        switch self {
        case .overview: return L("Vos appareils Apple, à portée de main.")
        case .restore: return L("Choisissez une version, ou utilisez votre fichier IPSW.")
        case .backups: return L("Vos données à l’abri, sur votre Mac.")
        case .check: return L("Des données lisibles. Des limites transparentes.")
        case .activity: return L("Le fil de vos opérations, conservé pendant cette session.")
        }
    }
}

struct ActivityEntry: Identifiable {
    let id = UUID()
    let date = Date()
    let title: String
    let message: String
    let symbol: String
}

@MainActor
final class AppModel: ObservableObject {
    @Published var appearance: AppAppearance = AppAppearance(rawValue: UserDefaults.standard.string(forKey: "appearance") ?? "") ?? .dark {
        didSet { UserDefaults.standard.set(appearance.rawValue, forKey: "appearance"); applyAppearance() }
    }
    @Published var language: AppLanguage = AppLanguage(rawValue: UserDefaults.standard.string(forKey: "appLanguage") ?? "") ?? .french {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: "appLanguage"); UserDefaults.standard.set([language.rawValue], forKey: "AppleLanguages") }
    }
    @Published var showOnboarding = false
    @Published var backups: [LocalBackup] = []
    @Published var isBackupBusy = false
    @Published var isLoadingBackups = false
    @Published var isReadingBackupEncryption = false
    @Published var backupEncryptionEnabled: Bool?
    @Published var backupLibraryError: String?
    @Published var backupPhase = ""
    @Published var backupProgress: Double?
    @Published var backupOperation: BackupOperation = .backup
    @Published var backupDirectoryPath = UserDefaults.standard.string(forKey: "backupDirectory") ?? BackupLibrary.defaultDirectory.path
    @Published var backupToRestore: LocalBackup?
    @Published var backupRestoreTarget: DeviceSnapshot?
    var backupSession: URL?
    var backupObservation: Task<Void, Never>?
    @Published var page: WorkspacePage = .overview
    @Published var devices: [DeviceSnapshot] = []
    @Published var selectedDeviceID: String?
    @Published var report: DiagnosticReport?
    @Published var checkReference: CheckReference?
    @Published var referenceError: String?
    @Published var isManagingReference = false
    @Published var firmware: FirmwareInfo?
    @Published var tools = DeviceService.toolStatus()
    @Published var isDemo = false
    @Published var isRefreshing = false
    @Published var isChecking = false
    @Published var isInspecting = false
    @Published var isRestoring = false
    @Published var activeRestoreMode: RestoreMode?
    private let dockProgress = DockProgressController()
    private var dockObservation: AnyCancellable?
    @Published var restorationComplete = false
    @Published var restorationFailed = false
    @Published var restorePhase = L("Prêt à préparer la restauration")
    @Published var restoreProgress: Double?
    @Published var logs: [String] = []
    @Published var activity: [ActivityEntry] = []
    @Published var alert: String?
    @Published var connectionIssue: DeviceConnectionIssue?
    @Published var informationDevice: DeviceSnapshot?
    @Published var deviceWallpapers: [String: Data] = [:]
    @Published var deviceClockOffsets: [String: TimeInterval] = [:]
    var wallpaperAttempts: [String: Date] = [:]
    @Published var deviceInformation: DeviceInformation?
    @Published var isReadingDeviceInformation = false
    @Published var deviceInformationError: String?
    @Published var showSettings = false
    @Published var showVisionProGuide = false
    @Published var showConfirmation = false
    @Published var confirmationDevice: DeviceSnapshot?
    @Published var confirmationFirmware: FirmwareInfo?
    @Published var revealIdentifiers = false
    @Published var backupAcknowledged = false
    @Published var appleIDAcknowledged = false
    @Published var operationAcknowledged = false
    @Published private(set) var defaultRestoreMode: RestoreMode =
        UserDefaults.standard.string(forKey: "defaultRestoreMode").flatMap(RestoreMode.init(rawValue:)) ?? .preserveData
    @Published var restoreMode: RestoreMode = .preserveData {
        didSet { if oldValue != restoreMode { resetAcknowledgements() } }
    }
    private(set) var confirmationMode: RestoreMode?
    @Published var showFirmwareBrowser = false
    @Published var catalogDevices: [FirmwareDevice] = []
    @Published var catalogReleases: [FirmwareRelease] = []
    @Published var catalogDeviceIdentifier: String?
    @Published var isLoadingCatalog = false
    @Published var catalogError: String?
    @Published var catalogWarnings: [String] = []
    @Published var isChoosingDownloadFolder = false
    @Published var catalogUpdatedAt: Date?
    @Published var isDownloadingFirmware = false
    @Published var isDownloadPaused = false
    @Published var isCancellingFirmware = false
    @Published var isCheckingExistingFirmware = false
    @Published var downloadRelease: FirmwareRelease?
    @Published var downloadBytesWritten: Int64 = 0
    @Published var downloadTotalBytes: Int64?
    @Published var downloadFraction: Double?
    @Published var downloadPhase = ""
    @Published var firmwareSourceRelease: FirmwareRelease?
    @Published var showRestorePreparation = false
    @Published var preparingCatalogRestore = false
    @Published var showSupportReport = false
    @Published var supportIncident: SupportReport?
    @Published var supportDescription = ""
    @Published var safetyStorageError: String?
    @Published var recoveryRequired = false
    @Published var interruptionNotice = false
    @Published var downloadDirectoryPath = UserDefaults.standard.string(forKey: "downloadDirectory")
        ?? FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0].appendingPathComponent("iTelier").path
    var safetyJournal: SafetyJournal?
    private var catalogRestoreTarget: String?
    private let service = DeviceService()
    private let firmwareCatalog = FirmwareCatalog()
    private let firmwareDownloader = FirmwareDownloader()
    private var refreshGeneration = 0
    private var catalogGeneration = 0
    private var catalogRequestTask: Task<FirmwareCatalogResult, Error>?
    private var downloadTask: Task<Void, Never>?
    private var downloadControl: FirmwareDownloadControl?
    private var downloadID: UUID?

    init() {
        DockMenuController.shared.model = self
        applyAppearance()
        restoreMode = defaultRestoreMode
        if CommandLine.arguments.contains("--demo") { enableDemo() }
        initializeSafety()
        resumeBackupObservation()
        dockObservation = objectWillChange.sink { [weak self] _ in
            DispatchQueue.main.async { self?.updateDockProgress() }
        }
        updateDockProgress()
    }

    private func updateDockProgress() {
        let active = isRestoring || isDownloadingFirmware || isBackupBusy
        let progress = isRestoring ? restoreProgress : isDownloadingFirmware ? (isInspecting ? nil : downloadFraction) : backupProgress
        dockProgress.update(active: active, fraction: progress, paused: isDownloadingFirmware && isDownloadPaused)
    }

    var device: DeviceSnapshot? { devices.first { $0.id == selectedDeviceID } }
    func setDefaultRestoreMode(_ mode: RestoreMode) {
        guard canChangeRestoreMode else { return }
        defaultRestoreMode = mode
        UserDefaults.standard.set(mode.rawValue, forKey: "defaultRestoreMode")
        restoreMode = mode
    }
    var currentReport: DiagnosticReport? {
        guard let report, report.device.id == device?.id else { return nil }
        if let checkReference, let compared = try? checkReference.applying(to: report, demo: isDemo) { return compared }
        return report
    }
    var busy: Bool { isReadingDeviceInformation || isReadingBackupEncryption || isBackupBusy || isRestoring || isInspecting || isChecking || isDownloadingFirmware || isChoosingDownloadFolder || isManagingReference }
    // Choosing a mode only changes local preparation. Downloading or inspecting an
    // IPSW must not lock it; the selected mode is validated again before execution.
    var canChangeRestoreMode: Bool { !isRestoring && !isBackupBusy }
    // Downloads and local IPSW analysis do not use USB. Keep discovering devices during them.
    var canRefreshDevices: Bool { !isReadingDeviceInformation && !isDemo && !isReadingBackupEncryption && !isBackupBusy && !isRestoring && !isChecking && !isRefreshing && !isManagingReference }
    var canInspect: Bool { !busy && !isRefreshing && !isDemo }
    var canRestore: Bool {
        guard let device, let firmware else { return false }
        return !device.isVisionPro && !isDemo && !busy && !isRefreshing && !recoveryRequired && safetyStorageError == nil
            && firmware.supports(device, mode: restoreMode)
            && (restoreMode == .erase || firmware.preservationIssue(for: device) == nil)
            && firmwareSourceRelease?.signed != false
            && device.ecid != nil && installed("idevicerestore")
            && backupAcknowledged && appleIDAcknowledged
    }
    var canConfirmRestore: Bool {
        guard canRestore, let device, let firmware, let confirmationDevice, let confirmationFirmware else { return false }
        return restoreMode == confirmationMode && device.id == confirmationDevice.id && device.ecid == confirmationDevice.ecid
            && device.productType == confirmationDevice.productType && device.hardwareModel == confirmationDevice.hardwareModel
            && firmware.sha256 == confirmationFirmware.sha256 && firmware.url == confirmationFirmware.url
    }
    func presentConfirmation() {
        guard canRestore else { return }
        confirmationDevice = device
        confirmationFirmware = firmware
        confirmationMode = restoreMode
        operationAcknowledged = false
        showRestorePreparation = false
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { self.showConfirmation = true }
    }
    func installed(_ name: String) -> Bool { tools.first { $0.name == name }?.isInstalled == true }

    func selectDevice(_ id: String?) {
        guard !isRestoring, !isBackupBusy else { return }
        selectedDeviceID = id
        report = nil
        checkReference = nil
        referenceError = nil
        resetAcknowledgements()
    }
    func resetAcknowledgements(clearOutcome: Bool = true) {
        showConfirmation = false
        confirmationDevice = nil
        confirmationFirmware = nil
        confirmationMode = nil
        backupAcknowledged = false
        appleIDAcknowledged = false
        operationAcknowledged = false
        if clearOutcome {
            restorationComplete = false
            restorationFailed = false
        }
    }

    func refresh(automatic: Bool = false) async {
        guard canRefreshDevices else { return }
        isRefreshing = true
        let generation = refreshGeneration
        defer { isRefreshing = false }
        tools = DeviceService.toolStatus()
        do {
            let found = try await service.discover()
            guard generation == refreshGeneration, !isDemo else { return }
            let previous = selectedDeviceID
            devices = found
            if showConfirmation, let confirmationDevice,
               !found.contains(where: { $0.id == confirmationDevice.id && $0.ecid == confirmationDevice.ecid
                   && $0.productType == confirmationDevice.productType && $0.hardwareModel == confirmationDevice.hardwareModel }) {
                resetAcknowledgements(clearOutcome: false)
                alert = L("L’appareil a changé ou a été déconnecté. Vérifiez la cible et confirmez à nouveau la restauration.")
            }
            if !found.contains(where: { $0.id == previous }) {
                selectedDeviceID = found.first?.id
                report = nil
                resetAcknowledgements(clearOutcome: false)
            }
            connectionIssue = found.isEmpty ? DeviceConnectionIssue.inspect() : nil
            for snapshot in found {
                if let seconds = snapshot.values["TimeIntervalSince1970"].flatMap(Double.init), seconds.isFinite, seconds > 0 {
                    deviceClockOffsets[snapshot.id] = seconds - Date().timeIntervalSince1970
                }
            }
            // Retain images only for currently connected devices, in memory, never in reports or on disk.
            let connectedIDs = Set(found.map(\.id))
            deviceWallpapers = deviceWallpapers.filter { connectedIDs.contains($0.key) }
            wallpaperAttempts = wallpaperAttempts.filter { connectedIDs.contains($0.key) }
            deviceClockOffsets = deviceClockOffsets.filter { connectedIDs.contains($0.key) }
            if let target = device, target.mode == .normal,
               !automatic || (wallpaperAttempts[target.id].map({ Date().timeIntervalSince($0) > 60 }) ?? true) {
                wallpaperAttempts[target.id] = Date()
                let data = try? await service.wallpaper(target)
                guard generation == refreshGeneration, !isDemo else { return }
                deviceWallpapers[target.id] = data
            }
        } catch {
            guard generation == refreshGeneration, !isDemo else { return }
            if showConfirmation {
                resetAcknowledgements(clearOutcome: false)
                alert = L("La connexion avec l’appareil a été interrompue. Vérifiez la cible avant de confirmer à nouveau.")
            }
            devices = []
            selectedDeviceID = nil
            deviceWallpapers = [:]
            wallpaperAttempts = [:]
            deviceClockOffsets = [:]
            report = nil
            connectionIssue = DeviceConnectionIssue.inspect(error: error)
        }
    }

    func runCheck() async {
        guard let requestedDevice = device, !busy else { return }
        page = .check
        if isDemo {
            report = Self.demoReport(requestedDevice)
            loadCheckReference()
            return
        }
        guard requestedDevice.mode == .normal else {
            alert = L("La vérification nécessite un appareil démarré normalement, déverrouillé et approuvé sur ce Mac.")
            return
        }
        isChecking = true
        track(.deviceCheck, phase: L("Lecture des informations de l’appareil"))
        defer { isChecking = false; finishTracking() }
        do {
            // Reserve the Check before waiting, so the next automatic refresh cannot
            // start another USB read. A click during discovery must not be discarded.
            while isRefreshing {
                try await Task.sleep(nanoseconds: 100_000_000)
            }
            try Task.checkCancellation()
            guard let current = device, current.id == requestedDevice.id,
                  current.ecid == requestedDevice.ecid,
                  current.productType == requestedDevice.productType,
                  current.mode == .normal else {
                throw DeviceServiceError.invalidData(L("L’appareil a changé ou a été déconnecté pendant l’actualisation. Vérifiez la connexion et relancez le Check."))
            }
            report = try await service.diagnose(current)
            loadCheckReference()
            addActivity(L("Vérification terminée"), L("Le rapport indique les données accessibles et les contrôles indisponibles."), symbol: "checkmark.shield")
        } catch is CancellationError {
            return
        } catch {
            reportFailure(error)
            addActivity(L("Lecture interrompue"), error.localizedDescription, symbol: "exclamationmark.triangle")
        }
    }

    func chooseFirmware() {
        guard canInspect else { return }
        let panel = NSOpenPanel()
        panel.title = L("Choisir un firmware IPSW")
        panel.prompt = L("Analyser l’IPSW")
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [UTType(filenameExtension: "ipsw") ?? .data]
        if panel.runModal() == .OK, let url = panel.url {
            Task { await inspectFirmware(url) }
        }
    }

    func inspectFirmware(_ url: URL) async {
        guard canInspect else { return }
        isInspecting = true
        track(.firmwareInspection, phase: L("Vérification d’un fichier IPSW local"))
        firmware = nil
        firmwareSourceRelease = nil
        resetAcknowledgements()
        defer { isInspecting = false; finishTracking() }
        do {
            firmware = try await service.inspectIPSW(at: url)
            addActivity(L("IPSW analysé"), L("\(url.lastPathComponent) · manifeste et SHA-256 lus."), symbol: "doc.badge.gearshape")
        } catch {
            reportFailure(error)
        }
    }

    func openFirmwareBrowser() {
        guard !busy, !showSettings, !showConfirmation else { return }
        page = .restore
        showFirmwareBrowser = true
        if isLoadingCatalog { return }
        if catalogDevices.isEmpty {
            Task { await loadCatalogDevices() }
        } else if let product = device?.productType, catalogDeviceIdentifier != product,
                  catalogDevices.contains(where: { $0.identifier == product }) {
            Task { await selectCatalogDevice(product) }
        } else if catalogReleases.isEmpty, catalogDeviceIdentifier != nil {
            Task { await refreshCatalog() }
        }
    }

    func loadCatalogDevices() async {
        catalogGeneration += 1
        let generation = catalogGeneration
        isLoadingCatalog = true
        catalogError = nil
        defer { if generation == catalogGeneration { isLoadingCatalog = false } }
        do {
            let result = try await firmwareCatalog.devices()
            guard generation == catalogGeneration else { return }
            catalogDevices = result
            let preferred = device?.productType ?? catalogDeviceIdentifier
            if let preferred, result.contains(where: { $0.identifier == preferred }) {
                await selectCatalogDevice(preferred)
            }
        } catch {
            guard generation == catalogGeneration else { return }
            catalogError = error.localizedDescription
        }
    }

    func clearCatalogSelection() {
        catalogRequestTask?.cancel()
        catalogRequestTask = nil
        catalogGeneration += 1
        catalogDeviceIdentifier = nil
        catalogReleases = []
        catalogWarnings = []
        catalogUpdatedAt = nil
        catalogError = nil
        isLoadingCatalog = false
    }

    func selectCatalogDevice(_ identifier: String) async {
        catalogRequestTask?.cancel()
        catalogGeneration += 1
        let generation = catalogGeneration
        catalogDeviceIdentifier = identifier
        catalogReleases = []
        catalogWarnings = []
        catalogUpdatedAt = nil
        catalogError = nil
        isLoadingCatalog = true
        defer {
            if generation == catalogGeneration {
                isLoadingCatalog = false
                catalogRequestTask = nil
            }
        }
        do {
            let catalog = firmwareCatalog
            let request = Task { try await catalog.catalog(for: identifier) }
            catalogRequestTask = request
            let result = try await request.value
            guard generation == catalogGeneration else { return }
            catalogReleases = result.releases
            catalogWarnings = result.warnings
            catalogUpdatedAt = Date()
        } catch {
            guard generation == catalogGeneration else { return }
            catalogError = error.localizedDescription
        }
    }

    func refreshCatalog() async {
        if catalogDevices.isEmpty || catalogDeviceIdentifier == nil { await loadCatalogDevices() }
        else if let identifier = catalogDeviceIdentifier { await selectCatalogDevice(identifier) }
    }

    func canPrepareRestore(_ release: FirmwareRelease) -> Bool {
        DeviceFamily(identifier: release.identifier) != .visionPro && !isDemo && !busy && !isRefreshing && !recoveryRequired && safetyStorageError == nil && release.signed
            && device?.productType == release.identifier && device?.ecid != nil
    }

    func startFirmwareDownload(_ release: FirmwareRelease, prepareRestore: Bool = false) {
        guard !busy, !isLoadingCatalog, release.identifier == catalogDeviceIdentifier,
              catalogReleases.contains(release), !prepareRestore || canPrepareRestore(release) else { return }
        do {
            let directory = URL(fileURLWithPath: downloadDirectoryPath, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            preparingCatalogRestore = prepareRestore
            catalogRestoreTarget = prepareRestore ? device?.id : nil
            beginFirmwareDownload(release, directory: directory)
        } catch { reportFailure(error) }
    }

    private func beginFirmwareDownload(_ release: FirmwareRelease, directory: URL) {
        let id = UUID()
        downloadID = id
        showFirmwareBrowser = false
        page = .restore
        isDownloadingFirmware = true
        isCheckingExistingFirmware = true
        isInspecting = true
        isDownloadPaused = false
        isCancellingFirmware = false
        downloadControl = FirmwareDownloadControl()
        downloadRelease = release
        downloadBytesWritten = 0
        downloadTotalBytes = release.fileSize > 0 ? release.fileSize : nil
        downloadFraction = 0
        downloadPhase = L("Recherche d’un IPSW déjà téléchargé")
        track(.firmwareInspection, phase: downloadPhase)
        firmware = nil
        firmwareSourceRelease = nil
        resetAcknowledgements()
        downloadTask = Task { await performFirmwareDownload(release, directory: directory, id: id) }
    }

    func cancelFirmwareDownload() {
        guard isDownloadingFirmware, !isCancellingFirmware else { return }
        isCancellingFirmware = true
        downloadPhase = L("Annulation…")
        downloadTask?.cancel()
    }

    func toggleDownloadPause() {
        guard isDownloadingFirmware, !isInspecting, !isCancellingFirmware,
              downloadControl?.setPaused(!isDownloadPaused) == true else { return }
        isDownloadPaused.toggle()
        downloadPhase = isDownloadPaused ? L("Téléchargement en pause")
            : preparingCatalogRestore ? L("Téléchargement avant restauration") : L("Téléchargement depuis Apple")
        track(.firmwareDownload, phase: downloadPhase)
    }

    private func performFirmwareDownload(_ release: FirmwareRelease, directory: URL, id: UUID) async {
        let scoped = directory.startAccessingSecurityScopedResource()
        var completedDownload: URL?
        var readyForPreparation = false
        defer {
            if scoped { directory.stopAccessingSecurityScopedResource() }
            if downloadID == id {
                isDownloadingFirmware = false
                isCheckingExistingFirmware = false
                isDownloadPaused = false
                isCancellingFirmware = false
                downloadControl = nil
                isInspecting = false
                downloadTask = nil
                downloadID = nil
            }
            finishTracking()
            if readyForPreparation { showRestorePreparation = true }
            preparingCatalogRestore = false
            catalogRestoreTarget = nil
        }
        do {
            let inspected: FirmwareInfo
            let reused: Bool
            if let existing = try await FirmwareLibrary.existingFirmware(for: release, in: directory) {
                inspected = existing
                completedDownload = existing.url
                reused = true
            } else {
                try Task.checkCancellation()
                isCheckingExistingFirmware = false
                isInspecting = false
                downloadPhase = preparingCatalogRestore ? L("Téléchargement avant restauration") : L("Téléchargement depuis Apple")
                track(.firmwareDownload, phase: downloadPhase)
                addActivity(L("Téléchargement lancé"), "\(release.identifier) · version \(release.displayVersion) · build \(release.buildID).", symbol: "arrow.down.circle")
                guard let control = downloadControl else { throw CancellationError() }
                let url = try await firmwareDownloader.download(release, to: directory, control: control,
                    onTransferCompleted: { [weak self] in
                        Task { @MainActor [weak self] in
                            guard let self, self.downloadID == id else { return }
                            self.isDownloadPaused = false
                            self.isInspecting = true
                            if !self.isCancellingFirmware { self.downloadPhase = L("Vérification de l’IPSW") }
                        }
                    }) { [weak self] progress in
                    Task { @MainActor [weak self] in
                        guard let self, self.downloadID == id, self.isDownloadingFirmware, !self.isInspecting else { return }
                        self.downloadBytesWritten = progress.bytesWritten
                        self.downloadTotalBytes = progress.totalBytes
                        self.downloadFraction = progress.fraction
                    }
                }
                completedDownload = url
                try Task.checkCancellation()
                downloadPhase = L("Vérification du manifeste et du SHA-256")
                track(.firmwareInspection, phase: downloadPhase)
                isInspecting = true
                inspected = try await service.inspectIPSW(at: url)
                reused = false
            }
            try Task.checkCancellation()
            guard inspected.version == release.version, inspected.build == release.buildID,
                  inspected.supportedProductTypes.contains(release.identifier) else {
                throw DeviceServiceError.invalidData(L("Le contenu de l’IPSW ne correspond pas à la version choisie. Il ne sera pas proposé pour la restauration."))
            }
            firmware = inspected
            firmwareSourceRelease = release
            downloadPhase = reused ? L("IPSW local vérifié et réutilisé") : L("IPSW téléchargé et vérifié")
            downloadFraction = 1
            if preparingCatalogRestore {
                if device?.id == catalogRestoreTarget && device?.productType == release.identifier {
                    readyForPreparation = true
                } else {
                    alert = L("L’appareil sélectionné a changé pendant le téléchargement. Sélectionnez la bonne cible avant de préparer la restauration.")
                }
            }
            addActivity(reused ? L("IPSW existant réutilisé") : L("IPSW téléchargé"),
                L("Version \(release.displayVersion) · build \(release.buildID) · manifeste et intégrité vérifiés. \(reused ? L("Aucun nouveau téléchargement. ") : "")Aucune restauration lancée."), symbol: "checkmark.circle")
        } catch is CancellationError {
            downloadPhase = L("Téléchargement annulé")
            addActivity(L("Téléchargement annulé"), L("Aucune restauration lancée."), symbol: "xmark.circle")
        } catch {
            if Task.isCancelled {
                downloadPhase = L("Téléchargement annulé")
                addActivity(L("Téléchargement annulé"), L("Aucune restauration lancée."), symbol: "xmark.circle")
            } else {
                downloadPhase = completedDownload == nil ? L("Le téléchargement n’a pas abouti") : L("L’IPSW n’a pas pu être validé")
                reportFailure(error)
                addActivity(completedDownload == nil ? L("Échec du téléchargement") : L("Validation du firmware interrompue"), error.localizedDescription, symbol: "exclamationmark.triangle")
            }
        }
    }

    func beginRestore() async {
        guard canConfirmRestore, operationAcknowledged, let device = confirmationDevice, let firmware = confirmationFirmware else { return }
        guard track(.restoration, phase: L("Préparation de la restauration")) else { return }
        showConfirmation = false
        activeRestoreMode = restoreMode
        isRestoring = true
        AppDelegate.restorationActive = true
        NSApp.windows.forEach { $0.standardWindowButton(.closeButton)?.isEnabled = false }
        restoreProgress = nil
        restorePhase = L("Validation de l’appareil et du firmware")
        logs = []
        restorationComplete = false
        restorationFailed = false
        let approval = RestoreApproval(deviceID: device.id, firmwareSHA256: firmware.sha256,
            acknowledgedDataLoss: restoreMode == .erase, mode: restoreMode,
            acknowledgedPreservationRisk: restoreMode == .preserveData)
        addActivity(L("Restauration lancée"), "\(restoreMode.title) · \(device.productType) · iOS/iPadOS \(firmware.version).", symbol: "arrow.triangle.2.circlepath")
        defer {
            isRestoring = false
            AppDelegate.restorationActive = false
            NSApp.windows.forEach { $0.standardWindowButton(.closeButton)?.isEnabled = true }
            resetAcknowledgementsAfterRestore()
            finishTracking()
        }
        do {
            try await service.restore(device: device, firmware: firmware, approval: approval) { [weak self] event in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    switch event {
                    case .log(let line):
                        self.logs.append(line)
                        if self.logs.count > 4000 { self.logs.removeFirst(self.logs.count - 4000) }
                    case .phase(let phase): if self.isRestoring {
                        self.restorePhase = phase
                        self.track(.restoration, phase: phase)
                    }
                    case .progress(let progress): if self.isRestoring { self.restoreProgress = progress }
                    case .finished: break
                    }
                }
            }
            restorationComplete = true
            acknowledgeRecovery()
            restorePhase = L("Installation du système terminée")
            restoreProgress = 1
            report = nil
            addActivity(L("Installation du système terminée"), L("La fin de l’installation est confirmée. L’appareil peut encore terminer son démarrage."), symbol: "checkmark.circle")
        } catch {
            restorationFailed = true
            recoveryRequired = true
            restorePhase = L("La restauration n’a pas abouti")
            restoreProgress = nil
            reportFailure(error)
            logs.append(error.localizedDescription)
            addActivity(L("Échec de restauration"), error.localizedDescription, symbol: "exclamationmark.triangle")
        }
    }
    private func resetAcknowledgementsAfterRestore() {
        backupAcknowledged = false
        appleIDAcknowledged = false
        operationAcknowledged = false
    }

    func toggleDemo() {
        guard !busy else { return }
        refreshGeneration += 1
        if isDemo {
            isDemo = false
            devices = []
            selectedDeviceID = nil
            report = nil
            firmware = nil
            firmwareSourceRelease = nil
            activity = []
            logs = []
            resetAcknowledgements()
            Task { await refresh() }
        } else {
            enableDemo()
        }
    }
    private func enableDemo() {
        isDemo = true
        checkReference = nil
        referenceError = nil
        connectionIssue = nil
        firmware = nil
        firmwareSourceRelease = nil
        logs = []
        resetAcknowledgements()
        let sample = DeviceSnapshot(
            id: "DEMO-00000000", name: "iPhone 15 Pro", productType: "iPhone16,1",
            osVersion: "18.7", buildVersion: L("Exemple"), serialNumber: "DEMO12345678",
            ecid: "0x1234", hardwareModel: "d83ap", mode: .normal, values: [:]
        )
        devices = [sample]
        selectedDeviceID = sample.id
        report = Self.demoReport(sample)
        loadCheckReference()
        activity = []
        addActivity(L("Aperçu de l’interface"), L("Données fictives. Les opérations sur les appareils sont désactivées."), symbol: "sparkles")
    }
    static func demoReport(_ device: DeviceSnapshot) -> DiagnosticReport {
        let items: [CheckItem] = [
            .init(id: "model", title: L("Modèle"), category: .identity, expected: nil, actual: "iPhone16,1", status: .read, detail: L("Exemple de valeur retournée par ideviceinfo. Sans référence d’usine."), sensitive: false),
            .init(id: "ios", title: L("Version iOS"), category: .identity, expected: nil, actual: "18.7", status: .read, detail: L("Version illustrative. Aucune vérification de signature effectuée."), sensitive: false),
            .init(id: "serial", title: L("Numéro de série"), category: .identity, expected: nil, actual: "DEMO12345678", status: .read, detail: L("Identifiant fictif, masqué par défaut."), sensitive: true),
            .init(id: "ecid", title: "ECID", category: .identity, expected: nil, actual: "0x1234", status: .read, detail: L("Identifiant fictif utilisé uniquement pour cet aperçu."), sensitive: true),
            .init(id: "battery-charge", title: L("Niveau de charge"), category: .battery, expected: nil, actual: "62 %", status: .read, detail: L("La charge actuelle est distincte de la santé de la batterie."), sensitive: false),
            .init(id: "battery-health", title: L("Capacité estimée"), category: .battery, expected: nil, actual: "78 %", status: .attention, detail: L("Exemple d’estimation inférieure à 80 %. Ce résultat invite à examiner la batterie; il ne certifie pas l’origine de la pièce."), sensitive: false),
            .init(id: "battery-cycles", title: L("Cycles de charge"), category: .battery, expected: nil, actual: "310", status: .read, detail: L("Exemple de compteur de cycles communiqué par l’appareil."), sensitive: false),
            .init(id: "battery-serial", title: L("Origine de la batterie"), category: .components, expected: nil, actual: nil, status: .unavailable, detail: L("Aucune référence d’usine indépendante. Une série lue ne prouve pas l’authenticité."), sensitive: false),
            .init(id: "screen", title: L("Écran et caméras"), category: .components, expected: nil, actual: nil, status: .manual, detail: L("Consultez Réglages → Général → Informations → Historique des pièces et des réparations, si disponible."), sensitive: false),
            .init(id: "faceid", title: L("Face ID / Touch ID"), category: .components, expected: nil, actual: nil, status: .manual, detail: L("Testez le déverrouillage biométrique directement sur l’appareil."), sensitive: false),
            .init(id: "wifi", title: L("Adresse Wi-Fi"), category: .connectivity, expected: nil, actual: "02:00:00:DE:00:01", status: .read, detail: L("Adresse fictive. Sa lecture ne teste pas la qualité du réseau."), sensitive: true),
            .init(id: "activation", title: L("État d’activation"), category: .security, expected: nil, actual: L("Activé"), status: .read, detail: L("L’état d’activation actuel ne permet pas de conclure sur le verrouillage d’activation."), sensitive: false),
            .init(id: "activation-lock", title: L("Verrouillage d’activation"), category: .security, expected: nil, actual: nil, status: .manual, detail: L("Vérifiez Localiser dans les réglages et préparez les identifiants Apple du propriétaire avant une restauration."), sensitive: false)
        ]
        return DiagnosticReport(date: Date(), device: device, items: items)
    }
    func addActivity(_ title: String, _ message: String, symbol: String) {
        activity.insert(ActivityEntry(title: title, message: message, symbol: symbol), at: 0)
    }
    func visible(_ value: String?, sensitive: Bool = false) -> String {
        guard let value, !value.isEmpty else { return L("Indisponible") }
        return sensitive && !revealIdentifiers ? "••••••••" : value
    }
    func checkValue(_ item: CheckItem) -> String {
        if item.actual != nil { return visible(item.actual, sensitive: item.sensitive) }
        switch item.status {
        case .readFailed: return L("Lecture échouée")
        case .unsupported: return L("Non pris en charge")
        case .manual: return L("Sur l’appareil")
        case .attention: return L("Valeurs divergentes")
        default: return L("Non exposé")
        }
    }
    func sanitizedLog(_ text: String) -> String {
        guard !revealIdentifiers else { return text }
        var result = text
        let snapshots = devices + (report.map { [$0.device] } ?? [])
        for snapshot in snapshots {
            let identifiers = [snapshot.id, snapshot.serialNumber, snapshot.ecid, snapshot.name]
                .compactMap { $0 }.filter { !$0.isEmpty && $0.count >= 4 }
            for identifier in identifiers { result = result.replacingOccurrences(of: identifier, with: L("[masqué]")) }
        }
        for item in report?.items ?? [] where item.sensitive {
            if let value = item.actual, value.count >= 4 { result = result.replacingOccurrences(of: value, with: L("[masqué]")) }
        }
        // Les chemins locaux et identifiants imprévus ne sont pas exportés dans le rapport.
        return result
    }
    func exportReport() {
        guard let report = currentReport else { return }
        let panel = NSSavePanel()
        panel.title = revealIdentifiers ? L("Exporter avec les identifiants") : L("Exporter le rapport masqué")
        panel.nameFieldStringValue = "iTelier-\(isDemo ? "exemple-" : "")rapport.json"
        panel.allowedContentTypes = [.json]
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let deviceInfo: [String: Any] = [
            "productType": report.device.productType,
            "osVersion": report.device.osVersion ?? NSNull() as Any,
            "mode": report.device.mode.rawValue,
            "serialNumber": revealIdentifiers ? (report.device.serialNumber ?? L("Indisponible")) : L("Masqué"),
            "ecid": revealIdentifiers ? (report.device.ecid ?? L("Indisponible")) : L("Masqué")
        ]
        let rows: [[String: Any]] = report.items.map { item in
            [
                "id": item.id, "element": item.title, "category": item.category.rawValue, "status": item.status.rawValue,
                "value": item.sensitive && !revealIdentifiers ? L("Masqué") : (item.actual ?? NSNull() as Any),
                "reference": item.sensitive && !revealIdentifiers ? L("Masqué") : (item.expected ?? NSNull() as Any),
                "method": item.detail, "source": item.source ?? NSNull() as Any,
                "comparison": item.referenceMatch?.rawValue ?? NSNull() as Any
            ]
        }
        let referenceMetadata: Any = checkReference.map { reference -> Any in
            ["origin": reference.origin.rawValue, "date": ISO8601DateFormatter().string(from: reference.date),
             "factoryVerified": false] as [String: Any]
        } ?? NSNull()
        let payload: [String: Any] = [
            "application": "iTelier", "schemaVersion": 3, "demo": isDemo,
            "comparisonReference": referenceMetadata,
            "sources": (report.sources ?? []).map { ["id": $0.id, "title": $0.title, "status": $0.status.rawValue, "detail": $0.detail] },
            "date": ISO8601DateFormatter().string(from: report.date),
            "identifiersIncluded": revealIdentifiers, "device": deviceInfo, "checks": rows,
            "scope": L("Lecture locale. Les contrôles indisponibles ne valent pas validation. Aucune certification d’authenticité.")
        ]
        do {
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
            try data.write(to: url, options: .atomic)
            addActivity(L("Rapport exporté"), revealIdentifiers ? L("L’export inclut les identifiants affichés.") : L("Les identifiants sont masqués dans l’export."), symbol: "square.and.arrow.up")
        } catch { alert = error.localizedDescription }
    }
}
