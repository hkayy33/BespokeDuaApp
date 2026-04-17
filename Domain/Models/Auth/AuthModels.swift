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

/// Matches `LoginResponseDto`: `{ "message", "user": GetUserDto }`.
struct LoginResponse: Decodable, Sendable {
    let message: String?
    let user: AuthUser
}

struct CreateSavedDuaRequest: Encodable, Sendable {
    let userId: Int
    let dua: String
}

struct SavedDuaDTO: Codable, Identifiable, Sendable {
    var id: String { duaId }
    let duaId: String
    let dua: String
    let createdAt: Date
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
