import ReScopeCore
import Foundation

extension AppModel {
    func refreshDeviceInformation(_ target: DeviceSnapshot, batteryDetails: Bool = false, storageDetails: Bool = false) async {
        deviceInformationError = nil
        guard !busy else { return }
        if isDemo {
            deviceInformation = DeviceInformation(device: target,
                battery: ["BatteryCurrentCapacity": "62", "BatteryIsCharging": "true"],
                disk: ["TotalDataCapacity": "256000000000", "TotalDataAvailable": "174730000000"],
                gauge: batteryDetails ? ["GasGauge.DesignCapacity": "3274", "GasGauge.NominalChargeCapacity": "3012", "GasGauge.CycleCount": "310"] : [:],
                registry: batteryDetails ? ["IORegistry.AppleRawCurrentCapacity": "1867", "IORegistry.Voltage": "4100", "IORegistry.InstantAmperage": "800", "IORegistry.Serial": "DEMO-BATTERY", "IORegistry.AtCriticalLevel": "false"] : [:], hasBatteryDetails: batteryDetails)
            return
        }
        guard target.mode == .normal else { deviceInformation = DeviceInformation(device: target); return }
        isReadingDeviceInformation = true
        defer { isReadingDeviceInformation = false }
        do {
            while isRefreshing { try await Task.sleep(nanoseconds: 100_000_000) }
            try Task.checkCancellation()
            guard let connected = devices.first(where: { $0.id == target.id }), connected.ecid == target.ecid,
                  connected.productType == target.productType else {
                throw DeviceServiceError.invalidData(L("L’appareil connecté ne correspond plus à l’appareil sélectionné."))
            }
            let information = try await DeviceService().information(connected, batteryDetails: batteryDetails, storageDetails: storageDetails)
            try Task.checkCancellation()
            guard informationDevice?.id == target.id else { return }
            if let previous = deviceInformation, previous.device.id == target.id, previous.device.ecid == target.ecid {
                deviceInformation = DeviceInformation(device: information.device, battery: information.battery,
                    disk: !storageDetails && previous.hasStorageDetails ? previous.disk.merging(information.disk) { _, new in new } : information.disk,
                    warnings: information.warnings,
                    gauge: batteryDetails ? information.metrics.gauge : previous.metrics.gauge,
                    registry: batteryDetails ? information.metrics.registry : previous.metrics.registry,
                    hasBatteryDetails: batteryDetails || previous.hasBatteryDetails,
                    storageHardware: storageDetails ? information.storageHardware : previous.storageHardware,
                    hasStorageDetails: storageDetails || previous.hasStorageDetails, date: information.date)
            } else { deviceInformation = information }
        } catch is CancellationError { }
        catch { if informationDevice?.id == target.id { deviceInformationError = error.localizedDescription } }
    }
}
