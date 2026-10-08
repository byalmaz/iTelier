import Foundation

public struct FirmwareDevice: Identifiable, Hashable, Codable, Sendable {
    public let identifier: String
    public let name: String
    public var id: String { identifier }
    public init(identifier: String, name: String) { self.identifier = identifier; self.name = name }
}

public struct FirmwareRelease: Identifiable, Hashable, Codable, Sendable {
    public let identifier: String
    public let version: String
    public let buildID: String
    public let url: URL
    public let fileSize: Int64
    public let signed: Bool
    public let releaseDate: Date?
    public let sha256: String?
    public let sha1: String?
    public let prereleaseTitle: String?
    public let source: String
    public var id: String { identifier + "-" + buildID }
    public var isBeta: Bool { prereleaseTitle != nil }
    public var displayVersion: String { displayVersion(language: AppLocalization.language) }

    func displayVersion(language: String) -> String {
        guard let title = prereleaseTitle else { return version }
        // Les titres conservés en mémoire suivent la langue actuelle, sans changer les métadonnées.
        let pattern = "^([0-9]+(?:\\.[0-9]+)*)\\s+(?:beta|bêta)(?:\\s+([0-9]+))?$"
        guard let expression = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = expression.firstMatch(in: title, range: NSRange(title.startIndex..., in: title)),
              let versionRange = Range(match.range(at: 1), in: title) else { return title }
        let number = String(title[versionRange])
        if let betaRange = Range(match.range(at: 2), in: title) {
            return AppLocalization.render("\(number) bêta \(String(title[betaRange]))", language: language)
        }
        return AppLocalization.render("\(number) bêta", language: language)
    }

    public init(identifier: String, version: String, buildID: String, url: URL, fileSize: Int64,
                signed: Bool, releaseDate: Date? = nil, sha256: String? = nil, sha1: String? = nil,
                prereleaseTitle: String? = nil, source: String = "IPSW.me") {
        self.identifier = identifier; self.version = version; self.buildID = buildID; self.url = url
        self.fileSize = fileSize; self.signed = signed; self.releaseDate = releaseDate
        self.sha256 = sha256; self.sha1 = sha1
        self.prereleaseTitle = prereleaseTitle; self.source = source
    }

    enum CodingKeys: String, CodingKey {
        case identifier, version, url, signed, prereleaseTitle, source
        case buildID = "buildid", fileSize = "filesize", releaseDate = "releasedate"
        case sha256 = "sha256sum", sha1 = "sha1sum"
    }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        identifier = try values.decode(String.self, forKey: .identifier)
        version = try values.decode(String.self, forKey: .version)
        buildID = try values.decode(String.self, forKey: .buildID)
        url = try values.decode(URL.self, forKey: .url)
        fileSize = try values.decode(Int64.self, forKey: .fileSize)
        signed = try values.decode(Bool.self, forKey: .signed)
        prereleaseTitle = try values.decodeIfPresent(String.self, forKey: .prereleaseTitle)
        source = try values.decodeIfPresent(String.self, forKey: .source) ?? "IPSW.me"
        releaseDate = try values.decodeIfPresent(String.self, forKey: .releaseDate).flatMap(Self.parseDate)
        sha256 = try Self.checksum(values.decodeIfPresent(String.self, forKey: .sha256), length: 64)
        sha1 = try Self.checksum(values.decodeIfPresent(String.self, forKey: .sha1), length: 40)
        guard fileSize > 0, !version.isEmpty, !buildID.isEmpty else { throw FirmwareTransferError.invalidMetadata }
    }
    public func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(identifier, forKey: .identifier); try values.encode(version, forKey: .version)
        try values.encode(buildID, forKey: .buildID); try values.encode(url, forKey: .url)
        try values.encode(fileSize, forKey: .fileSize); try values.encode(signed, forKey: .signed)
        try values.encodeIfPresent(prereleaseTitle, forKey: .prereleaseTitle)
        try values.encode(source, forKey: .source)
        let dateFormatter = ISO8601DateFormatter()
        dateFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        try values.encodeIfPresent(releaseDate.map { dateFormatter.string(from: $0) }, forKey: .releaseDate)
        try values.encodeIfPresent(sha256, forKey: .sha256); try values.encodeIfPresent(sha1, forKey: .sha1)
    }
    static func checksum(_ value: String?, length: Int) throws -> String? {
        guard let value, !value.isEmpty else { return nil }
        guard value.count == length, value.unicodeScalars.allSatisfy({ CharacterSet(charactersIn: "0123456789abcdefABCDEF").contains($0) }) else {
            throw FirmwareTransferError.invalidMetadata
        }
        return value.lowercased()
    }
    static func parseDate(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: text) { return date }
        let day = DateFormatter(); day.locale = Locale(identifier: "en_US_POSIX")
        day.timeZone = TimeZone(secondsFromGMT: 0); day.dateFormat = "yyyy-MM-dd"; day.isLenient = false
        return text.count == 10 ? day.date(from: text) : nil
    }
}

