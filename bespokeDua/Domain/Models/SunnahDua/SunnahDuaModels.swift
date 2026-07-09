import Foundation

struct SunnahDuaRecommendRequest: Encodable, Sendable {
    let text: String
    let userId: Int?
    let maxCategories: Int?
    let duasPerCategory: Int?

    init(
        text: String,
        userId: Int? = nil,
        maxCategories: Int? = nil,
        duasPerCategory: Int? = nil
    ) {
        self.text = text
        self.userId = userId
        self.maxCategories = maxCategories
        self.duasPerCategory = duasPerCategory
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(text, forKey: .text)
        try container.encodeIfPresent(userId, forKey: .userId)
        try container.encodeIfPresent(maxCategories, forKey: .maxCategories)
        try container.encodeIfPresent(duasPerCategory, forKey: .duasPerCategory)
    }

    private enum CodingKeys: String, CodingKey {
        case text, userId, maxCategories, duasPerCategory
    }
}

struct SunnahDuaRecommendResponse: Decodable, Sendable {
    let userInput: String
    let categories: [SunnahDuaCategoryResult]

    init(userInput: String, categories: [SunnahDuaCategoryResult]) {
        self.userInput = userInput
        self.categories = categories
    }
}

struct SunnahDuaCategoryResult: Decodable, Sendable, Identifiable {
    let id: String
    let name: String
    let description: String
    let reason: String
    let duas: [SunnahDuaItem]

    init(id: String, name: String, description: String, reason: String, duas: [SunnahDuaItem]) {
        self.id = id
        self.name = name
        self.description = description
        self.reason = reason
        self.duas = duas
    }
}

struct SunnahDuaItem: Decodable, Sendable, Identifiable {
    let id: Int
    let title: String
    let arabic: String
    let transliteration: String
    let translation: String
    let source: String
    let repeatCount: Int

    init(
        id: Int,
        title: String,
        arabic: String,
        transliteration: String,
        translation: String,
        source: String,
        repeatCount: Int
    ) {
        self.id = id
        self.title = title
        self.arabic = arabic
        self.transliteration = transliteration
        self.translation = translation
        self.source = source
        self.repeatCount = repeatCount
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, arabic, transliteration, translation, source
        case repeatCount = "repeat"
    }
}

struct SunnahDuaCategorySummary: Decodable, Sendable, Identifiable {
    let id: String
    let name: String
    let description: String
}

struct CreateSavedSunnahDuaRequest: Encodable, Sendable {
    let userId: Int
    let sunnahDua: String
}

struct SavedSunnahDuaDTO: Codable, Identifiable, Sendable, Equatable {
    var id: String { savedSunnahDuaId }
    let savedSunnahDuaId: String
    let sunnahDua: String
    let createdAt: Date

    init(savedSunnahDuaId: String, sunnahDua: String, createdAt: Date) {
        self.savedSunnahDuaId = savedSunnahDuaId
        self.sunnahDua = sunnahDua
        self.createdAt = createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: FlexibleKeys.self)
        if let sunnahDuaId = try container.decodeIfPresent(String.self, forKey: .sunnahDuaId) {
            savedSunnahDuaId = sunnahDuaId
        } else {
            savedSunnahDuaId = try container.decode(String.self, forKey: .id)
        }
        sunnahDua = try container.decode(String.self, forKey: .sunnahDua)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: FlexibleKeys.self)
        try container.encode(savedSunnahDuaId, forKey: .sunnahDuaId)
        try container.encode(sunnahDua, forKey: .sunnahDua)
        try container.encode(createdAt, forKey: .createdAt)
    }

    func asSavedDuaDTO() -> SavedDuaDTO {
        SavedDuaDTO(duaId: savedSunnahDuaId, dua: sunnahDua, createdAt: createdAt)
    }

    private enum FlexibleKeys: String, CodingKey {
        case sunnahDuaId
        case id
        case sunnahDua
        case createdAt
    }
}

struct SunnahDuaSavedPayload: Codable, Sendable {
    let id: Int
    let category: String
    let title: String
    let arabic: String
    let transliteration: String
    let translation: String
    let source: String
    let repeatCount: Int

    enum CodingKeys: String, CodingKey {
        case id, category, title, arabic, transliteration, translation, source
        case repeatCount = "repeat"
    }
}

enum SunnahDuaDisplay {
    static func cardBody(for item: SunnahDuaItem) -> String {
        cardBody(
            arabic: item.arabic,
            transliteration: item.transliteration,
            translation: item.translation
        )
    }

    static func cardBody(from payload: SunnahDuaSavedPayload) -> String {
        cardBody(
            arabic: payload.arabic,
            transliteration: payload.transliteration,
            translation: payload.translation
        )
    }

    static func cardBody(arabic: String, transliteration: String = "", translation: String) -> String {
        [arabic, transliteration, translation]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: "\n\n")
    }

    static func copyText(for item: SunnahDuaItem) -> String {
        var lines = [item.title]
        if !item.arabic.isEmpty { lines.append(item.arabic) }
        if !item.transliteration.isEmpty { lines.append(item.transliteration) }
        if !item.translation.isEmpty { lines.append(item.translation) }
        if !item.source.isEmpty { lines.append("— \(item.source)") }
        return lines.joined(separator: "\n\n")
    }

    static func duaReceiver(from item: SunnahDuaItem, category: SunnahDuaCategoryResult) -> DuaReceiver {
        let explanations = [
            ExplanationModel(name: category.name, explanation: category.reason),
            ExplanationModel(name: "Source", explanation: item.source),
        ]
        return DuaReceiver(
            duaText: cardBody(for: item),
            explanations: explanations,
            storageJSON: jsonForSavedSunnahDuaField(from: item, category: category)
        )
    }

    static func jsonForSavedSunnahDuaField(from item: SunnahDuaItem, category: SunnahDuaCategoryResult) -> String {
        let payload = SunnahDuaSavedPayload(
            id: item.id,
            category: category.id,
            title: item.title,
            arabic: item.arabic,
            transliteration: item.transliteration,
            translation: item.translation,
            source: item.source,
            repeatCount: item.repeatCount
        )
        guard let data = try? JSONEncoder().encode(payload),
              let str = String(data: data, encoding: .utf8) else {
            return cardBody(for: item)
        }
        return str
    }

    static func item(from payload: SunnahDuaSavedPayload) -> SunnahDuaItem {
        SunnahDuaItem(
            id: payload.id,
            title: payload.title,
            arabic: payload.arabic,
            transliteration: payload.transliteration,
            translation: payload.translation,
            source: payload.source,
            repeatCount: payload.repeatCount
        )
    }

    static func savedPayload(from row: SavedDuaDTO) -> SunnahDuaSavedPayload? {
        let raw = row.dua.trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw.hasPrefix("{"), let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(SunnahDuaSavedPayload.self, from: data)
    }

    static func jsonForSavedDuaField(from item: SunnahDuaItem, category: SunnahDuaCategoryResult) -> String {
        jsonForSavedSunnahDuaField(from: item, category: category)
    }

    static func savedItemKey(categoryId: String, duaId: Int) -> String {
        "\(categoryId)-\(duaId)"
    }
}
