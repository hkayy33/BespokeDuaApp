import Foundation

/// Persists the most recent bespoke and sunnah dua searches so the home screen can show a Continue card.
enum HomeRecentActivity {
    enum Kind: String, Codable, Sendable {
        case bespoke
        case sunnah
    }

    struct StoredExplanation: Codable, Sendable {
        let name: String
        let explanation: String
    }

    struct StoredDua: Codable, Sendable {
        let id: UUID
        let duaText: String
        let explanations: [StoredExplanation]
        let storageJSON: String?
    }

    struct Snapshot: Codable, Sendable {
        let requestText: String
        let savedAt: Date
        let generated: [StoredDua]
        let isGenerating: Bool

        init(requestText: String, savedAt: Date, generated: [StoredDua], isGenerating: Bool = false) {
            self.requestText = requestText
            self.savedAt = savedAt
            self.generated = generated
            self.isGenerating = isGenerating
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            requestText = try container.decode(String.self, forKey: .requestText)
            savedAt = try container.decode(Date.self, forKey: .savedAt)
            generated = try container.decode([StoredDua].self, forKey: .generated)
            isGenerating = try container.decodeIfPresent(Bool.self, forKey: .isGenerating) ?? false
        }

        var isContinuable: Bool {
            let trimmed = requestText.trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmed.isEmpty && (isGenerating || !generated.isEmpty)
        }
    }

    struct SunnahStoredDua: Codable, Sendable {
        let id: Int
        let title: String
        let arabic: String
        let transliteration: String
        let translation: String
        let source: String
        let repeatCount: Int
    }

    struct SunnahStoredCategory: Codable, Sendable {
        let id: String
        let name: String
        let description: String
        let reason: String
        let duas: [SunnahStoredDua]
    }

    struct SunnahSnapshot: Codable, Sendable {
        let requestText: String
        let savedAt: Date
        let categories: [SunnahStoredCategory]
        let isGenerating: Bool

        init(
            requestText: String,
            savedAt: Date,
            categories: [SunnahStoredCategory],
            isGenerating: Bool = false
        ) {
            self.requestText = requestText
            self.savedAt = savedAt
            self.categories = categories
            self.isGenerating = isGenerating
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            requestText = try container.decode(String.self, forKey: .requestText)
            savedAt = try container.decode(Date.self, forKey: .savedAt)
            categories = try container.decode([SunnahStoredCategory].self, forKey: .categories)
            isGenerating = try container.decodeIfPresent(Bool.self, forKey: .isGenerating) ?? false
        }

        var isContinuable: Bool {
            let trimmed = requestText.trimmingCharacters(in: .whitespacesAndNewlines)
            return !trimmed.isEmpty && (isGenerating || !categories.isEmpty)
        }
    }

    struct ContinueCard: Sendable {
        let kind: Kind
        let requestText: String
        let savedAt: Date
        let isGenerating: Bool
        let bespokeSnapshot: Snapshot?
        let sunnahSnapshot: SunnahSnapshot?
    }

    private static func bespokeStorageKey(userId: Int) -> String {
        "bespoke.home.recentActivity.\(userId)"
    }

    private static func sunnahStorageKey(userId: Int) -> String {
        "bespoke.home.recentActivity.sunnah.\(userId)"
    }

    // MARK: - Bespoke

    static func save(
        userId: Int,
        requestText: String,
        generated: [DuaReceiver],
        isGenerating: Bool
    ) {
        let snapshot = Snapshot(
            requestText: requestText,
            savedAt: .now,
            generated: generated.map {
                StoredDua(
                    id: $0.id,
                    duaText: $0.duaText,
                    explanations: $0.explanations.map {
                        StoredExplanation(name: $0.name, explanation: $0.explanation)
                    },
                    storageJSON: $0.storageJSON
                )
            },
            isGenerating: isGenerating
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: bespokeStorageKey(userId: userId))
    }

