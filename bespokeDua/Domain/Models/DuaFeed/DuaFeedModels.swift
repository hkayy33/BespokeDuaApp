import Foundation

enum DuaFeedRoute: Hashable {
    case postDua
    case pickDuaToPost
}

enum DuaFeedFilter: String, CaseIterable, Identifiable {
    case recent
    case mostDuas
    case myPosts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recent: "Recent"
        case .mostDuas: "Most dua made"
        case .myPosts: "Your duas"
        }
    }

    var symbolName: String {
        switch self {
        case .recent: "clock"
        case .mostDuas: "hands.sparkles"
        case .myPosts: "person.crop.circle"
        }
    }
}

enum DuaFeedCategory: String, CaseIterable, Identifiable {
    case health
    case family
    case rizq
    case exams
    case guidance
    case other

    var id: String { rawValue }

    var title: String {
        switch self {
        case .health: "Health"
        case .family: "Family"
        case .rizq: "Rizq"
        case .exams: "Exams"
        case .guidance: "Guidance"
        case .other: "Other"
        }
    }

    var symbolName: String {
        switch self {
        case .health: "heart.text.square"
        case .family: "figure.2"
        case .rizq: "leaf"
        case .exams: "book"
        case .guidance: "sparkles"
        case .other: "ellipsis.circle"
        }
    }

    var tagSymbolName: String {
        switch self {
        case .health: "heart"
        case .family: "figure.2"
        case .rizq: "leaf"
        case .exams: "book"
        case .guidance: "sparkles"
        case .other: "ellipsis.circle"
        }
    }
}

enum DuaFeedContentKind: String, Hashable, Sendable {
    case bespoke
    case sunnah
}

// MARK: - API DTOs

struct DuaFeedPostDTO: Decodable, Sendable, Equatable {
    let postId: String
    let authorUsername: String?
    let isAnonymous: Bool
    let content: String
    let createdAt: Date
    let expiresAt: Date
    let duaCount: Int
    let hasUserMadeDua: Bool
    let isOwnPost: Bool

    private enum CodingKeys: String, CodingKey {
        case postId
        case authorUsername
        case isAnonymous
        case content
        case createdAt
        case expiresAt
        case duaCount
        case hasUserMadeDua
        case isOwnPost
    }

    init(
        postId: String,
        authorUsername: String?,
        isAnonymous: Bool,
        content: String,
        createdAt: Date,
        expiresAt: Date,
        duaCount: Int,
        hasUserMadeDua: Bool,
        isOwnPost: Bool = false
    ) {
        self.postId = postId
        self.authorUsername = authorUsername
        self.isAnonymous = isAnonymous
        self.content = content
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.duaCount = duaCount
        self.hasUserMadeDua = hasUserMadeDua
        self.isOwnPost = isOwnPost
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        postId = try container.decode(String.self, forKey: .postId)
        authorUsername = try container.decodeIfPresent(String.self, forKey: .authorUsername)
        isAnonymous = try container.decode(Bool.self, forKey: .isAnonymous)
        content = try container.decode(String.self, forKey: .content)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        expiresAt = try container.decode(Date.self, forKey: .expiresAt)
        duaCount = try container.decode(Int.self, forKey: .duaCount)
        hasUserMadeDua = try container.decode(Bool.self, forKey: .hasUserMadeDua)
        isOwnPost = try container.decodeIfPresent(Bool.self, forKey: .isOwnPost) ?? false
    }
}

struct DuaFeedPageDTO: Decodable, Sendable {
    let items: [DuaFeedPostDTO]
    let page: Int
    let pageSize: Int
    let totalCount: Int
    let hasMore: Bool
}

struct CreateDuaFeedPostRequest: Encodable, Sendable {
    let userId: Int
    let savedDuaId: String
    let isAnonymous: Bool
}

struct MakeDuaRequest: Encodable, Sendable {
    let userId: Int
}

struct MakeDuaResponse: Decodable, Sendable {
    let duaCount: Int
    let hasUserMadeDua: Bool
}

struct DuaFeedPostingQuotaDTO: Decodable, Sendable {
    let usedToday: Int
    let dailyLimit: Int
    let remainingToday: Int
}

// MARK: - Saved-dua content snapshots (JSON in `content`)

struct DuaFeedBespokeContent: Decodable, Sendable {
    let duaText: String
    let explanations: [GeneratedExplanationDTO]?
}

struct DuaFeedSunnahContent: Decodable, Sendable {
    let category: String
    let title: String
    let arabic: String
    let translation: String
    let source: String
}

// MARK: - Content → display mapping

