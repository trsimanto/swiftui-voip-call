import CallCore
import SwiftUI

/// Four signal bars driven by the MOS estimate from `CallQuality`.
struct CallQualityIndicator: View {
    let quality: CallQuality
    var showsLabel = true

    var body: some View {
        HStack(spacing: 8) {
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(1...4, id: \.self) { level in
                    Capsule()
                        .fill(level <= quality.bars ? tint : Color.white.opacity(0.25))
                        .frame(width: 4, height: CGFloat(4 + level * 4))
                }
            }
            .frame(height: 20, alignment: .bottom)

            if showsLabel {
                Text(quality.label)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.75))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(Color.white.opacity(0.08)))
        .animation(.easeInOut, value: quality)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(quality.label)
    }

    private var tint: Color {
        switch quality {
        case .excellent, .good: return .green
        case .fair: return .yellow
        case .poor: return .red
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        ForEach(CallQuality.allCases, id: \.self) { CallQualityIndicator(quality: $0) }
    }
    .padding()
    .background(Color.black)
}