    static func load(userId: Int) -> Snapshot? {
        guard let data = UserDefaults.standard.data(forKey: bespokeStorageKey(userId: userId)) else { return nil }
        guard let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data) else { return nil }
        return snapshot.isContinuable ? snapshot : nil
    }

    static func clear(userId: Int) {
        UserDefaults.standard.removeObject(forKey: bespokeStorageKey(userId: userId))
    }

    static func duaReceivers(from snapshot: Snapshot) -> [DuaReceiver] {
        snapshot.generated.map { stored in
            DuaReceiver(
                id: stored.id,
                duaText: stored.duaText,
                explanations: stored.explanations.map {
                    ExplanationModel(name: $0.name, explanation: $0.explanation)
                },
                storageJSON: stored.storageJSON
            )
        }
    }

    // MARK: - Sunnah

    static func saveSunnah(
        userId: Int,
        requestText: String,
        response: SunnahDuaRecommendResponse?,
        isGenerating: Bool
    ) {
        let snapshot = SunnahSnapshot(
            requestText: requestText,
            savedAt: .now,
            categories: response.map { storedCategories(from: $0.categories) } ?? [],
            isGenerating: isGenerating
        )
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: sunnahStorageKey(userId: userId))
    }

    static func loadSunnah(userId: Int) -> SunnahSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: sunnahStorageKey(userId: userId)) else { return nil }
        guard let snapshot = try? JSONDecoder().decode(SunnahSnapshot.self, from: data) else { return nil }
        return snapshot.isContinuable ? snapshot : nil
    }

    static func clearSunnah(userId: Int) {
        UserDefaults.standard.removeObject(forKey: sunnahStorageKey(userId: userId))
    }

    static func sunnahResponse(from snapshot: SunnahSnapshot) -> SunnahDuaRecommendResponse {
        SunnahDuaRecommendResponse(
            userInput: snapshot.requestText,
            categories: snapshot.categories.map { stored in
                SunnahDuaCategoryResult(
                    id: stored.id,
                    name: stored.name,
                    description: stored.description,
                    reason: stored.reason,
                    duas: stored.duas.map { dua in
                        SunnahDuaItem(
                            id: dua.id,
                            title: dua.title,
                            arabic: dua.arabic,
                            transliteration: dua.transliteration,
                            translation: dua.translation,
                            source: dua.source,
                            repeatCount: dua.repeatCount
                        )
                    }
                )
            }
        )
    }

    // MARK: - Continue

    static func mostRecent(userId: Int) -> ContinueCard? {
        let bespoke = load(userId: userId)
        let sunnah = loadSunnah(userId: userId)

        switch (bespoke, sunnah) {
        case (nil, nil):
            return nil
        case (let bespoke?, nil):
            return continueCard(kind: .bespoke, bespoke: bespoke)
        case (nil, let sunnah?):
            return continueCard(kind: .sunnah, sunnah: sunnah)
        case (let bespoke?, let sunnah?):
            if bespoke.savedAt >= sunnah.savedAt {
                return continueCard(kind: .bespoke, bespoke: bespoke)
            }
            return continueCard(kind: .sunnah, sunnah: sunnah)
        }
    }

    private static func continueCard(kind: Kind, bespoke: Snapshot) -> ContinueCard {
        ContinueCard(
            kind: kind,
            requestText: bespoke.requestText,
            savedAt: bespoke.savedAt,
            isGenerating: bespoke.isGenerating,
            bespokeSnapshot: bespoke,
            sunnahSnapshot: nil
        )
    }

    private static func continueCard(kind: Kind, sunnah: SunnahSnapshot) -> ContinueCard {
        ContinueCard(
            kind: kind,
            requestText: sunnah.requestText,
            savedAt: sunnah.savedAt,
            isGenerating: sunnah.isGenerating,
            bespokeSnapshot: nil,
            sunnahSnapshot: sunnah
        )
    }

    private static func storedCategories(from categories: [SunnahDuaCategoryResult]) -> [SunnahStoredCategory] {
        categories.map { category in
            SunnahStoredCategory(
                id: category.id,
                name: category.name,
                description: category.description,
                reason: category.reason,
                duas: category.duas.map { dua in
                    SunnahStoredDua(
                        id: dua.id,
                        title: dua.title,
                        arabic: dua.arabic,
                        transliteration: dua.transliteration,
                        translation: dua.translation,
                        source: dua.source,
                        repeatCount: dua.repeatCount
                    )
                }
            )
        }
    }
}
