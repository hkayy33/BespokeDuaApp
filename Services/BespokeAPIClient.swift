import Foundation

struct BespokeAPIClient: Sendable {
    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL = APIBaseURL.current, session: URLSession = .shared) {
        self.baseURL = APIBaseURL.withTrailingSlash(baseURL)
        self.session = session
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoBasic = ISO8601DateFormatter()
        isoBasic.formatOptions = [.withInternetDateTime]
        decoder.dateDecodingStrategy = .custom { container in
            let str = try container.singleValueContainer().decode(String.self)
            if let d = iso.date(from: str) { return d }
            if let d = isoBasic.date(from: str) { return d }
            throw DecodingError.dataCorrupted(.init(codingPath: container.codingPath, debugDescription: "Invalid date: \(str)"))
        }
        return decoder
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.keyEncodingStrategy = .useDefaultKeys
        return e
    }()

    private func request(path: String, method: String) throws -> URLRequest {
        guard let url = URL(string: path, relativeTo: baseURL)?.absoluteURL else {
            throw BespokeAPIError.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = method
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        return req
    }

    private func request<T: Encodable>(path: String, method: String, body: T) throws -> URLRequest {
        var req = try request(path: path, method: method)
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try Self.encoder.encode(body)
        return req
    }

    private func data(for req: URLRequest) async throws -> (Data, URLResponse) {
        do {
            return try await session.data(for: req)
        } catch {
            throw BespokeAPIError.transport(error)
        }
    }

    private func decodeServerMessage(from data: Data) -> String? {
        struct Envelope: Decodable { let message: String? }
        return (try? JSONDecoder().decode(Envelope.self, from: data))?.message
    }

    func login(_ dto: LoginRequest) async throws -> AuthUser {
        let req = try request(path: "Auth/login", method: "POST", body: dto)
        let (data, resp) = try await data(for: req)
        try throwIfNeeded(data: data, response: resp)
        do {
            let decoded = try Self.makeDecoder().decode(LoginResponse.self, from: data)
            return decoded.user
        } catch {
            throw BespokeAPIError.decoding(error)
        }
    }

    func register(_ dto: RegisterRequest) async throws -> AuthUser {
        let req = try request(path: "Auth/register", method: "POST", body: dto)
        let (data, resp) = try await data(for: req)
        try throwIfNeeded(data: data, response: resp)
        do {
            return try Self.makeDecoder().decode(AuthUser.self, from: data)
        } catch {
            throw BespokeAPIError.decoding(error)
        }
    }

    func generateDuas(text: String, userId: Int?) async throws -> [DuaReceiver] {
        let body = GenerateDuaRequestBody(text: text, userId: userId)
        let req = try request(path: "Dua/generate", method: "POST", body: body)
        let (data, resp) = try await data(for: req)
        try throwIfNeeded(data: data, response: resp)
        let decoded: GenerateDuaResponse
        do {
            decoded = try Self.makeDecoder().decode(GenerateDuaResponse.self, from: data)
        } catch {
            throw BespokeAPIError.decoding(error)
        }
        return decoded.duas.map { item in
            let explanations = item.explanations.map {
                ExplanationModel(name: $0.name, explanation: $0.explanation)
            }
            return DuaReceiver(duaText: item.dua, explanations: explanations)
        }
    }

    func savedDuas(forUserId userId: Int) async throws -> [SavedDuaDTO] {
        let req = try request(path: "SavedDuas/user/\(userId)", method: "GET")
        let (data, resp) = try await data(for: req)
        try throwIfNeeded(data: data, response: resp)
        do {
            return try Self.makeDecoder().decode([SavedDuaDTO].self, from: data)
        } catch {
            throw BespokeAPIError.decoding(error)
        }
    }

    func saveDua(userId: Int, duaText: String) async throws -> SavedDuaDTO {
        let body = CreateSavedDuaRequest(userId: userId, dua: duaText)
        let req = try request(path: "SavedDuas", method: "POST", body: body)
        let (data, resp) = try await data(for: req)
        try throwIfNeeded(data: data, response: resp)
        do {
            return try Self.makeDecoder().decode(SavedDuaDTO.self, from: data)
        } catch {
            throw BespokeAPIError.decoding(error)
        }
    }

    func deleteSavedDua(id: String) async throws {
        let req = try request(path: "SavedDuas/\(id)", method: "DELETE")
        let (data, resp) = try await data(for: req)
        try throwIfNeeded(data: data, response: resp)
    }

    /// `DELETE api/Auth/account`. Backend expects `Authorization: Bearer <userId>` (numeric id as string), not a JWT.
    func deleteAccount(authorizedUserId userId: Int) async throws {
        var req = try request(path: "Auth/account", method: "DELETE")
        req.setValue("Bearer \(userId)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await data(for: req)
        try throwIfNeeded(data: data, response: resp)
    }

    private func throwIfNeeded(data: Data, response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200 ..< 300).contains(http.statusCode) else {
            let msg = decodeServerMessage(from: data)
            throw BespokeAPIError.status(http.statusCode, msg)
        }
    }
}
