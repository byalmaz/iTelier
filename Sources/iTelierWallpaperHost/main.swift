import Foundation
import CoreFoundation
import Darwin

// Client SpringBoard en lecture seule, isolé dans un processus enfant borné afin
// qu’un appareil verrouillé ou sans réponse ne bloque pas l’interface.
typealias NewDevice = @convention(c) (UnsafeMutablePointer<OpaquePointer?>, UnsafePointer<CChar>?, Int32) -> Int32
typealias StartService = @convention(c) (OpaquePointer?, UnsafeMutablePointer<OpaquePointer?>, UnsafePointer<CChar>?) -> Int32
typealias StartLockdownService = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?, UnsafeMutablePointer<OpaquePointer?>) -> Int32
typealias NewPlistClient = @convention(c) (OpaquePointer?, OpaquePointer?, UnsafeMutablePointer<OpaquePointer?>) -> Int32
typealias SendPlist = @convention(c) (OpaquePointer?, OpaquePointer?) -> Int32
typealias ReceivePlist = @convention(c) (OpaquePointer?, UnsafeMutablePointer<OpaquePointer?>, UInt32) -> Int32
typealias FreeClient = @convention(c) (OpaquePointer?) -> Int32
typealias NewPlist = @convention(c) () -> OpaquePointer?
typealias NewString = @convention(c) (UnsafePointer<CChar>?) -> OpaquePointer?
typealias SetItem = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?, OpaquePointer?) -> Void
typealias AppendItem = @convention(c) (OpaquePointer?, OpaquePointer?) -> Void
typealias FreePlist = @convention(c) (OpaquePointer?) -> Void
typealias BrowseApps = @convention(c) (OpaquePointer?, OpaquePointer?, UnsafeMutablePointer<OpaquePointer?>) -> Int32
typealias PlistXML = @convention(c) (OpaquePointer?, UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>, UnsafeMutablePointer<UInt32>) -> Void
typealias GetItem = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?) -> OpaquePointer?
typealias GetData = @convention(c) (OpaquePointer?, UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>, UnsafeMutablePointer<UInt64>) -> Void

