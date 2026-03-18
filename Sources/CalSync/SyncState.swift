import Foundation

struct SyncRecord: Codable {
    let sourceExternalId: String
    let destinationExternalId: String
    let destinationCalendarId: String
    let lastSyncedDate: Date
    let sourceLastModified: Date
}

class SyncState {
    static let shared = SyncState()

    private var records: [String: SyncRecord] = [:]
    private let fileURL: URL

    private init() {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("CalSync", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        fileURL = dir.appendingPathComponent("sync-state.json")
        load()
    }

    // MARK: - Query

    func record(forSourceId sourceId: String) -> SyncRecord? {
        return records[sourceId]
    }

    func allRecords() -> [SyncRecord] {
        return Array(records.values)
    }

    func sourceIds() -> Set<String> {
        return Set(records.keys)
    }

    // MARK: - Mutate

    func upsert(sourceExternalId: String, destinationExternalId: String, destinationCalendarId: String, sourceLastModified: Date) {
        records[sourceExternalId] = SyncRecord(
            sourceExternalId: sourceExternalId,
            destinationExternalId: destinationExternalId,
            destinationCalendarId: destinationCalendarId,
            lastSyncedDate: Date(),
            sourceLastModified: sourceLastModified
        )
        save()
    }

    func remove(forSourceId sourceId: String) {
        records.removeValue(forKey: sourceId)
        save()
    }

    func destinationExternalIds() -> Set<String> {
        return Set(records.values.map { $0.destinationExternalId })
    }

    // MARK: - Persistence

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            records = try decoder.decode([String: SyncRecord].self, from: data)
        } catch {
            print("CalSync: Failed to load sync state: \(error)")
        }
    }

    private func save() {
        do {
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(records)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            print("CalSync: Failed to save sync state: \(error)")
        }
    }
}
