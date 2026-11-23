import CallCore
import Foundation
import Observation

@MainActor
@Observable
final class RecentsViewModel {
    enum Filter: String, CaseIterable, Identifiable {
        case all = "All"
        case missed = "Missed"

        var id: Self { self }
    }

    struct DaySection: Identifiable, Equatable {
        let id: Date
        let title: String
        let records: [CallRecord]
    }

    var filter: Filter = .all
    private(set) var records: [CallRecord] = []
    private(set) var hasLoaded = false

    private let repository: any CallHistoryRepository
    private let calendar: Calendar
    private let now: () -> Date

    init(
        repository: any CallHistoryRepository,
        calendar: Calendar = .current,
        now: @escaping () -> Date = { Date() }
    ) {
        self.repository = repository
        self.calendar = calendar
        self.now = now
    }

    var sections: [DaySection] {
        let visible = filter == .missed ? records.filter(\.isMissed) : records
        let byDay = Dictionary(grouping: visible) { calendar.startOfDay(for: $0.startedAt) }

        return byDay.keys.sorted(by: >).map { day in
            DaySection(
                id: day,
                title: title(for: day),
                records: (byDay[day] ?? []).sorted { $0.startedAt > $1.startedAt }
            )
        }
    }

    var isEmpty: Bool { sections.isEmpty }

    var missedCount: Int { records.filter(\.isMissed).count }

    func load() async {
        do {
            records = try await repository.fetchAll()
        } catch {
            records = []
        }
        hasLoaded = true
    }

    func delete(_ record: CallRecord) async {
        records.removeAll { $0.id == record.id }
        try? await repository.delete(id: record.id)
    }

    func clearAll() async {
        records = []
        try? await repository.deleteAll()
    }

    func title(for day: Date) -> String {
        let today = calendar.startOfDay(for: now())
        let daysAgo = calendar.dateComponents([.day], from: day, to: today).day ?? 0

        switch daysAgo {
        case 0:
            return "Today"
        case 1:
            return "Yesterday"
        case 2..<7:
            return day.formatted(.dateTime.weekday(.wide))
        default:
            return day.formatted(date: .abbreviated, time: .omitted)
        }
    }

    /// Second line of a Recents row: "Outgoing · 2m 05s", "Missed", "Busy"...
    static func detailText(for record: CallRecord) -> String {
        if record.wasConnected {
            let direction = record.direction == .incoming ? "Incoming" : "Outgoing"
            return "\(direction) · \(CallDurationFormatter.compactString(from: record.duration))"
        }
        if record.direction == .outgoing && record.endReason == .completed {
            return "Outgoing"
        }
        return record.endReason.localizedDescription
    }
}