public struct FirmwareCatalogResult: Sendable {
    public let releases: [FirmwareRelease]
    public let warnings: [String]
}

public enum FirmwareTransferError: LocalizedError, Sendable {
    case invalidMetadata, untrustedURL, httpStatus(Int), metadataTooLarge, incompleteDownload, checksumMismatch, invalidDestination, insufficientSpace
    public var errorDescription: String? {
        switch self {
        case .invalidMetadata: return L("Le catalogue a renvoyé des métadonnées de firmware invalides.")
        case .untrustedURL: return L("Le téléchargement doit rester sur un serveur Apple en HTTPS. Cette URL ou redirection a été refusée.")
        case .httpStatus(let status): return L("Le serveur a répondu avec le code HTTP \(status). Réessayez plus tard.")
        case .metadataTooLarge: return L("La réponse du catalogue dépasse la taille autorisée.")
        case .incompleteDownload: return L("Le fichier reçu ne correspond pas à la taille annoncée. Le téléchargement incomplet a été supprimé.")
        case .checksumMismatch: return L("L’empreinte du fichier ne correspond pas au catalogue. Le téléchargement a été supprimé.")
        case .invalidDestination: return L("Choisissez un dossier accessible pour enregistrer le fichier IPSW.")
        case .insufficientSpace: return L("L’espace libre du dossier choisi est insuffisant pour ce fichier IPSW.")
        }
    }
}

