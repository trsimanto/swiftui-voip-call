import XCTest
@testable import CallCore

final class CallHistoryStoreTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("CallHistoryStoreTests-\(UUID().uuidString)", isDirectory: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private var fileURL: URL {
        directory.appendingPathComponent("history.json")
    }

    func testEmptyWhenFileDoesNotExist() async throws {
        let store = JSONCallHistoryStore(fileURL: fileURL)
        let records = try await store.fetchAll()
        XCTAssertTrue(records.isEmpty)
    }

    func testRecordsAreReturnedNewestFirst() async throws {
        let store = JSONCallHistoryStore(fileURL: fileURL)
        let old = makeRecord(minutesAgo: 30)
        let recent = makeRecord(minutesAgo: 1)
        let middle = makeRecord(minutesAgo: 10)

        try await store.add(old)
        try await store.add(recent)
        try await store.add(middle)

        let ids = try await store.fetchAll().map(\.id)
        XCTAssertEqual(ids, [recent.id, middle.id, old.id])
    }

    func testRecordsSurviveAcrossInstances() async throws {
        let record = makeRecord(minutesAgo: 5, reason: .missed, direction: .incoming)
        try await JSONCallHistoryStore(fileURL: fileURL).add(record)

        let reloaded = try await JSONCallHistoryStore(fileURL: fileURL).fetchAll()
        XCTAssertEqual(reloaded.count, 1)
        XCTAssertEqual(reloaded.first?.id, record.id)
        XCTAssertEqual(reloaded.first?.endReason, .missed)
        XCTAssertEqual(reloaded.first?.isMissed, true)
        // ISO 8601 drops sub-second precision.
        XCTAssertEqual(reloaded.first!.startedAt.timeIntervalSince1970, record.startedAt.timeIntervalSince1970, accuracy: 1)
    }

    func testAddingSameIdReplacesRecord() async throws {
        let store = JSONCallHistoryStore(fileURL: fileURL)
        let id = UUID()
        try await store.add(makeRecord(id: id, minutesAgo: 2, reason: .cancelled))
        try await store.add(makeRecord(id: id, minutesAgo: 2, reason: .completed))

        let records = try await store.fetchAll()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.endReason, .completed)
    }

    func testDeleteAndDeleteAll() async throws {
        let store = JSONCallHistoryStore(fileURL: fileURL)
        let first = makeRecord(minutesAgo: 1)
        let second = makeRecord(minutesAgo: 2)
        try await store.add(first)
        try await store.add(second)

        try await store.delete(id: first.id)
        var remaining = try await store.fetchAll().map(\.id)
        XCTAssertEqual(remaining, [second.id])

        try await store.deleteAll()
        remaining = try await JSONCallHistoryStore(fileURL: fileURL).fetchAll().map(\.id)
        XCTAssertTrue(remaining.isEmpty)
    }

    func testOldestRecordsAreTrimmedPastLimit() async throws {
        let store = JSONCallHistoryStore(fileURL: fileURL, maxRecords: 3)
        let records = (1...5).map { makeRecord(minutesAgo: Double($0)) }
        for record in records {
            try await store.add(record)
        }

        let kept = try await store.fetchAll().map(\.id)
        XCTAssertEqual(kept, records.prefix(3).map(\.id))
    }

    func testCorruptFileIsTreatedAsEmpty() async throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: fileURL)

        let store = JSONCallHistoryStore(fileURL: fileURL)
        let records = try await store.fetchAll()
        XCTAssertTrue(records.isEmpty)

        try await store.add(makeRecord(minutesAgo: 1))
        let count = try await store.fetchAll().count
        XCTAssertEqual(count, 1)
    }

    func testInMemoryStoreBehavesLikeFileStore() async throws {
        let store = InMemoryCallHistoryStore()
        let old = makeRecord(minutesAgo: 9)
        let recent = makeRecord(minutesAgo: 1)
        try await store.add(old)
        try await store.add(recent)

        var ids = try await store.fetchAll().map(\.id)
        XCTAssertEqual(ids, [recent.id, old.id])

        try await store.delete(id: recent.id)
        ids = try await store.fetchAll().map(\.id)
        XCTAssertEqual(ids, [old.id])
    }

    func testRecordFromCallUsesTalkTime() {
        let start = Date(timeIntervalSince1970: 0)
        let call = Call(
            handle: "+1 555",
            displayName: "Test",
            direction: .outgoing,
            state: .ended(.completed),
            createdAt: start,
            connectedAt: start.addingTimeInterval(5)
        )
        let record = CallRecord(call: call, endReason: .completed, endedAt: start.addingTimeInterval(65))
        XCTAssertEqual(record.duration, 60)
        XCTAssertTrue(record.wasConnected)
        XCTAssertFalse(record.isMissed)
    }

    // MARK: - Helpers

    private func makeRecord(
        id: UUID = UUID(),
        minutesAgo: Double,
        reason: CallEndReason = .completed,
        direction: CallDirection = .outgoing
    ) -> CallRecord {
        CallRecord(
            id: id,
            handle: "+1 (555) 010-0101",
            displayName: "Ayesha Rahman",
            direction: direction,
            endReason: reason,
            startedAt: Date().addingTimeInterval(-minutesAgo * 60),
            duration: reason == .completed ? 42 : 0
        )
    }
}
