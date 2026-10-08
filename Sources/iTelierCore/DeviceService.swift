import Foundation

public struct DeviceService: Sendable {
    private let runner = ProcessRunner()
    public init() {}

    public static func toolStatus() -> [ToolStatus] {
        ToolResolver.names.map { ToolStatus(id: $0, name: $0, path: ToolResolver.resolve($0)) }
    }

    public func discover(excludingRestoreECIDs: Set<String> = []) async throws -> [DeviceSnapshot] {
        var devices: [DeviceSnapshot] = []
        var readFailure: Error?
        let activeIDs = Set(RestoreHost.sessions().compactMap { entry -> String? in
            guard let target = entry.snapshot.target, excludingRestoreECIDs.contains(target.ecid) else { return nil }
            return target.deviceID
        })
        if let tool = ToolResolver.resolve("idevice_id") {
            let listing = try await command(tool, ["-l"])
            let identifiers = String(decoding: listing.stdout, as: UTF8.self).split(whereSeparator: \.isNewline).map(String.init)
            for id in identifiers {
                try Task.checkCancellation()
                do {
                    // Une cible active n’est jamais interrogée pour le Check ou le fond.
                    if activeIDs.contains(id) { continue }
                    let device = try await readNormalDevice(id: id)
                    if !excludingRestoreECIDs.contains(device.ecid ?? "") { devices.append(device) }
                }
                catch is CancellationError { throw CancellationError() }
                catch { readFailure = error }
            }
        }
        if let tool = ToolResolver.resolve("irecovery") {
            let inventory = RecoveryUSBInventory.ecids()
            let known = Set(devices.compactMap(\.ecid)).union(excludingRestoreECIDs)
            var targets = inventory.subtracting(known).sorted().map { ["-i", $0, "-q"] }
            // Repli ancien : uniquement sans restauration active ni cible connue.
            if targets.isEmpty, inventory.isEmpty, devices.isEmpty, excludingRestoreECIDs.isEmpty, !RestoreHost.isRunning { targets = [["-q"]] }
            for arguments in targets {
                do {
                    let result = try await command(tool, arguments, timeout: 10)
                    let snapshot = try DeviceParser.recoveryDevice(String(decoding: result.stdout, as: UTF8.self))
                    guard !known.contains(snapshot.ecid ?? ""),
                          arguments.count == 1 || snapshot.ecid == arguments[1] else { continue }
                    devices.append(snapshot)
                } catch is CancellationError { throw CancellationError() }
                catch { /* Un appareil peut changer de mode entre l’inventaire et la lecture. */ }
            }
        }
        if devices.isEmpty, let readFailure { throw readFailure }
        if ToolResolver.resolve("idevice_id") == nil && ToolResolver.resolve("irecovery") == nil {
            throw DeviceServiceError.missingTool("idevice_id / irecovery")
        }
        return devices
    }

