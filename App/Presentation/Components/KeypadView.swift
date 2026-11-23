import SwiftUI

/// 12-key phone keypad, shared by the dialer and the in-call DTMF pad.
struct KeypadView: View {
    enum Style {
        case light
        case dark
    }

    var style: Style = .light
    let onKey: (String) -> Void
    var onLongPressZero: (() -> Void)?

    private static let keys: [(digit: String, letters: String)] = [
        ("1", ""), ("2", "ABC"), ("3", "DEF"),
        ("4", "GHI"), ("5", "JKL"), ("6", "MNO"),
        ("7", "PQRS"), ("8", "TUV"), ("9", "WXYZ"),
        ("*", ""), ("0", "+"), ("#", "")
    ]

    var body: some View {
        Grid(horizontalSpacing: 24, verticalSpacing: 16) {
            ForEach(0..<4, id: \.self) { row in
                GridRow {
                    ForEach(0..<3, id: \.self) { column in
                        let key = Self.keys[row * 3 + column]
                        KeypadKey(
                            digit: key.digit,
                            letters: key.letters,
                            style: style,
                            onTap: { onKey(key.digit) },
                            onLongPress: key.digit == "0" ? onLongPressZero : nil
                        )
                    }
                }
            }
        }
    }
}

private struct KeypadKey: View {
    let digit: String
    let letters: String
    let style: KeypadView.Style
    let onTap: () -> Void
    let onLongPress: (() -> Void)?

    @State private var isPressed = false

    var body: some View {
        VStack(spacing: 0) {
            Text(digit)
                .font(.system(size: 32, weight: .regular, design: .rounded))
            Text(letters.isEmpty ? " " : letters)
                .font(.system(size: 10, weight: .semibold))
                .tracking(1.5)
                .opacity(0.7)
        }
        .foregroundStyle(style == .dark ? Color.white : Color.primary)
        .frame(width: 76, height: 76)
        .background(Circle().fill(background))
        .scaleEffect(isPressed ? 0.94 : 1)
        .contentShape(Circle())
        .onTapGesture {
            flash()
            onTap()
        }
        .onLongPressGesture(minimumDuration: 0.5) {
            if let onLongPress {
                flash()
                onLongPress()
            } else {
                onTap()
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(digit)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { onTap() }
    }

    private var background: Color {
        let base = style == .dark ? Color.white.opacity(0.15) : Color(.systemGray5)
        return isPressed ? base.opacity(0.5) : base
    }

    private func flash() {
        isPressed = true
        withAnimation(.easeOut(duration: 0.2)) {
            isPressed = false
        }
    }
}

#Preview {
    KeypadView { print($0) }
        .padding()
}
