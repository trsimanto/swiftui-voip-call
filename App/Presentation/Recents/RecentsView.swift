import CallCore
import SwiftUI

@MainActor
struct RecentsView: View {
    @Bindable var viewModel: RecentsViewModel
    @Environment(CallSession.self) private var session
    @State private var isConfirmingClear = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(viewModel.sections) { section in
                    Section(section.title) {
                        ForEach(section.records) { record in
                            RecentCallRow(record: record) {
                                session.startCall(handle: record.handle, name: record.displayName)
                            }
                            .swipeActions {
                                Button("Delete", systemImage: "trash", role: .destructive) {
                                    Task { await viewModel.delete(record) }
                                }
                            }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .overlay {
                if viewModel.hasLoaded && viewModel.isEmpty {
                    ContentUnavailableView(
                        viewModel.filter == .missed ? "No Missed Calls" : "No Recent Calls",
                        systemImage: "phone",
                        description: Text("Calls you make and receive show up here.")
                    )
                }
            }
            .navigationTitle("Recents")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("Filter", selection: $viewModel.filter) {
                        ForEach(RecentsViewModel.Filter.allCases) { filter in
                            Text(filter.rawValue).tag(filter)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear") { isConfirmingClear = true }
                        .disabled(viewModel.records.isEmpty)
                }
            }
            .confirmationDialog("Clear all recent calls?", isPresented: $isConfirmingClear, titleVisibility: .visible) {
                Button("Clear All Recents", role: .destructive) {
                    Task { await viewModel.clearAll() }
                }
            }
            .task(id: session.historyVersion) {
                await viewModel.load()
            }
        }
    }
}

private struct RecentCallRow: View {
    let record: CallRecord
    let onCallBack: () -> Void

    var body: some View {
        Button(action: onCallBack) {
            HStack(spacing: 12) {
                Image(systemName: record.direction == .incoming ? "phone.arrow.down.left" : "phone.arrow.up.right")
                    .font(.subheadline)
                    .foregroundStyle(record.isMissed ? Color.red : Color.secondary)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text(record.displayName)
                        .font(.body.weight(.medium))
                        .foregroundStyle(record.isMissed ? Color.red : Color.primary)
                    Text(RecentsViewModel.detailText(for: record))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(record.startedAt.formatted(date: .omitted, time: .shortened))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Calls \(record.displayName) back")
    }
}