    public func wallpaper(_ device: DeviceSnapshot) async throws -> Data? {
        guard device.mode == .normal, device.productType.hasPrefix("iPhone") || device.productType.hasPrefix("iPad") else { return nil }
        let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/iTelierWallpaperHost").path
        guard FileManager.default.isExecutableFile(atPath: helper) else { return nil }
        let result = try await runner.run(executable: helper, arguments: [device.id], timeout: 12, outputLimit: 20 * 1_024 * 1_024)
        guard result.exitCode == 0, result.stdout.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]) else { return nil }
        return result.stdout
    }

    public func information(_ device: DeviceSnapshot, batteryDetails: Bool = false, storageDetails: Bool = false) async throws -> DeviceInformation {
        guard device.mode == .normal else { return DeviceInformation(device: device) }
        let current = try await readNormalDevice(id: device.id)
        guard current.productType == device.productType, current.ecid == device.ecid else {
            throw DeviceServiceError.invalidData(L("L’appareil connecté ne correspond plus à l’appareil sélectionné."))
        }
        let battery = try await diagnosticReading(id: "battery", title: L("Batterie"), tool: "ideviceinfo",
            arguments: ["-u", device.id, "-q", "com.apple.mobile.battery", "-x"])
        let disk = try await diagnosticReading(id: "disk", title: L("Stockage"), tool: "ideviceinfo",
            arguments: ["-u", device.id, "-q", "com.apple.disk_usage", "-x"])
        try Task.checkCancellation()
        var details: [DiagnosticReading] = []
        var storageValues = disk.values
        var hardware = StorageHardware()
        if storageDetails {
            let categories = try await diagnosticReading(id: "storage-categories", title: L("Répartition du stockage"), tool: "ideviceinfo",
                arguments: ["-u", device.id, "-q", "com.apple.disk_usage.factory", "-x"], timeout: 30)
            details.append(categories)
            if categories.status == .read { storageValues.merge(categories.values) { _, new in new } }
            let helper = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/iTelierWallpaperHost").path
            if FileManager.default.isExecutableFile(atPath: helper) {
                do {
                    let result = try await runner.run(executable: helper, arguments: [device.id, "--storage"], timeout: 30)
                    if result.exitCode == 0, let usage = try? JSONDecoder().decode(StorageAppUsage.self, from: result.stdout) {
                        storageValues.merge(usage.diskValues) { _, new in new }
                    }
                } catch is CancellationError { throw CancellationError() }
                catch { details.append(.failure(id: "app-sizes", title: L("Applications"), error: error)) }
            }
            do {
                guard let tool = ToolResolver.resolve("idevicediagnostics") else { throw DeviceServiceError.missingTool("idevicediagnostics") }
                let inventory = try await command(tool, ["-u", device.id, "ioreg", "IOService"], timeout: 15, outputLimit: 4 * 1_024 * 1_024)
                for name in try StorageHardware.controllerNames(inventory.stdout) {
                    try Task.checkCancellation()
                    let reading = try await diagnosticReading(id: "storage-controller", title: L("Mémoire flash"), tool: "idevicediagnostics", arguments: ["-u", device.id, "ioregentry", name])
                    details.append(reading)
                    let candidate = StorageHardware(values: reading.values)
                    if candidate.model != nil || candidate.flashName != nil { hardware = candidate; break }
                }
            } catch is CancellationError { throw CancellationError() }
            catch { details.append(.failure(id: "storage-controller", title: L("Mémoire flash"), error: error)) }
        }
        if batteryDetails {
            for (id, title, args) in [("gauge", "GasGauge", ["diagnostics", "GasGauge"]),
                                      ("registry", "AppleSmartBattery", ["ioregentry", "AppleSmartBattery"])] {
                try Task.checkCancellation()
                details.append(try await diagnosticReading(id: id, title: title, tool: "idevicediagnostics", arguments: ["-u", device.id] + args))
            }
        }
        return DeviceInformation(device: current, battery: battery.values, disk: storageValues,
            warnings: ([battery, disk] + details).filter { $0.status != .read }.map { $0.title + " : " + $0.detail },
            gauge: details.first { $0.id == "gauge" }?.values ?? [:], registry: details.first { $0.id == "registry" }?.values ?? [:], hasBatteryDetails: batteryDetails,
            storageHardware: hardware, hasStorageDetails: storageDetails)
    }

    public func diagnose(_ device: DeviceSnapshot) async throws -> DiagnosticReport {
        if device.mode != .normal {
            return DiagnosticBuilder.report(device: device)
        }
        let current = try await readNormalDevice(id: device.id)
        if let originalECID = DeviceParser.normalizedECID(device.ecid), current.ecid != originalECID {
            throw DeviceServiceError.invalidData(L("L’appareil connecté ne correspond plus à l’appareil sélectionné."))
        }
        // Serialize requests to diagnostics_relay: several simultaneous clients can cause partial failures.
        var readings: [DiagnosticReading] = []
        let requests: [(String, String, String, [String])] = [
            ("battery", L("Domaine batterie"), "ideviceinfo", ["-q", "com.apple.mobile.battery", "-x"]),
            ("disk", "Stockage", "ideviceinfo", ["-q", "com.apple.disk_usage", "-x"]),
            ("gauge", "GasGauge", "idevicediagnostics", ["diagnostics", "GasGauge"]),
            ("registry", "IORegistry · AppleSmartBattery", "idevicediagnostics", ["ioregentry", "AppleSmartBattery"]),
            ("product", "IORegistry · product", "idevicediagnostics", ["ioregentry", "product"]),
            ("gestalt", "MobileGestalt", "idevicediagnostics", ["mobilegestalt",
                "BatterySerialNumber", "MLBSerialNumber", "FrontFacingCameraModuleSerialNumber",
                "BackFacingCameraModuleSerialNumber", "ScreenSerialNumber", "CoverglassSerialNumber",
                "FrontFacingIRCameraModuleSerialNumber", "FrontFacingIRStructuredLightProjectorModuleSerialNumber"])
        ]
        for (id, title, tool, args) in requests {
            try Task.checkCancellation()
            readings.append(try await diagnosticReading(id: id, title: title, tool: tool, arguments: ["-u", device.id] + args))
        }
        var cameraNames: [String] = []
        do {
            guard let tool = ToolResolver.resolve("idevicediagnostics") else { throw DeviceServiceError.missingTool("idevicediagnostics") }
            let result = try await command(tool, ["-u", device.id, "ioreg", "IOService"], timeout: 12, outputLimit: 4 * 1_024 * 1_024)
            let reading = try DiagnosticReading.decode(id: "services", title: L("Inventaire IOService"), data: result.stdout)
            readings.append(DiagnosticReading(id: reading.id, title: reading.title, values: [:], status: reading.status, detail: reading.detail))
            if reading.status == .read { cameraNames = try DiagnosticReading.cameraEntries(result.stdout) }
        } catch is CancellationError { throw CancellationError() }
        catch { readings.append(.failure(id: "services", title: L("Inventaire IOService"), error: error)) }
        // Target the actual driver names when advertised; bounded fallback for older diagnostic servers.
        if cameraNames.isEmpty { cameraNames = ["AppleH16CamIn", "AppleH13CamIn"] }
        for name in cameraNames {
            try Task.checkCancellation()
            readings.append(try await diagnosticReading(id: "camera-" + name, title: "IORegistry · " + name,
                tool: "idevicediagnostics", arguments: ["-u", device.id, "ioregentry", name]))
        }
        return DiagnosticBuilder.report(device: current, readings: readings)
    }

    public func inspectIPSW(at url: URL) async throws -> FirmwareInfo {
        let scope = url.startAccessingSecurityScopedResource()
        defer { if scope { url.stopAccessingSecurityScopedResource() } }
        return try await FirmwareInspector.inspect(url, runner: runner)
    }

    public func restore(device: DeviceSnapshot, firmware: FirmwareInfo, approval: RestoreApproval,
                        sessionDirectory: URL? = nil,
                        onEvent: @escaping @Sendable (RestoreEvent) -> Void) async throws {
        let ecid = try RestoreValidator.validateApproval(device: device, firmware: firmware, approval: approval)
        guard let restoreTool = ToolResolver.resolve("idevicerestore") else {
            throw DeviceServiceError.missingTool("idevicerestore")
        }
        let scope = firmware.url.startAccessingSecurityScopedResource()
        defer { if scope { firmware.url.stopAccessingSecurityScopedResource() } }
        onEvent(.phase(L("Vérification du fichier IPSW")))
        let fingerprint = try FileFingerprint.read(firmware.url)
        // Re-read manifest and hash; the user-approved URL may have been replaced since selection.
        let verified = try await FirmwareInspector.inspect(firmware.url, runner: runner)
        guard verified.sha256 == approval.firmwareSHA256, verified.supports(device, mode: approval.mode) else {
            throw DeviceServiceError.unsafeRestore(L("Le fichier IPSW a changé ou sa compatibilité n’est plus vérifiable. Confirmez à nouveau la restauration."))
        }
        onEvent(.phase(L("Vérification de l’appareil connecté")))
        var candidates: [DeviceSnapshot]
        do { candidates = try await discover(excludingRestoreECIDs: RestoreHost.activeECIDs.subtracting([ecid])) }
        catch is CancellationError { throw CancellationError() }
        catch { candidates = [] }
        // Normal and Recovery devices can coexist, and a selected device may have changed modes.
        // Always target the approved ECID if it did not appear in the normal-mode enumeration.
        if !candidates.contains(where: { DeviceParser.normalizedECID($0.ecid) == ecid }),
           let recoveryTool = ToolResolver.resolve("irecovery") {
            let query = try await command(recoveryTool, ["-i", ecid, "-q"], timeout: 10)
            candidates.append(try DeviceParser.recoveryDevice(String(decoding: query.stdout, as: UTF8.self)))
        }
        let connected = try RestoreValidator.reconnectedDevice(original: device, ecid: ecid, candidates: candidates)
        guard verified.supports(connected, mode: approval.mode), try FileFingerprint.read(firmware.url) == fingerprint else {
            throw DeviceServiceError.unsafeRestore(L("Le firmware ou l’appareil a changé pendant les derniers contrôles."))
        }
        // A selected recovery device can coexist with a normal device; query the confirmed ECID directly.
        if connected.mode != .normal {
            guard let recoveryTool = ToolResolver.resolve("irecovery") else { throw DeviceServiceError.missingTool("irecovery") }
            let query = try await command(recoveryTool, ["-i", ecid, "-q"], timeout: 10)
            let targeted = try DeviceParser.recoveryDevice(String(decoding: query.stdout, as: UTF8.self))
            _ = try RestoreValidator.reconnectedDevice(original: device, ecid: ecid, candidates: [targeted])
        }
        if approval.mode == .preserveData {
            try RestoreValidator.validatePreservation(device: connected, firmware: verified, approval: approval)
            // --variant performs an exact identity match and fails instead of falling back to erase.
            let help = try await command(restoreTool, ["--help"], timeout: 10)
            let usage = String(decoding: help.stdout + help.stderr, as: UTF8.self)
            guard usage.contains("--variant") else {
                throw DeviceServiceError.unsafeRestore(L("Ce moteur est trop ancien pour imposer la conservation des données. Mettez idevicerestore à jour."))
            }
        }
        let arguments = try RestoreValidator.arguments(ecid: ecid, url: verified.url, mode: approval.mode,
                                                       upgradeVariant: verified.upgradeVariant(for: connected))
        let workDirectory = try sessionDirectory ?? restoreWorkingDirectory()
        guard workDirectory.deletingLastPathComponent().resolvingSymlinksInPath() == RestoreHost.root.resolvingSymlinksInPath(),
              UUID(uuidString: workDirectory.lastPathComponent) != nil else {
            throw DeviceServiceError.unsafeRestore(L("Le suivi ne correspond pas à l’appareil confirmé."))
        }
        onEvent(.phase(L("Dernière vérification SHA-256")))
        guard try await FirmwareInspector.sha256(verified.url) == approval.firmwareSHA256,
              try FileFingerprint.read(verified.url) == fingerprint else {
            throw DeviceServiceError.unsafeRestore(L("Le fichier IPSW a changé avant le lancement. Sélectionnez-le et confirmez à nouveau."))
        }
        try Task.checkCancellation()
        onEvent(.phase(approval.mode == .erase ? L("Démarrage de la restauration avec effacement") : L("Réinstallation avec conservation des données")))
        onEvent(.log(L("L’outil de restauration vérifie la signature Apple. La disponibilité d’un fichier IPSW ne garantit pas qu’Apple accepte encore cette version.")))
        try RestoreHost.launch(arguments: arguments, firmwareSHA256: approval.firmwareSHA256, directory: workDirectory,
                               target: RestoreTarget(device: device, firmware: verified, mode: approval.mode))
        let result = try await RestoreHost.wait(directory: workDirectory, onEvent: onEvent)
        guard result.exitCode == 0 else {
            let detail = String(decoding: result.stderr.isEmpty ? result.stdout : result.stderr, as: UTF8.self)
            throw DeviceServiceError.commandFailed("idevicerestore", result.exitCode, String(detail.suffix(2_000)))
        }
        guard let snapshot = RestoreHost.read(workDirectory), snapshot.completion == .confirmed else {
            throw DeviceServiceError.unsafeRestore(L("Le moteur n’a pas confirmé la fin de l’installation. Gardez l’appareil connecté et vérifiez son état avant une nouvelle tentative."))
        }
        onEvent(.finished)
    }

    private func readNormalDevice(id: String) async throws -> DeviceSnapshot {
        guard DeviceParser.validUDID(id) else { throw DeviceServiceError.invalidData(L("Identifiant USB non valide.")) }
        guard let tool = ToolResolver.resolve("ideviceinfo") else { throw DeviceServiceError.missingTool("ideviceinfo") }
        let result = try await command(tool, ["-u", id, "-x"])
        let snapshot = try DeviceParser.normalDevice(id: id, data: result.stdout)
        guard snapshot.values["DeviceEnclosureColor"] == nil else { return snapshot }
        // Newer devices omit this key from GetValue(all), but expose it by name.
        // Artwork metadata is optional: it must never make a connected device disappear.
        do {
            let color = try await command(tool, ["-u", id, "-k", "DeviceEnclosureColor"], timeout: 3)
            return try DeviceParser.normalDevice(id: id, data: result.stdout,
                                                enclosureColor: String(decoding: color.stdout, as: UTF8.self))
        } catch is CancellationError { throw CancellationError() }
        catch { return snapshot }
    }

    private func diagnosticReading(id: String, title: String, tool: String, arguments: [String], timeout: TimeInterval = 12) async throws -> DiagnosticReading {
        do {
            guard let executable = ToolResolver.resolve(tool) else { throw DeviceServiceError.missingTool(tool) }
            let result = try await command(executable, arguments, timeout: timeout)
            return try DiagnosticReading.decode(id: id, title: title, data: result.stdout)
        } catch is CancellationError { throw CancellationError() }
        catch { return .failure(id: id, title: title, error: error) }
    }

    private func command(_ executable: String, _ arguments: [String], timeout: TimeInterval = 15, outputLimit: Int = 2 * 1_024 * 1_024) async throws -> CommandResult {
        let result = try await runner.run(executable: executable, arguments: arguments, timeout: timeout, outputLimit: outputLimit)
        guard result.exitCode == 0 else {
            let message = String(decoding: result.stderr.isEmpty ? result.stdout : result.stderr, as: UTF8.self)
            throw DeviceServiceError.commandFailed(URL(fileURLWithPath: executable).lastPathComponent, result.exitCode, String(message.suffix(1_000)))
        }
        return result
    }

    private func restoreWorkingDirectory() throws -> URL {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: true)
        let directory = base.appendingPathComponent("iTelier/Restores/" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        return directory
    }
}
