import SwiftUI

struct CallControlButton: View {
    let title: String
    let systemImage: String
    var isOn = false
    var isEnabled = true
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .frame(width: 72, height: 72)
                    .foregroundStyle(isOn ? Color.black : Color.white)
                    .background(Circle().fill(isOn ? Color.white : Color.white.opacity(0.15)))
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.4)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
