import Foundation

struct AuthUser: Codable, Equatable, Sendable {
    let userId: Int
    let username: String
    let email: String
    let plan: String
    let lastRequestDate: String?
}

struct LoginRequest: Encodable, Sendable {
    let email: String
    let password: String
}

struct RegisterRequest: Encodable, Sendable {
    let username: String
    let email: String
    let password: String
}

struct SyncProfileRequest: Encodable, Sendable {
    let username: String?
}

struct UpdateUsernameRequest: Encodable, Sendable {
    let username: String
}

enum UsernameRules {
    /// `^[a-zA-Z0-9][a-zA-Z0-9_-]{0,98}$` — 2–100 chars; cannot start with `-`.
    private static let pattern = #"^[a-zA-Z0-9][a-zA-Z0-9_-]{0,98}$"#

    static let hint = "2–100 characters. Letters, numbers, underscores, or hyphens (cannot start with a hyphen)."
    static let invalidMessage = "Use letters, numbers, underscores, or hyphens (cannot start with a hyphen)."

    static func isValid(_ username: String) -> Bool {
        username.range(of: pattern, options: .regularExpression) != nil
    }
}

enum RegisterResult: Sendable {
    case signedIn(AuthUser)
    case awaitingVerification(email: String)
    case failed
}

/// Matches `LoginResponseDto`: `{ "message", "user": GetUserDto }`.
struct LoginResponse: Decodable, Sendable {
    let message: String?
    let user: AuthUser
}

struct CreateSavedDuaRequest: Encodable, Sendable {
    let userId: Int
    let dua: String
}

struct UpdateSavedDuaRequest: Encodable, Sendable {
    let dua: String
}

struct SavedDuaDTO: Codable, Identifiable, Sendable, Equatable {
    var id: String { duaId }
    let duaId: String
    let dua: String
    let createdAt: Date
    let updatedAt: Date?

    init(duaId: String, dua: String, createdAt: Date, updatedAt: Date? = nil) {
        self.duaId = duaId
        self.dua = dua
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        duaId = try container.decode(String.self, forKey: .duaId)
        dua = try container.decode(String.self, forKey: .dua)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decodeIfPresent(Date.self, forKey: .updatedAt)
    }

    private enum CodingKeys: String, CodingKey {
        case duaId
        case dua
        case createdAt
        case updatedAt
    }
}

struct GenerateDuaResponse: Decodable, Sendable {
    let duas: [GeneratedDuaItemDTO]
}

struct GeneratedDuaItemDTO: Decodable, Sendable {
    let dua: String
    let explanations: [GeneratedExplanationDTO]
}

struct GeneratedExplanationDTO: Decodable, Sendable {
    let name: String
    let explanation: String
}

struct GenerateDuaRequestBody: Encodable, Sendable {
    let text: String
    let userId: Int?
}

struct SubscribePlanRequest: Encodable, Sendable {
    let originalTransactionId: String?
    let productId: String
    let confirmTransfer: Bool
}

enum BespokeAPIError: LocalizedError, Sendable {
    case invalidURL
    case status(Int, String?)
    case decoding(Error)
    case transport(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Invalid request URL."
        case let .status(code, message):
            if let message, !message.isEmpty { return message }
            return "Request failed (\(code))."
        case let .decoding(error):
            return "Could not read response: \(error.localizedDescription)"
        case let .transport(error):
            return error.localizedDescription
        }
    }
}
