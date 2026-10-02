import Foundation

/// La fin du processus ne certifie pas son résultat ni le démarrage d’iOS.
public enum RestoreCompletion: String, Codable, Sendable {
    case confirmed, failed, unconfirmed
}

/// Suit les messages terminaux même lorsqu’ils sortent du journal borné.
struct RestoreCompletionTracker: Sendable {
    private(set) var confirmed = false
    private(set) var failed = false

    mutating func append(_ line: String) {
        var text = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if text.hasPrefix("error: ") { text.removeFirst(7) }
        if text == "status: restore finished" { confirmed = true }
        if ["unable to successfully restore device", "unable to restore device", "restore failed"].contains(text) {
            failed = true
        }
        if text.hasPrefix("status: "), ["verification error", "disk failure", "fail", "failed to ", "x-gold baseband update failed"].contains(where: { text.dropFirst(8).hasPrefix($0) }) {
            failed = true
        }
    }

    func completion(exitCode: Int32) -> RestoreCompletion {
        if exitCode != 0 || failed { return .failed }
        return confirmed ? .confirmed : .unconfirmed
    }
}
