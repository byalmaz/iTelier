import Foundation

/// AppleDB's official gh-pages publication contains both iOS and iPadOS IPSWs.
/// Keep the decoded index in memory for five minutes when switching devices.
actor AppleDBCatalog {
    static let shared = AppleDBCatalog()
    private var cache: [String: (builds: [AppleDBBuild], date: Date)] = [:]

    func firmwares(for identifier: String) async throws -> [FirmwareRelease] {
        let system = DeviceFamily(identifier: identifier) == .visionPro ? "visionOS" : "iOS"
        if let cached = cache[system], Date().timeIntervalSince(cached.date) < 300 {
            return try Self.releases(cached.builds, identifier: identifier)
        }
        let url = URL(string: "https://raw.githubusercontent.com/littlebyteorg/appledb/gh-pages/ios/\(system)/main.json")!
        let data = try await FirmwareCatalog().fetch(url, limit: 48 * 1_024 * 1_024)
        try Task.checkCancellation()
        let builds = try JSONDecoder().decode([AppleDBBuild].self, from: data)
        cache[system] = (builds, Date())
        return try Self.releases(builds, identifier: identifier)
    }

    static func decode(_ data: Data, identifier: String) throws -> [FirmwareRelease] {
        try releases(JSONDecoder().decode([AppleDBBuild].self, from: data), identifier: identifier)
    }

    private static func releases(_ builds: [AppleDBBuild], identifier: String) throws -> [FirmwareRelease] {
        guard FirmwareCatalog.isSupportedIdentifier(identifier) else { throw FirmwareTransferError.invalidMetadata }
        var results: [FirmwareRelease] = []
        var seen = Set<String>()
        for build in builds where ["iOS", "iPadOS", "visionOS"].contains(build.osStr) && build.deviceMap.contains(identifier) {
            guard let versionRange = build.version.range(of: "^[0-9]+(?:\\.[0-9]+)*", options: .regularExpression),
                  !build.build.isEmpty else { continue }
            let version = String(build.version[versionRange])
            let prerelease = build.beta == true || build.rc == true
            for source in build.sources ?? [] where source.type == "ipsw" && source.deviceMap.contains(identifier) {
                guard let size = source.size, size > 0,
                      let link = source.links.filter({ $0.active != false && FirmwareDownloader.isAllowedDownloadURL($0.url)
                          && $0.url.pathExtension.lowercased() == "ipsw" })
                        .sorted(by: { $0.preferred == true && $1.preferred != true }).first else { continue }
                // active describes URL availability, never Apple's signing status.
                let signed = build.signed?.includes(identifier) ?? false
                let release = FirmwareRelease(identifier: identifier, version: version, buildID: build.build,
                    url: link.url, fileSize: size, signed: signed,
                    releaseDate: build.released.flatMap(FirmwareRelease.parseDate),
                    sha256: try FirmwareRelease.checksum(source.hashes?["sha2-256"], length: 64),
                    sha1: try FirmwareRelease.checksum(source.hashes?["sha1"], length: 40),
                    prereleaseTitle: prerelease ? build.version : nil,
                    source: "AppleDB")
                if seen.insert(release.id).inserted { results.append(release) }
            }
        }
        return results.sorted(by: FirmwareCatalog.newestFirst)
    }
}

private struct AppleDBBuild: Decodable {
    let osStr: String
    let version: String
    let build: String
    let beta: Bool?
    let rc: Bool?
    let released: String?
    let deviceMap: [String]
    let sources: [Source]?
    let signed: Signature?

    enum Signature: Decodable {
        case all(Bool), devices([String])
        init(from decoder: Decoder) throws {
            let value = try decoder.singleValueContainer()
            if let all = try? value.decode(Bool.self) { self = .all(all) }
            else { self = .devices(try value.decode([String].self)) }
        }
        func includes(_ identifier: String) -> Bool {
            switch self { case .all(let value): return value; case .devices(let devices): return devices.contains(identifier) }
        }
    }
    struct Source: Decodable {
        let type: String
        let deviceMap: [String]
        let size: Int64?
        let links: [Link]
        let hashes: [String: String]?
    }
    struct Link: Decodable {
        let url: URL
        let active: Bool?
        let preferred: Bool?
    }
}
