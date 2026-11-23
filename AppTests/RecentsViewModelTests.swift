import CallCore
import XCTest
@testable import VoIPCall

@MainActor
final class RecentsViewModelTests: XCTestCase {
    private var calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }()

    // Thursday 14 Nov 2024, 15:00 UTC
    private let now = Date(timeIntervalSince1970: 1_731_596_400)

    private func record(hoursAgo: Double, reason: CallEndReason = .completed, direction: CallDirection = .outgoing, duration: TimeInterval = 60) -> CallRecord {
        CallRecord(
            id: UUID(),
            handle: "+1 555",
            displayName: "Mei",
            direction: direction,
            endReason: reason,
            startedAt: now.addingTimeInterval(-hoursAgo * 3600),
            duration: duration
        )
    }

    private func makeViewModel(records: [CallRecord]) -> (RecentsViewModel, InMemoryCallHistoryStore) {
        let store = InMemoryCallHistoryStore(records: records)
        let fixedNow = now
        let viewModel = RecentsViewModel(repository: store, calendar: calendar, now: { fixedNow })
        return (viewModel, store)
    }

    func testGroupsByDayNewestFirst() async {
        let today1 = record(hoursAgo: 1)
        let today2 = record(hoursAgo: 3)
        let yesterday = record(hoursAgo: 20)
        let lastWeek = record(hoursAgo: 24 * 9)
        let (viewModel, _) = makeViewModel(records: [lastWeek, today2, yesterday, today1])

        await viewModel.load()

        let sections = viewModel.sections
        XCTAssertEqual(sections.count, 3)
        XCTAssertEqual(sections[0].title, "Today")
        XCTAssertEqual(sections[0].records.map(\.id), [today1.id, today2.id])
        XCTAssertEqual(sections[1].title, "Yesterday")
        XCTAssertEqual(sections[1].records.map(\.id), [yesterday.id])
        XCTAssertEqual(sections[2].records.map(\.id), [lastWeek.id])
    }

    func testMissedFilter() async {
        let missed = record(hoursAgo: 2, reason: .missed, direction: .incoming, duration: 0)
        let answered = record(hoursAgo: 1, direction: .incoming)
        let (viewModel, _) = makeViewModel(records: [missed, answered])
        await viewModel.load()

        viewModel.filter = .missed
        XCTAssertEqual(viewModel.sections.flatMap(\.records).map(\.id), [missed.id])
        XCTAssertEqual(viewModel.missedCount, 1)

        viewModel.filter = .all
        XCTAssertEqual(viewModel.sections.flatMap(\.records).count, 2)
    }

    func testDeleteRemovesFromStore() async throws {
        let first = record(hoursAgo: 1)
        let second = record(hoursAgo: 2)
        let (viewModel, store) = makeViewModel(records: [first, second])
        await viewModel.load()

        await viewModel.delete(first)

        XCTAssertEqual(viewModel.records.map(\.id), [second.id])
        let stored = try await store.fetchAll().map(\.id)
        XCTAssertEqual(stored, [second.id])
    }

    func testClearAll() async throws {
        let (viewModel, store) = makeViewModel(records: [record(hoursAgo: 1), record(hoursAgo: 2)])
        await viewModel.load()

        await viewModel.clearAll()

        XCTAssertTrue(viewModel.isEmpty)
        let stored = try await store.fetchAll()
        XCTAssertTrue(stored.isEmpty)
    }

    func testEmptyStateOnlyAfterLoad() async {
        let (viewModel, _) = makeViewModel(records: [])
        XCTAssertFalse(viewModel.hasLoaded)
        await viewModel.load()
        XCTAssertTrue(viewModel.hasLoaded)
        XCTAssertTrue(viewModel.isEmpty)
    }

    func testDetailText() {
        XCTAssertEqual(RecentsViewModel.detailText(for: record(hoursAgo: 1, duration: 125)), "Outgoing · 2m 05s")
        XCTAssertEqual(RecentsViewModel.detailText(for: record(hoursAgo: 1, direction: .incoming, duration: 45)), "Incoming · 45s")
        XCTAssertEqual(RecentsViewModel.detailText(for: record(hoursAgo: 1, reason: .missed, direction: .incoming, duration: 0)), "Missed")
        XCTAssertEqual(RecentsViewModel.detailText(for: record(hoursAgo: 1, reason: .busy, duration: 0)), "Busy")
        XCTAssertEqual(RecentsViewModel.detailText(for: record(hoursAgo: 1, reason: .cancelled, duration: 0)), "Cancelled")
    }
}
