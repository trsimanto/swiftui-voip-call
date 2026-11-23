import Foundation

/// Non-persistent history, for previews and tests.
public actor InMemoryCallHistoryStore: CallHistoryRepository {
    private var records: [CallRecord]

    public init(records: [CallRecord] = []) {
        self.records = records.sorted { $0.startedAt > $1.startedAt }
    }

    public func fetchAll() async throws -> [CallRecord] {
        records
    }

    public func add(_ record: CallRecord) async throws {
        records.removeAll { $0.id == record.id }
        records.append(record)
        records.sort { $0.startedAt > $1.startedAt }
    }

    public func delete(id: UUID) async throws {
        records.removeAll { $0.id == id }
    }

    public func deleteAll() async throws {
        records.removeAll()
    }
}
