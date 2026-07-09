import Foundation

struct DuaCollectionSummaryDTO: Codable, Identifiable, Hashable, Sendable {
    var id: String { collectionId }
    let collectionId: String
    let name: String
    let description: String?
    let duaCount: Int
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case collectionId
        case name
        case description
        case duaCount
        case createdAt
        case updatedAt
    }

    init(
        collectionId: String,
        name: String,
        description: String?,
        duaCount: Int,
        createdAt: Date,
        updatedAt: Date
    ) {
        self.collectionId = collectionId
        self.name = name
        self.description = description
        self.duaCount = duaCount
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

struct DuaCollectionDetailDTO: Codable, Identifiable, Sendable {
    var id: String { collectionId }
    let collectionId: String
    let name: String
    let description: String?
    let createdAt: Date
    let updatedAt: Date
    let savedDuas: [SavedDuaDTO]

    var savedDuaIds: [String] { savedDuas.map(\.duaId) }

    enum CodingKeys: String, CodingKey {
        case collectionId
        case name
        case description
        case createdAt
        case updatedAt
        case savedDuas
    }

    init(
        collectionId: String,
        name: String,
        description: String?,
        createdAt: Date,
        updatedAt: Date,
        savedDuas: [SavedDuaDTO]
    ) {
        self.collectionId = collectionId
        self.name = name
        self.description = description
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.savedDuas = savedDuas
    }
}

struct CreateDuaCollectionRequest: Encodable, Sendable {
    let userId: Int
    let name: String
    let description: String?
    let duaIds: [String]
}

struct UpdateDuaCollectionRequest: Encodable, Sendable {
    let name: String
    let description: String?
    let duaIds: [String]
}
