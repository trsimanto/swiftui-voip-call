import SwiftUI
import UIKit

@MainActor
struct DialerView: View {
    let viewModel: DialerViewModel
    @Environment(CallSession.self) private var session

    var body: some View {
        NavigationStack {
            VStack(spacing: 28) {
                Spacer()

                Text(viewModel.number.isEmpty ? " " : viewModel.number)
                    .font(.system(size: 38, weight: .light, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.5)
                    .truncationMode(.head)
                    .padding(.horizontal, 32)
                    .accessibilityLabel(viewModel.number.isEmpty ? "No number entered" : viewModel.number)
                    .contextMenu {
                        Button("Paste", systemImage: "doc.on.clipboard") {
                            if let text = UIPasteboard.general.string {
                                viewModel.paste(text)
                            }
                        }
                    }

                KeypadView(
                    style: .light,
                    onKey: { viewModel.press($0) },
                    onLongPressZero: { viewModel.longPressZero() }
                )

                HStack(spacing: 24) {
                    Color.clear.frame(width: 76, height: 76)

                    Button {
                        session.startCall(handle: viewModel.number, name: nil)
                    } label: {
                        Image(systemName: "phone.fill")
                            .font(.title)
                            .foregroundStyle(.white)
                            .frame(width: 76, height: 76)
                            .background(Circle().fill(Color.green))
                    }
                    .buttonStyle(.plain)
                    .disabled(!viewModel.canCall)
                    .opacity(viewModel.canCall ? 1 : 0.5)
                    .accessibilityLabel("Call")

                    Button {
                        viewModel.deleteLast()
                    } label: {
                        Image(systemName: "delete.left.fill")
                            .font(.title2)
                            .foregroundStyle(.secondary)
                            .frame(width: 76, height: 76)
                    }
                    .buttonStyle(.plain)
                    .opacity(viewModel.number.isEmpty ? 0 : 1)
                    .disabled(viewModel.number.isEmpty)
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.6).onEnded { _ in viewModel.clear() }
                    )
                    .accessibilityLabel("Delete")
                }

                Spacer()
            }
            .navigationTitle("Keypad")
            .toolbar(.hidden, for: .navigationBar)
        }
    }
}
