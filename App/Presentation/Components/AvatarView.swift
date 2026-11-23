import CallCore
import SwiftUI

struct AvatarView: View {
    let name: String
    var size: CGFloat = 44

    var body: some View {
        let colors = Self.palette(for: name)
        Text(Contact.initials(from: name))
            .font(.system(size: size * 0.38, weight: .semibold, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(
                Circle().fill(LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .accessibilityHidden(true)
    }

    private static let palettes: [[Color]] = [
        [.blue, .indigo],
        [.teal, .blue],
        [.orange, .pink],
        [.purple, .indigo],
        [.green, .teal],
        [.pink, .purple]
    ]

    /// Stable per name, unlike `hashValue`, which is seeded per launch.
    static func palette(for name: String) -> [Color] {
        let sum = name.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        return palettes[sum % palettes.count]
    }
}

#Preview {
    HStack {
        AvatarView(name: "Ayesha Rahman", size: 64)
        AvatarView(name: "Mei Tanaka", size: 64)
        AvatarView(name: "Support Desk", size: 64)
    }
}
