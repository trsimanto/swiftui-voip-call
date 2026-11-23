import Foundation
import Observation

@MainActor
@Observable
final class DialerViewModel {
    static let maxLength = 24
    private static let allowedCharacters = Set("0123456789*#+")

    private(set) var number = ""

    var canCall: Bool {
        number.contains(where: \.isNumber)
    }

    func press(_ key: String) {
        guard
            !key.isEmpty,
            number.count + key.count <= Self.maxLength,
            key.allSatisfy({ Self.allowedCharacters.contains($0) })
        else { return }

        // "+" is only meaningful as the international prefix.
        if key.contains("+") {
            guard key == "+", number.isEmpty else { return }
        }
        number += key
    }

    /// Long-pressing 0 on a phone keypad types "+".
    func longPressZero() {
        if number.isEmpty {
            press("+")
        } else {
            press("0")
        }
    }

    func deleteLast() {
        guard !number.isEmpty else { return }
        number.removeLast()
    }

    func clear() {
        number = ""
    }

    /// Accepts pasted numbers like "+1 (555) 010-0101" by dropping formatting.
    func paste(_ text: String) {
        var result = ""
        for character in text where Self.allowedCharacters.contains(character) {
            if character == "+" && !result.isEmpty { continue }
            result.append(character)
            if result.count == Self.maxLength { break }
        }
        number = result
    }
}
