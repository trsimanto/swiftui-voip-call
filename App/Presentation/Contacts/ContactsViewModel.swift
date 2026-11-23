import CallCore
import Foundation
import Observation

@MainActor
@Observable
final class ContactsViewModel {
    var searchText = ""
    private(set) var contacts: [Contact] = []
    private(set) var isLoading = false
    private(set) var loadError: String?

    private let repository: any ContactRepository

    init(repository: any ContactRepository) {
        self.repository = repository
    }

    /// Hidden while searching so results aren't listed twice.
    var favorites: [Contact] {
        guard searchText.isEmpty else { return [] }
        return contacts.filter(\.isFavorite)
    }

    var filteredContacts: [Contact] {
        contacts.filter { $0.matches(searchText) }
    }

    var showsEmptySearch: Bool {
        !isLoading && !searchText.isEmpty && filteredContacts.isEmpty
    }

    func load() async {
        guard contacts.isEmpty, !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            contacts = try await repository.fetchContacts()
            loadError = nil
        } catch {
            loadError = "Couldn't load contacts."
        }
    }
}
