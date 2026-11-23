import Foundation

/// Fixed address book for the demo. Some numbers are wired to specific
/// outcomes in `MockSignalingService.Configuration.demo` so every path of the
/// call flow can be tried from the UI.
public enum SampleContacts {
    public static let busyHandle = "+1 (555) 010-0486"
    public static let declineHandle = "+1 (555) 010-0313"
    public static let noAnswerHandle = "+1 (555) 010-0777"
    public static let unreachableHandle = "+1 (555) 010-0503"

    public static let all: [Contact] = [
        Contact(id: "c1", name: "Ayesha Rahman", handle: "+1 (555) 010-0101", isFavorite: true),
        Contact(id: "c2", name: "Daniel Okafor", handle: "+1 (555) 010-0142", isFavorite: true),
        Contact(id: "c3", name: "Mei Tanaka", handle: "+1 (555) 010-0199"),
        Contact(id: "c4", name: "Lars Virtanen", handle: "+1 (555) 010-0230"),
        Contact(id: "c5", name: "Ioana Popescu", handle: declineHandle),
        Contact(id: "c6", name: "Support Desk", handle: "+1 (555) 010-0600", isFavorite: true),
        Contact(id: "c7", name: "Busy Line", handle: busyHandle),
        Contact(id: "c8", name: "Voicemail Test", handle: noAnswerHandle),
        Contact(id: "c9", name: "Offline Server", handle: unreachableHandle)
    ]

    public static let demoBehaviors: [String: MockSignalingService.RemoteBehavior] = [
        busyHandle: .busy,
        declineHandle: .decline,
        noAnswerHandle: .noAnswer,
        unreachableHandle: .networkFailure
    ]
}

public final class SampleContactRepository: ContactRepository {
    private let contacts: [Contact]

    public init(contacts: [Contact] = SampleContacts.all) {
        self.contacts = contacts
    }

    public func fetchContacts() async throws -> [Contact] {
        contacts.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
}
