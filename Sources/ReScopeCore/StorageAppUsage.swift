import Foundation

/// Totaux renvoyés par le helper. Aucun nom ni identifiant d’application ne sort du processus de lecture.
struct StorageAppUsage: Decodable {
    let count: Int
    let applicationBytes: Int64?
    let documentBytes: Int64?
    var diskValues: [String: String] {
        guard count >= 0, count <= 100_000 else { return [:] }
        var result: [String: String] = [:]
        if let bytes = applicationBytes, bytes >= 0 { result["MobileApplicationUsage"] = String(bytes) }
        if let bytes = documentBytes, bytes >= 0 { result["ApplicationDocumentsUsage"] = String(bytes) }
        return result
    }
}