func lockScreenWallpaper(handle: UnsafeMutableRawPointer, device: OpaquePointer?, directory: URL) -> Int32 {
    guard let plist = dlopen(directory.appendingPathComponent("libplist-2.0.4.dylib").path, RTLD_NOW | RTLD_LOCAL) else { return 3 }
    defer { dlclose(plist) }
    guard let handshakeSymbol = dlsym(handle, "lockdownd_client_new_with_handshake"),
          let startSymbol = dlsym(handle, "lockdownd_start_service"),
          let lockdownFreeSymbol = dlsym(handle, "lockdownd_client_free"),
          let descriptorFreeSymbol = dlsym(handle, "lockdownd_service_descriptor_free"),
          let newClientSymbol = dlsym(handle, "property_list_service_client_new"),
          let clientFreeSymbol = dlsym(handle, "property_list_service_client_free"),
          let sendSymbol = dlsym(handle, "property_list_service_send_binary_plist"),
          let receiveSymbol = dlsym(handle, "property_list_service_receive_plist_with_timeout"),
          let dictSymbol = dlsym(plist, "plist_new_dict"), let stringSymbol = dlsym(plist, "plist_new_string"),
          let setSymbol = dlsym(plist, "plist_dict_set_item"), let getSymbol = dlsym(plist, "plist_dict_get_item"),
          let dataSymbol = dlsym(plist, "plist_get_data_val"), let freeSymbol = dlsym(plist, "plist_free") else { return 3 }
    let handshake = unsafeBitCast(handshakeSymbol, to: StartService.self)
    let start = unsafeBitCast(startSymbol, to: StartLockdownService.self)
    let releaseLockdown = unsafeBitCast(lockdownFreeSymbol, to: FreeClient.self)
    let releaseDescriptor = unsafeBitCast(descriptorFreeSymbol, to: FreeClient.self)
    let newClient = unsafeBitCast(newClientSymbol, to: NewPlistClient.self)
    let releaseClient = unsafeBitCast(clientFreeSymbol, to: FreeClient.self)
    let send = unsafeBitCast(sendSymbol, to: SendPlist.self), receive = unsafeBitCast(receiveSymbol, to: ReceivePlist.self)
    let dict = unsafeBitCast(dictSymbol, to: NewPlist.self), string = unsafeBitCast(stringSymbol, to: NewString.self)
    let set = unsafeBitCast(setSymbol, to: SetItem.self), get = unsafeBitCast(getSymbol, to: GetItem.self)
    let getData = unsafeBitCast(dataSymbol, to: GetData.self), freePlist = unsafeBitCast(freeSymbol, to: FreePlist.self)
    var lockdown: OpaquePointer?, descriptor: OpaquePointer?, client: OpaquePointer?, response: OpaquePointer?
    guard "iTelier".withCString({ handshake(device, &lockdown, $0) }) == 0 else { return 5 }
    defer { _ = releaseLockdown(lockdown) }
    guard "com.apple.springboardservices".withCString({ start(lockdown, $0, &descriptor) }) == 0 else { return 5 }
    defer { _ = releaseDescriptor(descriptor) }
    guard newClient(device, descriptor, &client) == 0 else { return 5 }
    defer { _ = releaseClient(client) }
    guard let request = dict() else { return 3 }
    defer { freePlist(request); freePlist(response) }
    "command".withCString { key in "getWallpaperPreviewImage".withCString { set(request, key, string($0)) } }
    "wallpaperName".withCString { key in "lockscreen".withCString { set(request, key, string($0)) } }
    // L’ancienne API ne lit que l’accueil, parfois obsolète depuis les fonds personnalisables.
    // Ne pas réécrire la disposition des icônes pour forcer un rafraîchissement.
    guard send(client, request) == 0, receive(client, &response, 6_000) == 0,
          let image = "pngData".withCString({ get(response, $0) }) else { return 6 }
    var bytes: UnsafeMutablePointer<CChar>?, count: UInt64 = 0
    getData(image, &bytes, &count)
    defer { free(bytes) }
    guard let bytes, count > 8, count <= 20 * 1_024 * 1_024 else { return 6 }
    let data = Data(bytes: bytes, count: Int(count))
    guard data.starts(with: [137, 80, 78, 71, 13, 10, 26, 10]) else { return 7 }
    do { try FileHandle.standardOutput.write(contentsOf: data); return 0 } catch { return 8 }
}

