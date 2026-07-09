import Foundation

enum DuaCollectionIcons {
    static let defaultSymbol = "folder.fill"

    static let options: [String] = [
        "folder.fill",
        "heart.text.square.fill",
        "sparkles",
        "moon.stars.fill",
        "leaf.fill",
        "book.closed.fill",
        "star.fill",
        "sun.max.fill",
        "hands.sparkles.fill",
        "gift.fill",
        "flame.fill",
        "drop.fill"
    ]
}

enum CollectionIconCache {
    private static func storageKey(userId: Int, collectionId: String) -> String {
        "bespoke.collection.icon.\(userId).\(collectionId)"
    }

    static func store(userId: Int, collectionId: String, symbolName: String) {
        let normalized = DuaCollectionIcons.options.contains(symbolName) ? symbolName : DuaCollectionIcons.defaultSymbol
        UserDefaults.standard.set(normalized, forKey: storageKey(userId: userId, collectionId: collectionId))
    }

    static func symbol(userId: Int?, collectionId: String) -> String {
        guard let userId else { return DuaCollectionIcons.defaultSymbol }
        return UserDefaults.standard.string(forKey: storageKey(userId: userId, collectionId: collectionId))
            ?? DuaCollectionIcons.defaultSymbol
    }

    static func remove(userId: Int, collectionId: String) {
        UserDefaults.standard.removeObject(forKey: storageKey(userId: userId, collectionId: collectionId))
    }
}
