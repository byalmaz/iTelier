import Foundation
import XCTest
@testable import ReScopeCore

final class FirmwareDownloadIntegrityTests: XCTestCase {
    private let sha256 = "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad"
    private let sha1 = "a9993e364706816aba3e25717850c26c9cd0d89d"

    func testDownloadAcceptsMatchingSHA1WithoutSHA256() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = try await downloader().download(release(sha1: sha1.uppercased()), to: directory) { _ in }
        XCTAssertEqual(try Data(contentsOf: file), Data("abc".utf8))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["fixture.ipsw"])
    }

    func testDownloadRejectsWrongSHA1AndPreservesExistingFile() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let existing = directory.appendingPathComponent("fixture.ipsw")
        try Data("existing".utf8).write(to: existing)
        do {
            _ = try await downloader().download(release(sha1: String(repeating: "0", count: 40)), to: directory) { _ in }
            XCTFail("Une empreinte SHA-1 incorrecte doit interrompre le téléchargement.")
        } catch let error as FirmwareTransferError {
            guard case .checksumMismatch = error else { return XCTFail("Erreur inattendue : \(error)") }
        }
        XCTAssertEqual(try Data(contentsOf: existing), Data("existing".utf8))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["fixture.ipsw"])
    }

    func testDownloadPrefersSHA256WhenBothDigestsExist() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = try await downloader().download(
            release(sha256: sha256, sha1: String(repeating: "0", count: 40)), to: directory) { _ in }
        XCTAssertEqual(try Data(contentsOf: file), Data("abc".utf8))
    }

    func testDownloadRejectsMalformedSHA1MetadataWithoutLeavingFiles() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        do {
            _ = try await downloader().download(release(sha1: "invalid"), to: directory) { _ in }
            XCTFail("Une empreinte SHA-1 mal formée doit être refusée.")
        } catch let error as FirmwareTransferError {
            guard case .invalidMetadata = error else { return XCTFail("Erreur inattendue : \(error)") }
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [])
    }

    func testDownloadAcceptsIntactZIPWithoutPublishedDigest() async throws {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let payload = try await fixtureZIP()
        let file = try await downloader().download(release(payload: payload), to: directory) { _ in }
        XCTAssertEqual(try Data(contentsOf: file), payload)
        let inspected = try await FirmwareInspector.inspect(file, runner: ProcessRunner())
        XCTAssertEqual(inspected.version, "18.0")
        XCTAssertEqual(inspected.build, "22A3354")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), ["fixture.ipsw"])
    }

    func testDownloadRejectsCorruptZIPPayloadWithIntactManifest() async throws {
        let directory = try temporaryDirectory()
        let fixtureDirectory = try temporaryDirectory()
        defer {
            try? FileManager.default.removeItem(at: directory)
            try? FileManager.default.removeItem(at: fixtureDirectory)
        }
        var payload = try await fixtureZIP()
        guard let member = payload.range(of: Data("DOWNLOAD_PAYLOAD_0123456789".utf8)) else {
            return XCTFail("Le membre ZIP de la fixture est introuvable.")
        }
        payload[member.lowerBound] ^= 1 // Même taille et manifeste intact, mais CRC du membre incorrect.
        let damagedFile = fixtureDirectory.appendingPathComponent("damaged.ipsw")
        try payload.write(to: damagedFile)
        _ = try FileFingerprint.read(damagedFile)
        let manifest = try await ProcessRunner().run(executable: "/usr/bin/unzip",
            arguments: ["-p", damagedFile.path, "BuildManifest.plist"])
        XCTAssertEqual(manifest.exitCode, 0)
        XCTAssertEqual(try FirmwareManifest.parse(manifest.stdout).build, "22A3354")
        do {
            _ = try await downloader().download(release(payload: payload), to: directory) { _ in }
            XCTFail("Le CRC incorrect d’un membre doit bloquer le téléchargement.")
        } catch let error as DeviceServiceError {
            guard case .invalidData = error else { return XCTFail("Erreur inattendue : \(error)") }
        }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: directory.path), [])
    }

    private func fixtureZIP() async throws -> Data {
        let directory = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let object: [String: Any] = [
            "ProductVersion": "18.0", "ProductBuildVersion": "22A3354",
            "SupportedProductTypes": ["iPhone14,2"],
            "BuildIdentities": [[
                "Info": ["DeviceClass": "D63AP", "RestoreBehavior": "Erase", "Variant": "Customer Erase Install (IPSW)"],
                "Manifest": ["OS": ["Info": ["Path": "payload.bin"]],
                             "iBSS": ["Info": ["Path": "Firmware/dfu/iBSS.img4"]],
                             "iBEC": ["Info": ["Path": "Firmware/dfu/iBEC.img4"]]]
            ]]
        ]
        let manifest = try PropertyListSerialization.data(fromPropertyList: object, format: .xml, options: 0)
        try manifest.write(to: directory.appendingPathComponent("BuildManifest.plist"))
        try Data("DOWNLOAD_PAYLOAD_0123456789".utf8).write(to: directory.appendingPathComponent("payload.bin"))
        let file = directory.appendingPathComponent("source.ipsw")
        let zip = try await ProcessRunner().run(executable: "/usr/bin/zip",
            arguments: ["-0q", file.path, "BuildManifest.plist", "payload.bin"], workingDirectory: directory)
        guard zip.exitCode == 0 else { throw DeviceServiceError.invalidData("La création de la fixture ZIP a échoué.") }
        return try Data(contentsOf: file)
    }

    private func temporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    private func downloader() -> FirmwareDownloader {
        FirmwareDownloader(configurationFactory: {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.protocolClasses = [IntegrityDownloadProtocol.self]
            return configuration
        })
    }

    private func release(sha256: String? = nil, sha1: String? = nil, payload: Data? = nil) -> FirmwareRelease {
        var url = URLComponents(string: "https://updates.cdn-apple.com/fixture.ipsw")!
        if let payload { url.queryItems = [URLQueryItem(name: "payload", value: payload.base64EncodedString())] }
        return FirmwareRelease(identifier: "iPhone14,2", version: "18.0", buildID: "22A3354",
            url: url.url!, fileSize: Int64(payload?.count ?? 3),
            signed: true, sha256: sha256, sha1: sha1)
    }
}

/// Le transport est simulé ; la tâche URLSession et le fichier temporaire restent réels.
private final class IntegrityDownloadProtocol: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let url = request.url else { return }
        let encoded = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first(where: { $0.name == "payload" })?.value
        let payload = encoded.flatMap { Data(base64Encoded: $0) } ?? Data("abc".utf8)
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
            headerFields: ["Content-Length": String(payload.count), "Content-Type": "application/octet-stream"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: payload)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
