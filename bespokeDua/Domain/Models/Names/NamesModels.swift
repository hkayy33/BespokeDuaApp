import Foundation

struct FeelingLabel: Identifiable, Decodable, Sendable, Hashable {
    let feelingLabelId: Int
    let label: String
    let displayOrder: Int

    var id: Int { feelingLabelId }

    var titleLine: String {
        label
            .components(separatedBy: ",")
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? label
    }

    var subtitleLine: String? {
        let parts = label
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard parts.count > 1 else { return nil }
        return parts.dropFirst().joined(separator: ", ")
    }
}

struct AllahNameSummary: Identifiable, Decodable, Sendable, Hashable {
    let name: String
    let arabic: String
    let transliteration: String
    let translation: String
    let meaning: String

    var id: String { "\(transliteration)-\(arabic)" }
}

struct NamesByFeelingResponse: Decodable, Sendable {
    let feelingLabelId: Int
    let feelingLabel: String
    let names: [AllahNameSummary]
}

struct AllahNameDetail: Identifiable, Decodable, Sendable, Hashable {
    let number: Int
    let arabic: String
    let transliteration: String
    let translation: String
    let meaning: String
    let feelingLabelId: Int
    let feelingLabel: String
    let sortOrder: Int

    var id: Int { number }

    var summary: AllahNameSummary {
        AllahNameSummary(
            name: arabic,
            arabic: arabic,
            transliteration: transliteration,
            translation: translation,
            meaning: meaning
        )
    }
}
