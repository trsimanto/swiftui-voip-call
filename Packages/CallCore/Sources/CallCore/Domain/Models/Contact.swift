import Foundation

public struct Contact: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let name: String
    /// Phone number or SIP URI user part.
    public let handle: String
    public let isFavorite: Bool

    public init(id: String, name: String, handle: String, isFavorite: Bool = false) {
        self.id = id
        self.name = name
        self.handle = handle
        self.isFavorite = isFavorite
    }

    public var initials: String {
        Self.initials(from: name)
    }

    /// "Ayesha Rahman" -> "AR", "Jean-Luc Picard" -> "JL", "" -> "#".
    public static func initials(from name: String) -> String {
        let parts = name
            .split(whereSeparator: { $0 == " " || $0 == "-" })
            .prefix(2)
            .compactMap(\.first)
        let letters = String(parts).uppercased()
        return letters.isEmpty ? "#" : letters
    }

    public func matches(_ query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        if name.range(of: trimmed, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
            return true
        }
        // Compare digits only so "5550100" matches "+1 (555) 010-0100".
        let queryDigits = trimmed.filter(\.isNumber)
        return !queryDigits.isEmpty && handle.filter(\.isNumber).contains(queryDigits)
    }
}