enum DuaFeedContentMapper {
    struct ParsedContent: Sendable {
        let kind: DuaFeedContentKind
        let body: String
        let explanations: [ExplanationModel]
        let sunnahTitle: String?
        let sunnahCategory: String?
    }

    static func parse(_ rawContent: String) -> ParsedContent {
        let trimmed = rawContent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{"),
              let data = trimmed.data(using: .utf8) else {
            return ParsedContent(
                kind: .bespoke,
                body: trimmed,
                explanations: [],
                sunnahTitle: nil,
                sunnahCategory: nil
            )
        }

        if let sunnah = try? JSONDecoder().decode(DuaFeedSunnahContent.self, from: data) {
            let body = SunnahDuaDisplay.cardBody(
                arabic: sunnah.arabic,
                transliteration: "",
                translation: sunnah.translation
            )
            let explanations = [
                ExplanationModel(name: sunnah.title, explanation: sunnah.translation),
                ExplanationModel(name: "Source", explanation: sunnah.source),
            ]
            return ParsedContent(
                kind: .sunnah,
                body: body,
                explanations: explanations,
                sunnahTitle: sunnah.title,
                sunnahCategory: sunnah.category
            )
        }

        if let bespoke = try? JSONDecoder().decode(DuaFeedBespokeContent.self, from: data) {
            let explanations = (bespoke.explanations ?? []).map {
                ExplanationModel(name: $0.name, explanation: $0.explanation)
            }
            return ParsedContent(
                kind: .bespoke,
                body: bespoke.duaText,
                explanations: explanations,
                sunnahTitle: nil,
                sunnahCategory: nil
            )
        }

        struct FlexibleSavedDuaJSON: Decodable {
            let dua: String?
            let duaText: String?
            let explanations: [GeneratedExplanationDTO]?
        }

        if let flex = try? JSONDecoder().decode(FlexibleSavedDuaJSON.self, from: data) {
            let text = flex.dua ?? flex.duaText ?? trimmed
            let explanations = (flex.explanations ?? []).map {
                ExplanationModel(name: $0.name, explanation: $0.explanation)
            }
            return ParsedContent(
                kind: .bespoke,
                body: text,
                explanations: explanations,
                sunnahTitle: nil,
                sunnahCategory: nil
            )
        }

        return ParsedContent(
            kind: .bespoke,
            body: trimmed,
            explanations: [],
            sunnahTitle: nil,
            sunnahCategory: nil
        )
    }
}

extension DuaFeedPostDTO {
    private static func feedLocalID(for postId: String) -> UUID {
        if let uuid = UUID(uuidString: postId) { return uuid }
        var bytes = [UInt8](repeating: 0, count: 16)
        for (index, byte) in postId.utf8.enumerated() {
            bytes[index % 16] = bytes[index % 16] &+ byte
        }
        bytes[6] = (bytes[6] & 0x0F) | 0x40
        bytes[8] = (bytes[8] & 0x3F) | 0x80
        return UUID(uuid: (
            bytes[0], bytes[1], bytes[2], bytes[3],
            bytes[4], bytes[5], bytes[6], bytes[7],
            bytes[8], bytes[9], bytes[10], bytes[11],
            bytes[12], bytes[13], bytes[14], bytes[15]
        ))
    }

    func asFeedPost() -> DuaFeedPost? {
        let parsed = DuaFeedContentMapper.parse(content)
        let id = Self.feedLocalID(for: postId)
        return DuaFeedPost(
            id: id,
            serverPostId: postId,
            body: parsed.body,
            category: nil,
            createdAt: createdAt,
            expiresAt: expiresAt,
            duaCount: duaCount,
            hasMadeDua: hasUserMadeDua,
            isAnswered: false,
            isSaved: false,
            authorUsername: authorUsername,
            isAnonymous: isAnonymous,
            contentKind: parsed.kind,
            explanations: parsed.explanations,
            sunnahTitle: parsed.sunnahTitle,
            sunnahCategory: parsed.sunnahCategory,
            isOwnPost: isOwnPost
        )
    }
}

// MARK: - App model

struct DuaFeedPost: Identifiable, Hashable {
    let id: UUID
    let serverPostId: String
    var body: String
    var category: DuaFeedCategory?
    var createdAt: Date
    var expiresAt: Date
    var duaCount: Int
    var hasMadeDua: Bool
    var isAnswered: Bool
    var isSaved: Bool
    var authorUsername: String?
    var isAnonymous: Bool
    var contentKind: DuaFeedContentKind
    var explanations: [ExplanationModel]
    var sunnahTitle: String?
    var sunnahCategory: String?
    var isOwnPost: Bool

