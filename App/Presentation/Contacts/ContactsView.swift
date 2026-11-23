import CallCore
import SwiftUI

@MainActor
struct ContactsView: View {
    @Bindable var viewModel: ContactsViewModel
    @Environment(CallSession.self) private var session

    var body: some View {
        NavigationStack {
            List {
                if !viewModel.favorites.isEmpty {
                    Section("Favorites") {
                        ForEach(viewModel.favorites) { contact in
                            row(for: contact)
                        }
                    }
                }

                Section(viewModel.searchText.isEmpty ? "All Contacts" : "Results") {
                    ForEach(viewModel.filteredContacts) { contact in
                        row(for: contact)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .overlay {
                if viewModel.showsEmptySearch {
                    ContentUnavailableView.search(text: viewModel.searchText)
                } else if viewModel.isLoading && viewModel.contacts.isEmpty {
                    ProgressView()
                }
            }
            .searchable(text: $viewModel.searchText, prompt: "Name or number")
            .navigationTitle("Contacts")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        session.simulateIncomingCall()
                    } label: {
                        Label("Simulate Incoming Call", systemImage: "phone.arrow.down.left")
                    }
                    .disabled(!session.canSimulateIncomingCall)
                    .accessibilityHint("Rings this device in a few seconds")
                }
            }
            .task { await viewModel.load() }
        }
    }

    private func row(for contact: Contact) -> some View {
        HStack(spacing: 12) {
            AvatarView(name: contact.name, size: 40)

            VStack(alignment: .leading, spacing: 2) {
                Text(contact.name)
                    .font(.body.weight(.medium))
                Text(contact.handle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                session.startCall(to: contact)
            } label: {
                Image(systemName: "phone.fill")
                    .font(.body)
                    .foregroundStyle(.white)
                    .frame(width: 36, height: 36)
                    .background(Circle().fill(Color.green))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Call \(contact.name)")
        }
        .padding(.vertical, 2)
    }
}
