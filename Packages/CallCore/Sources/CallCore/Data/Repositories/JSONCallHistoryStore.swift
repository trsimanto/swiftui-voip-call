import Foundation

/// File-backed call history.
///
/// An actor so reads and writes are serialised without locks. The whole list
/// is small (capped at `maxRecords`) so rewriting the file on each change is
/// cheaper than pulling in a database for it.
public actor JSONCallHistoryStore: CallHistoryRepository {
    private let fileURL: URL
    private let maxRecords: Int
    private var cache: [CallRecord]?

    private static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }()

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }()

    public init(fileURL: URL, maxRecords: Int = 500) {
        self.fileURL = fileURL
        self.maxRecords = maxRecords
    }

    /// `Application Support/CallHistory.json`
    public static func defaultFileURL() throws -> URL {
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return directory.appendingPathComponent("CallHistory.json")
    }

    public func fetchAll() async throws -> [CallRecord] {
        try loadIfNeeded()
    }

    public func add(_ record: CallRecord) async throws {
        var records = try loadIfNeeded()
        records.removeAll { $0.id == record.id }
        records.append(record)
        records.sort { $0.startedAt > $1.startedAt }
        if records.count > maxRecords {
            records.removeLast(records.count - maxRecords)
        }
        try save(records)
    }

    public func delete(id: UUID) async throws {
        var records = try loadIfNeeded()
        records.removeAll { $0.id == id }
        try save(records)
    }

    public func deleteAll() async throws {
        try save([])
    }

    // MARK: - Private

    private func loadIfNeeded() throws -> [CallRecord] {
        if let cache { return cache }

        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            cache = []
            return []
        }

        let data = try Data(contentsOf: fileURL)
        do {
            let records = try Self.decoder.decode([CallRecord].self, from: data)
                .sorted { $0.startedAt > $1.startedAt }
            cache = records
            return records
        } catch {
            // A corrupt history file shouldn't brick the Recents tab. Start
            // over rather than surfacing an error the user can't act on.
            cache = []
            return []
        }
    }

    private func save(_ records: [CallRecord]) throws {
        let directory = fileURL.deletingLastPathComponent()
        if !FileManager.default.fileExists(atPath: directory.path) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let data = try Self.encoder.encode(records)
        try data.write(to: fileURL, options: .atomic)
        cache = records
    }
}
