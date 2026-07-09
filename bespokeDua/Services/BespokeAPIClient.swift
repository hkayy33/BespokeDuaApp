import Foundation

struct BespokeAPIClient: Sendable {
    private let baseURL: URL
    private let session: URLSession

    init(baseURL: URL = APIBaseURL.current, session: URLSession = .shared) {
        self.baseURL = APIBaseURL.withTrailingSlash(baseURL)
        self.session = session
    }

    private nonisolated static func parseISO8601Date(_ string: String) -> Date? {
        let withFractionalSeconds = ISO8601DateFormatter()
        withFractionalSeconds.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = withFractionalSeconds.date(from: string) { return date }

        let basic = ISO8601DateFormatter()
        basic.formatOptions = [.withInternetDateTime]
        return basic.date(from: string)
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .useDefaultKeys
        decoder.dateDecodingStrategy = .custom { container in
            let str = try container.singleValueContainer().decode(String.self)
            if let date = parseISO8601Date(str) { return date }
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
        if let message = (try? JSONDecoder().decode(Envelope.self, from: data))?.message,
           !message.isEmpty {
            return message
        }
        guard let text = String(data: data, encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            !text.isEmpty,
            !text.hasPrefix("{") else {
            return nil
        }
        return text
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

    func syncProfile(username: String?, bearerToken: String?) async throws -> AuthUser {
        let body = SyncProfileRequest(username: username)
        var req = try request(path: "Auth/sync", method: "POST", body: body)
        if let bearerToken, !bearerToken.isEmpty {
            req.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        let (data, resp) = try await data(for: req)
        try throwIfNeeded(data: data, response: resp)
        do {
            return try Self.makeDecoder().decode(AuthUser.self, from: data)
        } catch {
            throw BespokeAPIError.decoding(error)
        }
    }

    /// `PATCH api/Auth/username`. Bearer is Supabase JWT or legacy numeric `userId`.
    func updateUsername(bearerToken: String, username: String) async throws -> AuthUser {
        let body = UpdateUsernameRequest(username: username)
        var req = try request(path: "Auth/username", method: "PATCH", body: body)
        req.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
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

    func updateSavedDua(id: String, dua: String) async throws -> SavedDuaDTO {
        let body = UpdateSavedDuaRequest(dua: dua)
        let req = try request(path: "SavedDuas/\(id)", method: "PUT", body: body)
        let (data, resp) = try await data(for: req)
        try throwIfNeeded(data: data, response: resp)
        do {
            return try Self.makeDecoder().decode(SavedDuaDTO.self, from: data)
        } catch {
            throw BespokeAPIError.decoding(error)
        }
    }

    func savedSunnahDuas(forUserId userId: Int) async throws -> [SavedSunnahDuaDTO] {
        let req = try request(path: "SavedSunnahDuas/user/\(userId)", method: "GET")
        let (data, resp) = try await data(for: req)
        try throwIfNeeded(data: data, response: resp)
        do {
            return try Self.makeDecoder().decode([SavedSunnahDuaDTO].self, from: data)
        } catch {
            throw BespokeAPIError.decoding(error)
        }
    }

    func saveSunnahDua(userId: Int, sunnahDua: String) async throws -> SavedSunnahDuaDTO {
        let body = CreateSavedSunnahDuaRequest(userId: userId, sunnahDua: sunnahDua)
        let req = try request(path: "SavedSunnahDuas", method: "POST", body: body)
        let (data, resp) = try await data(for: req)
        try throwIfNeeded(data: data, response: resp)
        do {
            return try Self.makeDecoder().decode(SavedSunnahDuaDTO.self, from: data)
        } catch {
            throw BespokeAPIError.decoding(error)
        }
    }

    func deleteSavedSunnahDua(id: String) async throws {
        let req = try request(path: "SavedSunnahDuas/\(id)", method: "DELETE")
        let (data, resp) = try await data(for: req)
        try throwIfNeeded(data: data, response: resp)
    }

    func duaCollections(forUserId userId: Int) async throws -> [DuaCollectionSummaryDTO] {
        let req = try request(path: "DuaCollections/user/\(userId)", method: "GET")
        let (data, resp) = try await data(for: req)
        try throwIfNeeded(data: data, response: resp)
        do {
            return try Self.makeDecoder().decode([DuaCollectionSummaryDTO].self, from: data)
        } catch {
            throw BespokeAPIError.decoding(error)
        }
    }

    func duaCollection(id: String) async throws -> DuaCollectionDetailDTO {
        let req = try request(path: "DuaCollections/\(id)", method: "GET")
        let (data, resp) = try await data(for: req)
        try throwIfNeeded(data: data, response: resp)
        do {
            return try Self.makeDecoder().decode(DuaCollectionDetailDTO.self, from: data)
        } catch {
            throw BespokeAPIError.decoding(error)
        }
    }

    func createDuaCollection(_ body: CreateDuaCollectionRequest) async throws -> DuaCollectionDetailDTO {
        let req = try request(path: "DuaCollections", method: "POST", body: body)
        let (data, resp) = try await data(for: req)
        try throwIfNeeded(data: data, response: resp)
        do {
            return try Self.makeDecoder().decode(DuaCollectionDetailDTO.self, from: data)
        } catch {
            throw BespokeAPIError.decoding(error)
        }
    }

    func updateDuaCollection(id: String, body: UpdateDuaCollectionRequest) async throws -> DuaCollectionDetailDTO {
        let req = try request(path: "DuaCollections/\(id)", method: "PUT", body: body)
        let (data, resp) = try await data(for: req)
        try throwIfNeeded(data: data, response: resp)
        do {
            return try Self.makeDecoder().decode(DuaCollectionDetailDTO.self, from: data)
        } catch {
            throw BespokeAPIError.decoding(error)
        }
    }

    func deleteDuaCollection(id: String) async throws {
        let req = try request(path: "DuaCollections/\(id)", method: "DELETE")
        let (data, resp) = try await data(for: req)
        try throwIfNeeded(data: data, response: resp)
    }

    /// `DELETE api/Auth/account`. Bearer is Supabase JWT or legacy numeric user id.
    func deleteAccount(bearerToken: String?) async throws {
        var req = try request(path: "Auth/account", method: "DELETE")
        if let bearerToken, !bearerToken.isEmpty {
            req.setValue("Bearer \(bearerToken)", forHTTPHeaderField: "Authorization")
        }
        let (data, resp) = try await data(for: req)
        try throwIfNeeded(data: data, response: resp)
    }

    func feelingLabels() async throws -> [FeelingLabel] {
        let req = try request(path: "names/feeling-labels", method: "GET")
        let (data, resp) = try await data(for: req)
        try throwIfNeeded(data: data, response: resp)
        do {
            return try Self.makeDecoder().decode([FeelingLabel].self, from: data)
        } catch {
            throw BespokeAPIError.decoding(error)
        }
    }

    /// Library view — focused name list for one feeling. Falls back to `names(feelingLabelId:)` if the route is unavailable.
    func namesByFeeling(feelingLabelId: Int) async throws -> NamesByFeelingResponse {
        let req = try request(path: "names/by-feeling/\(feelingLabelId)", method: "GET")
        let (data, resp) = try await data(for: req)
        if let http = resp as? HTTPURLResponse, http.statusCode == 404,
           decodeServerMessage(from: data) == nil || data.isEmpty {
            let details = try await names(feelingLabelId: feelingLabelId)
            guard let first = details.first else {
                throw BespokeAPIError.status(404, "Feeling label not found.")
            }
            return NamesByFeelingResponse(
                feelingLabelId: feelingLabelId,
                feelingLabel: first.feelingLabel,
                names: details.map(\.summary)
            )
        }
        try throwIfNeeded(data: data, response: resp)
        do {
            return try Self.makeDecoder().decode(NamesByFeelingResponse.self, from: data)
        } catch {
            throw BespokeAPIError.decoding(error)
        }
    }

    func names(feelingLabelId: Int) async throws -> [AllahNameDetail] {
        let req = try request(path: "names?feelingLabelId=\(feelingLabelId)", method: "GET")
        let (data, resp) = try await data(for: req)
        try throwIfNeeded(data: data, response: resp)
        do {
            return try Self.makeDecoder().decode([AllahNameDetail].self, from: data)
        } catch {
            throw BespokeAPIError.decoding(error)
        }
    }

    func name(number: Int) async throws -> AllahNameDetail {
        let req = try request(path: "names/\(number)", method: "GET")
        let (data, resp) = try await data(for: req)
        try throwIfNeeded(data: data, response: resp)
        do {
            return try Self.makeDecoder().decode(AllahNameDetail.self, from: data)
        } catch {
            throw BespokeAPIError.decoding(error)
        }
    }

    func sunnahDuaCategories() async throws -> [SunnahDuaCategorySummary] {
        let req = try request(path: "sunnah-duas/categories", method: "GET")
        let (data, resp) = try await data(for: req)
        try throwIfNeeded(data: data, response: resp)
        do {
            return try Self.makeDecoder().decode([SunnahDuaCategorySummary].self, from: data)
        } catch {
            throw BespokeAPIError.decoding(error)
        }
    }

    func recommendSunnahDuas(_ body: SunnahDuaRecommendRequest) async throws -> SunnahDuaRecommendResponse {
        let req = try request(path: "sunnah-duas/recommend", method: "POST", body: body)
        let (data, resp) = try await data(for: req)
        try throwIfNeeded(data: data, response: resp)
        do {
            return try Self.makeDecoder().decode(SunnahDuaRecommendResponse.self, from: data)
        } catch {
            throw BespokeAPIError.decoding(error)
        }
    }

    // MARK: - Dua Feed

    func duaFeed(userId: Int?, page: Int = 1, pageSize: Int = 20) async throws -> DuaFeedPageDTO {
        var query = "page=\(page)&pageSize=\(pageSize)"
        if let userId {
            query += "&userId=\(userId)"
        }
        let req = try request(path: "DuaFeed?\(query)", method: "GET")
        let (data, resp) = try await data(for: req)
        try throwIfNeeded(data: data, response: resp)
        do {
            return try Self.makeDecoder().decode(DuaFeedPageDTO.self, from: data)
        } catch {
            throw BespokeAPIError.decoding(error)
        }
    }

    func duaFeedPost(postId: String, userId: Int?) async throws -> DuaFeedPostDTO {
        var path = "DuaFeed/\(postId)"
        if let userId {
            path += "?userId=\(userId)"
        }
        let req = try request(path: path, method: "GET")
        let (data, resp) = try await data(for: req)
        try throwIfNeeded(data: data, response: resp)
        do {
            return try Self.makeDecoder().decode(DuaFeedPostDTO.self, from: data)
        } catch {
            throw BespokeAPIError.decoding(error)
        }
    }

    func activeDuaFeedPosts(userId: Int) async throws -> [DuaFeedPostDTO] {
        let req = try request(path: "DuaFeed/user/\(userId)/active", method: "GET")
        let (data, resp) = try await data(for: req)
        try throwIfNeeded(data: data, response: resp)
        return try Self.decodeDuaFeedPostList(from: data)
    }

    func duaFeedPostingQuota(userId: Int) async throws -> DuaFeedPostingQuotaDTO {
        let req = try request(path: "DuaFeed/user/\(userId)/posting-quota", method: "GET")
        let (data, resp) = try await data(for: req)
        try throwIfNeeded(data: data, response: resp)
        do {
            return try Self.makeDecoder().decode(DuaFeedPostingQuotaDTO.self, from: data)
        } catch {
            throw BespokeAPIError.decoding(error)
        }
    }

    func syncDuaFeedPostingQuota(userId: Int, activePosts: [DuaFeedPost] = []) async {
        if let quota = try? await duaFeedPostingQuota(userId: userId) {
            DuaFeedPostingQuota.applyServerUsage(userId: userId, usedToday: quota.usedToday)
            return
        }

        guard !activePosts.isEmpty else { return }
        let usedFromActive = DuaFeedPostingQuota.postsCreatedTodayCount(activePosts)
        let current = DuaFeedPostingQuota.postsUsedToday(userId: userId)
        DuaFeedPostingQuota.applyServerUsage(userId: userId, usedToday: max(current, usedFromActive))
    }

    /// Resolves every live post for the user, merging the active endpoint with own posts from the feed.
    func userActiveFeedPosts(userId: Int) async -> [DuaFeedPost] {
        var merged: [String: DuaFeedPost] = [:]

        func absorb(_ dtos: [DuaFeedPostDTO]) {
            for dto in dtos {
                guard var post = dto.asFeedPost(), post.isActive else { continue }
                post.isOwnPost = true
                merged[post.serverPostId] = post
            }
        }

        if let dtos = try? await activeDuaFeedPosts(userId: userId) {
            absorb(dtos)
        }

        if let response = try? await duaFeed(userId: userId, page: 1, pageSize: 50) {
            absorb(response.items.filter(\.isOwnPost))
        }

        let posts = merged.values.sorted { $0.createdAt > $1.createdAt }
        await syncDuaFeedPostingQuota(userId: userId, activePosts: posts)
        return posts
    }

    private static func decodeDuaFeedPostList(from data: Data) throws -> [DuaFeedPostDTO] {
        let decoder = makeDecoder()
        if let posts = try? decoder.decode([DuaFeedPostDTO].self, from: data) {
            return posts
        }
        if let page = try? decoder.decode(DuaFeedPageDTO.self, from: data) {
            return page.items
        }
        struct PostsWrapper: Decodable { let posts: [DuaFeedPostDTO] }
        if let wrapped = try? decoder.decode(PostsWrapper.self, from: data) {
            return wrapped.posts
        }
        struct ItemsWrapper: Decodable { let items: [DuaFeedPostDTO] }
        if let wrapped = try? decoder.decode(ItemsWrapper.self, from: data) {
            return wrapped.items
        }
        return [try decoder.decode(DuaFeedPostDTO.self, from: data)]
    }

    func activeDuaFeedPost(userId: Int) async throws -> DuaFeedPostDTO {
        let req = try request(path: "DuaFeed/user/\(userId)/active", method: "GET")
        let (data, resp) = try await data(for: req)
        try throwIfNeeded(data: data, response: resp)
        do {
            return try Self.makeDecoder().decode(DuaFeedPostDTO.self, from: data)
        } catch {
            throw BespokeAPIError.decoding(error)
        }
    }

    func createDuaFeedPost(userId: Int, savedDuaId: String, isAnonymous: Bool) async throws -> DuaFeedPostDTO {
        let body = CreateDuaFeedPostRequest(userId: userId, savedDuaId: savedDuaId, isAnonymous: isAnonymous)
        let req = try request(path: "DuaFeed", method: "POST", body: body)
        let (data, resp) = try await data(for: req)
        try throwIfNeeded(data: data, response: resp)
        do {
            return try Self.makeDecoder().decode(DuaFeedPostDTO.self, from: data)
        } catch {
            throw BespokeAPIError.decoding(error)
        }
    }

    func deleteDuaFeedPost(postId: String, userId: Int) async throws {
        let req = try request(path: "DuaFeed/\(postId)?userId=\(userId)", method: "DELETE")
        let (data, resp) = try await data(for: req)
        try throwIfNeeded(data: data, response: resp)
    }

    func toggleMakeDua(postId: String, userId: Int) async throws -> MakeDuaResponse {
        let body = MakeDuaRequest(userId: userId)
        let req = try request(path: "DuaFeed/\(postId)/make-dua", method: "POST", body: body)
        let (data, resp) = try await data(for: req)
        try throwIfNeeded(data: data, response: resp)
        do {
            return try Self.makeDecoder().decode(MakeDuaResponse.self, from: data)
        } catch {
            throw BespokeAPIError.decoding(error)
        }
    }

    /// `PATCH api/Plan/subscribe`. Sends Apple linkage metadata for strict account ownership checks.
    func subscribePlan(
        authorizedUserId userId: Int,
        bearerToken: String?,
        originalTransactionId: String?,
        productId: String,
        confirmTransfer: Bool = false
    ) async throws -> AuthUser {
        let body = SubscribePlanRequest(
            originalTransactionId: originalTransactionId,
            productId: productId,
            confirmTransfer: confirmTransfer
        )
        var req = try request(path: "Plan/subscribe", method: "PATCH", body: body)
        let token = bearerToken ?? String(userId)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, resp) = try await data(for: req)
        try throwIfNeeded(data: data, response: resp)
        do {
            return try Self.makeDecoder().decode(AuthUser.self, from: data)
        } catch {
            throw BespokeAPIError.decoding(error)
        }
    }

    private func throwIfNeeded(data: Data, response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { return }
        guard (200 ..< 300).contains(http.statusCode) else {
            let msg = decodeServerMessage(from: data)
            throw BespokeAPIError.status(http.statusCode, msg)
        }
    }
}