/// These services supply metadata only. Firmware binaries always come from Apple.
public struct FirmwareCatalog: Sendable {
    public init() {}
    public func devices() async throws -> [FirmwareDevice] {
        try Self.decodeDevices(await fetch(URL(string: "https://api.ipsw.me/v4/devices?type=ipsw")!))
    }
    public func firmwares(for identifier: String) async throws -> [FirmwareRelease] {
        try await catalog(for: identifier).releases
    }
    public func catalog(for identifier: String) async throws -> FirmwareCatalogResult {
        guard Self.isSupportedIdentifier(identifier) else { throw FirmwareTransferError.invalidMetadata }
        async let stable = capture { try await publicFirmwares(for: identifier) }
        async let expanded = capture { try await AppleDBCatalog.shared.firmwares(for: identifier) }
        return try Self.merge(publicResult: await stable, appleDBResult: await expanded)
    }
    private func publicFirmwares(for identifier: String) async throws -> [FirmwareRelease] {
        var url = URLComponents(string: "https://api.ipsw.me")!
        url.path = "/v4/device/" + identifier; url.queryItems = [URLQueryItem(name: "type", value: "ipsw")]
        return try Self.decodeFirmwares(await fetch(url.url!), identifier: identifier)
    }
    private func capture(_ operation: () async throws -> [FirmwareRelease]) async -> Result<[FirmwareRelease], Error> {
        do { return .success(try await operation()) } catch { return .failure(error) }
    }
    static func merge(publicResult: Result<[FirmwareRelease], Error>, appleDBResult: Result<[FirmwareRelease], Error>) throws -> FirmwareCatalogResult {
        var releases: [FirmwareRelease] = [], warnings: [String] = []
        var successes = 0
        for (name, result) in [("IPSW.me", publicResult), (L("AppleDB (bêtas et archives)"), appleDBResult)] {
            switch result {
            case .success(let values): releases += values; successes += 1
            case .failure(let error):
                let message = UserFacingError.presentation(for: error, operation: .firmwareDownload).message
                warnings.append(L("\(name) indisponible : \(message)"))
            }
        }
        guard successes > 0 else { return try publicResult.map { FirmwareCatalogResult(releases: $0, warnings: warnings) }.get() }
        var seen = Set<String>()
        releases = releases.filter { seen.insert($0.id).inserted }
        return FirmwareCatalogResult(releases: releases.sorted(by: newestFirst), warnings: warnings)
    }
    public static func newestFirst(_ left: FirmwareRelease, _ right: FirmwareRelease) -> Bool {
        let version = left.version.compare(right.version, options: .numeric)
        if version != .orderedSame { return version == .orderedDescending }
        let a = left.releaseDate ?? .distantPast, b = right.releaseDate ?? .distantPast
        if a != b { return a > b }
        if left.isBeta != right.isBeta { return !left.isBeta }
        return left.buildID.compare(right.buildID, options: .numeric) == .orderedDescending
    }
    static func isSupportedIdentifier(_ value: String) -> Bool {
        value.range(of: "^(iPhone|iPad|RealityDevice)[0-9]+,[0-9]+$", options: .regularExpression) != nil
    }
    static func decodeDevices(_ data: Data) throws -> [FirmwareDevice] {
        let devices = try JSONDecoder().decode([FirmwareDevice].self, from: data)
        var seen = Set<String>()
        return devices.filter { isSupportedIdentifier($0.identifier) && !$0.name.isEmpty && seen.insert($0.identifier).inserted }
            // Les identifiants suivent les générations matérielles, même si le nom change.
            .sorted { $0.identifier.compare($1.identifier, options: .numeric) == .orderedDescending }
    }
    static func decodeFirmwares(_ data: Data, identifier: String) throws -> [FirmwareRelease] {
        struct Response: Decodable { let identifier: String; let firmwares: [FirmwareRelease] }
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard response.identifier == identifier, response.firmwares.allSatisfy({ $0.identifier == identifier }) else {
            throw FirmwareTransferError.invalidMetadata
        }
        var seen = Set<String>()
        return response.firmwares.filter {
            FirmwareDownloader.isAllowedDownloadURL($0.url) && $0.url.pathExtension.lowercased() == "ipsw" && seen.insert($0.id).inserted
        }.sorted {
            let first = $0.releaseDate ?? .distantPast, second = $1.releaseDate ?? .distantPast
            return first == second ? $0.buildID.compare($1.buildID, options: .numeric) == .orderedDescending : first > second
        }
    }
    func fetch(_ url: URL, limit: Int = 8 * 1_024 * 1_024) async throws -> Data {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false; configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 30
        let session = URLSession(configuration: configuration, delegate: CatalogRedirectGuard(host: url.host!), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        var request = URLRequest(url: url); request.setValue("application/json", forHTTPHeaderField: "Accept")
        let (bytes, response) = try await session.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.url?.scheme == "https", http.url?.host == url.host else {
            throw FirmwareTransferError.invalidMetadata
        }
        guard http.statusCode == 200 else { throw FirmwareTransferError.httpStatus(http.statusCode) }
        guard response.expectedContentLength <= limit else { throw FirmwareTransferError.metadataTooLarge }
        var buffer = [UInt8](); buffer.reserveCapacity(65_536)
        for try await byte in bytes {
            try Task.checkCancellation()
            guard buffer.count < limit else { throw FirmwareTransferError.metadataTooLarge }
            buffer.append(byte)
        }
        return Data(buffer)
    }
}

private final class CatalogRedirectGuard: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let host: String
    init(host: String) { self.host = host }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        let url = request.url
        completionHandler(url?.scheme == "https" && url?.host == host && url?.user == nil && url?.password == nil ? request : nil)
    }
}
