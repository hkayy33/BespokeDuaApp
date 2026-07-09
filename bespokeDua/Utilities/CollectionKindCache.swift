import Foundation

enum CollectionKindCache {
    private static func storageKey(userId: Int, collectionId: String) -> String {
        "bespoke.collection.kind.\(userId).\(collectionId)"
    }

    static func store(userId: Int, collectionId: String, kind: SavedDuaKind) {
        UserDefaults.standard.set(kind.rawValue, forKey: storageKey(userId: userId, collectionId: collectionId))
    }

    static func kind(userId: Int?, collectionId: String) -> SavedDuaKind? {
        guard let userId,
              let raw = UserDefaults.standard.string(forKey: storageKey(userId: userId, collectionId: collectionId)),
              let kind = SavedDuaKind(rawValue: raw) else {
            return nil
        }
        return kind
    }

    static func remove(userId: Int, collectionId: String) {
        UserDefaults.standard.removeObject(forKey: storageKey(userId: userId, collectionId: collectionId))
    }
}

enum DuaCollectionDisplay {
    static func inferredKind(from duas: [SavedDuaDTO]) -> SavedDuaKind? {
        guard !duas.isEmpty else { return nil }

        let kinds = Set(duas.map { SavedDuaDisplay.kind(from: $0) })
        if kinds.count == 1, let only = kinds.first {
            return only
        }

        let sunnahCount = duas.filter { SavedDuaDisplay.kind(from: $0) == .sunnah }.count
        return sunnahCount > duas.count / 2 ? .sunnah : .bespoke
    }

    static func kind(
        for collection: DuaCollectionSummaryDTO,
        userId: Int?,
        detailDuas: [SavedDuaDTO] = []
    ) -> SavedDuaKind {
        if let userId,
           let cached = CollectionKindCache.kind(userId: userId, collectionId: collection.collectionId) {
            return cached
        }

        if let inferred = inferredKind(from: detailDuas) {
            return inferred
        }

        return .bespoke
    }
}
