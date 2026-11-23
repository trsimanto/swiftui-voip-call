import Foundation

public protocol CallHistoryRepository: AnyObject, Sendable {
    /// Newest first.
    func fetchAll() async throws -> [CallRecord]
    func add(_ record: CallRecord) async throws
    func delete(id: UUID) async throws
    func deleteAll() async throws
}

public protocol ContactRepository: AnyObject, Sendable {
    func fetchContacts() async throws -> [Contact]
}