    init(
        id: UUID,
        serverPostId: String? = nil,
        body: String,
        category: DuaFeedCategory? = nil,
        createdAt: Date,
        expiresAt: Date = Date.now.addingTimeInterval(86_400),
        duaCount: Int,
        hasMadeDua: Bool,
        isAnswered: Bool,
        isSaved: Bool,
        authorUsername: String? = nil,
        isAnonymous: Bool = true,
        contentKind: DuaFeedContentKind = .bespoke,
        explanations: [ExplanationModel] = [],
        sunnahTitle: String? = nil,
        sunnahCategory: String? = nil,
        isOwnPost: Bool = false
    ) {
        self.id = id
        self.serverPostId = serverPostId ?? id.uuidString.lowercased()
        self.body = body
        self.category = category
        self.createdAt = createdAt
        self.expiresAt = expiresAt
        self.duaCount = duaCount
        self.hasMadeDua = hasMadeDua
        self.isAnswered = isAnswered
        self.isSaved = isSaved
        self.authorUsername = authorUsername
        self.isAnonymous = isAnonymous
        self.contentKind = contentKind
        self.explanations = explanations
        self.sunnahTitle = sunnahTitle
        self.sunnahCategory = sunnahCategory
        self.isOwnPost = isOwnPost
    }

    var displayAuthorName: String {
        if isAnonymous { return "Anonymous" }
        let name = authorUsername?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "Anonymous" : name
    }

    var isActive: Bool {
        expiresAt > Date.now
    }

    var isFromToday: Bool {
        isActive && Date.now.timeIntervalSince(createdAt) < 86_400
    }

    private static let feedPreviewLength = 100

    var feedPreview: String {
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > Self.feedPreviewLength else { return trimmed }
        let prefix = String(trimmed.prefix(Self.feedPreviewLength))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(prefix)…"
    }

    var needsFeedPreviewExpansion: Bool {
        body.trimmingCharacters(in: .whitespacesAndNewlines).count > Self.feedPreviewLength
    }

    var hoursAgoText: String {
        let interval = Date.now.timeIntervalSince(createdAt)
        if interval < 60 {
            return "Just now"
        }
        if interval < 3600 {
            let minutes = max(1, Int(interval / 60))
            return minutes == 1 ? "1m ago" : "\(minutes)m ago"
        }
        let hours = Int(interval / 3600)
        if hours < 24 {
            return hours == 1 ? "1h ago" : "\(hours)h ago"
        }
        let days = Int(interval / 86_400)
        return days == 1 ? "1d ago" : "\(days)d ago"
    }

    var timeRemainingText: String? {
        guard isActive else { return nil }
        let remaining = expiresAt.timeIntervalSinceNow
        guard remaining > 0 else { return nil }
        if remaining < 3600 {
            let minutes = max(1, Int(ceil(remaining / 60)))
            return minutes == 1 ? "1m left" : "\(minutes)m left"
        }
        let hours = max(1, Int(ceil(remaining / 3600)))
        return hours == 1 ? "1h left" : "\(hours)h left"
    }

    func asDuaReceiver() -> DuaReceiver {
        DuaReceiver(duaText: body, explanations: explanations)
    }
}

enum DuaFeedSampleData {
    static let posts: [DuaFeedPost] = [
        DuaFeedPost(
            id: UUID(uuidString: "983E4F29-4FBA-472B-9254-CEBDA0DF757E")!,
            body: "Ya Allah, grant me clarity in my studies and help me succeed in my exams. Ameen.",
            category: .exams,
            createdAt: Date.now.addingTimeInterval(-7_200),
            duaCount: 36,
            hasMadeDua: false,
            isAnswered: false,
            isSaved: false
        ),
        DuaFeedPost(
            id: UUID(uuidString: "9189B241-4E58-46B0-BC5B-C581014ECC91")!,
            body: "Ya Qawiyy (القوي), strengthen my body and grant complete shifa. Ameen.",
            category: .health,
            createdAt: Date.now.addingTimeInterval(-18_000),
            duaCount: 58,
            hasMadeDua: false,
            isAnswered: false,
            isSaved: false
        ),
        DuaFeedPost(
            id: UUID(uuidString: "A809663F-1011-4260-AC06-3FE573AB3E11")!,
            body: "O Allah, open doors of rizq for me and grant barakah in my earnings. Ameen.",
            category: .rizq,
            createdAt: Date.now.addingTimeInterval(-86_400),
            duaCount: 74,
            hasMadeDua: false,
            isAnswered: false,
            isSaved: false
        )
    ]
}
