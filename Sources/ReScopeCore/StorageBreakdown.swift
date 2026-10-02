import Foundation

public struct StorageSegment: Identifiable, Sendable {
    public let id: String
    public let title: String
    public let bytes: Int64
}

extension DeviceInformation {
    /// Legacy domain categories are optional. Reject inconsistent totals instead of scaling them into a plausible chart.
    public var storageSegments: [StorageSegment] {
        guard let used = storageUsed, let free = storageFree else { return [] }
        // PhotoUsage et CameraUsage peuvent désigner les mêmes octets sur les iOS récents.
        let photoKey = disk["PhotoUsage"] != nil ? "PhotoUsage" : "CameraUsage"
        let keys = [(photoKey, L("Photos")),
                    ("MobileApplicationUsage", L("Applications")), ("ApplicationDocumentsUsage", L("Documents des applications")), ("CalendarUsage", L("Calendriers")),
                    ("NotesUsage", L("Notes")), ("VoicemailUsage", L("Messagerie vocale"))]
        var result: [StorageSegment] = []
        var remainder = used
        if let system = systemUsed, system > 0, system <= remainder {
            result.append(StorageSegment(id: "system", title: L("Système"), bytes: system)); remainder -= system
        }
        for (key, title) in keys {
            guard let raw = disk[key], let bytes = Int64(raw), bytes > 0 else { continue }
            guard bytes <= remainder else {
                return [StorageSegment(id: "used", title: L("Espace utilisé"), bytes: used), StorageSegment(id: "free", title: L("Disponible"), bytes: free)]
            }
            result.append(StorageSegment(id: key, title: title, bytes: bytes)); remainder -= bytes
        }
        if remainder > 0 { result.append(StorageSegment(id: "used", title: result.isEmpty ? L("Espace utilisé") : L("Autres données"), bytes: remainder)) }
        result.append(StorageSegment(id: "free", title: L("Disponible"), bytes: free))
        return result
    }
}