func applicationSizes(handle: UnsafeMutableRawPointer, device: OpaquePointer?, directory: URL) -> Int32 {
    guard let plist = dlopen(directory.appendingPathComponent("libplist-2.0.4.dylib").path, RTLD_NOW | RTLD_LOCAL) else { return 3 }
    defer { dlclose(plist) }
    guard let startSymbol = dlsym(handle, "instproxy_client_start_service"), let browseSymbol = dlsym(handle, "instproxy_browse"),
          let freeSymbol = dlsym(handle, "instproxy_client_free"), let dictSymbol = dlsym(plist, "plist_new_dict"),
          let arraySymbol = dlsym(plist, "plist_new_array"), let stringSymbol = dlsym(plist, "plist_new_string"),
          let setSymbol = dlsym(plist, "plist_dict_set_item"), let appendSymbol = dlsym(plist, "plist_array_append_item"),
          let xmlSymbol = dlsym(plist, "plist_to_xml"), let plistFreeSymbol = dlsym(plist, "plist_free") else { return 3 }
    let start = unsafeBitCast(startSymbol, to: StartService.self), browse = unsafeBitCast(browseSymbol, to: BrowseApps.self)
    let release = unsafeBitCast(freeSymbol, to: FreeClient.self), dict = unsafeBitCast(dictSymbol, to: NewPlist.self)
    let array = unsafeBitCast(arraySymbol, to: NewPlist.self), string = unsafeBitCast(stringSymbol, to: NewString.self)
    let set = unsafeBitCast(setSymbol, to: SetItem.self), append = unsafeBitCast(appendSymbol, to: AppendItem.self)
    let xml = unsafeBitCast(xmlSymbol, to: PlistXML.self), freePlist = unsafeBitCast(plistFreeSymbol, to: FreePlist.self)
    var client: OpaquePointer?, result: OpaquePointer?
    guard "iTelier".withCString({ start(device, &client, $0) }) == 0 else { return 5 }
    defer { _ = release(client) }
    let options = dict(), attributes = array()
    defer { freePlist(options); freePlist(result) }
    for key in ["StaticDiskUsage", "DynamicDiskUsage"] { key.withCString { append(attributes, string($0)) } }
    "ReturnAttributes".withCString { set(options, $0, attributes) }
    "ApplicationType".withCString { key in "User".withCString { set(options, key, string($0)) } }
    guard browse(client, options, &result) == 0 else { return 6 }
    var bytes: UnsafeMutablePointer<CChar>?, count: UInt32 = 0
    xml(result, &bytes, &count)
    defer { free(bytes) }
    guard let bytes, count > 0, count <= 20 * 1_024 * 1_024,
          let apps = try? PropertyListSerialization.propertyList(from: Data(bytes: bytes, count: Int(count)), format: nil) as? [[String: Any]], apps.count <= 100_000 else { return 7 }
    func total(_ key: String) -> Int64? {
        var sum: Int64 = 0
        for app in apps {
            guard let number = app[key] as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
                  let value = Int64(number.stringValue), value >= 0, sum <= Int64.max - value else { return nil }
            sum += value
        }
        return sum
    }
    var output: [String: Any] = ["count": apps.count]
    if let value = total("StaticDiskUsage") { output["applicationBytes"] = value }
    if let value = total("DynamicDiskUsage") { output["documentBytes"] = value }
    do { try FileHandle.standardOutput.write(contentsOf: JSONSerialization.data(withJSONObject: output)); return 0 } catch { return 8 }
}

func run() -> Int32 {
    guard CommandLine.arguments.count == 2 || (CommandLine.arguments.count == 3 && CommandLine.arguments[2] == "--storage") else { return 2 }
    let id = CommandLine.arguments[1]
    guard id.range(of: "^[A-Za-z0-9-]{6,128}$", options: .regularExpression) != nil else { return 2 }
    // Le chemin du chargeur est fourni par dyld ; argv[0] ne choisit jamais la bibliothèque.
    var length: UInt32 = 0
    _ = _NSGetExecutablePath(nil, &length)
    var path = [CChar](repeating: 0, count: Int(length))
    guard _NSGetExecutablePath(&path, &length) == 0 else { return 3 }
    let executable = URL(fileURLWithPath: String(cString: path)).resolvingSymlinksInPath()
    let library = executable.deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Frameworks/libimobiledevice-1.0.6.dylib")
    guard let handle = dlopen(library.path, RTLD_NOW | RTLD_LOCAL) else { return 3 }
    defer { dlclose(handle) }
    guard let newSymbol = dlsym(handle, "idevice_new_with_options"),
          let freeDeviceSymbol = dlsym(handle, "idevice_free") else { return 3 }
    let newDevice = unsafeBitCast(newSymbol, to: NewDevice.self)
    let freeDevice = unsafeBitCast(freeDeviceSymbol, to: FreeClient.self)
    var device: OpaquePointer?
    // IDEVICE_LOOKUP_USBMUX (1 << 1), jamais un appareil réseau.
    guard id.withCString({ newDevice(&device, $0, 2) }) == 0 else { return 4 }
    defer { _ = freeDevice(device) }
    if CommandLine.arguments.count == 3 { return applicationSizes(handle: handle, device: device, directory: library.deletingLastPathComponent()) }
    return lockScreenWallpaper(handle: handle, device: device, directory: library.deletingLastPathComponent())
}
exit(run())
