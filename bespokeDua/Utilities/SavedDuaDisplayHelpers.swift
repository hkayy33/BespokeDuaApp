import Foundation

/// The API may only persist plain `dua` text; we keep reflections locally by server `duaId` so the Saved tab can still show them.
enum SavedDuaReflectionsCache {
    private static func storageKey(userId: Int, duaId: String) -> String {
        "bespoke.savedDua.reflections.\(userId).\(duaId)"
    }

    static func store(userId: Int, duaId: String, explanations: [ExplanationModel]) {
        if explanations.isEmpty {
            remove(userId: userId, duaId: duaId)
            return
        }
        struct Row: Codable {
            let name: String
            let explanation: String
        }
        let rows = explanations.map { Row(name: $0.name, explanation: $0.explanation) }
        guard let data = try? JSONEncoder().encode(rows) else { return }
        UserDefaults.standard.set(data, forKey: storageKey(userId: userId, duaId: duaId))
    }

    static func explanations(userId: Int, duaId: String) -> [ExplanationModel]? {
        guard let data = UserDefaults.standard.data(forKey: storageKey(userId: userId, duaId: duaId)) else { return nil }
        struct Row: Codable {
            let name: String
            let explanation: String
        }
        guard let rows = try? JSONDecoder().decode([Row].self, from: data) else { return nil }
        return rows.map { ExplanationModel(name: $0.name, explanation: $0.explanation) }
    }

    static func remove(userId: Int, duaId: String) {
        UserDefaults.standard.removeObject(forKey: storageKey(userId: userId, duaId: duaId))
    }
}

enum SavedDuaKind: String, CaseIterable, Identifiable, Sendable {
    case bespoke
    case sunnah

    var id: String { rawValue }

    var title: String {
        switch self {
        case .bespoke: "Bespoke duas"
        case .sunnah: "Sunnah duas"
        }
    }

    var iconName: String {
        switch self {
        case .bespoke: "wand.and.stars"
        case .sunnah: "book.closed.fill"
        }
    }
}

enum SavedDuaDisplay {
    /// Matches API semantics: `updatedAt == null` means never edited.
    static func isEdited(_ row: SavedDuaDTO) -> Bool {
        row.updatedAt != nil
    }

    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    static func kind(from row: SavedDuaDTO) -> SavedDuaKind {
        if SunnahDuaDisplay.savedPayload(from: row) != nil {
            return .sunnah
        }

        let raw = row.dua.trimmingCharacters(in: .whitespacesAndNewlines)
        guard raw.hasPrefix("{"), let data = raw.data(using: .utf8) else {
            return .bespoke
        }

        struct SavedDuaMetaJSON: Decodable {
            let source: String?
            let kind: String?
            let type: String?
        }

        guard let meta = try? JSONDecoder().decode(SavedDuaMetaJSON.self, from: data) else {
            return .bespoke
        }

        let token = (meta.source ?? meta.kind ?? meta.type ?? "").lowercased()
        return token.contains("sunnah") ? .sunnah : .bespoke
    }

    static func kind(for dua: DuaReceiver) -> SavedDuaKind {
        guard let storageJSON = dua.storageJSON?
            .trimmingCharacters(in: .whitespacesAndNewlines),
            storageJSON.hasPrefix("{"),
            let data = storageJSON.data(using: .utf8) else {
            return .bespoke
        }

        if (try? JSONDecoder().decode(SunnahDuaSavedPayload.self, from: data)) != nil {
            return .sunnah
        }

        if storageJSON.lowercased().contains("sunnah") {
            return .sunnah
        }

        return .bespoke
    }

    static func existingRow(matching dua: DuaReceiver, in rows: [SavedDuaDTO]) -> SavedDuaDTO? {
        if kind(for: dua) == .sunnah,
           let storageJSON = dua.storageJSON?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           storageJSON.hasPrefix("{"),
           let data = storageJSON.data(using: .utf8),
           let payload = try? JSONDecoder().decode(SunnahDuaSavedPayload.self, from: data) {
            let key = SunnahDuaDisplay.savedItemKey(categoryId: payload.category, duaId: payload.id)
            return rows.first { row in
                guard kind(from: row) == .sunnah,
                      let savedPayload = SunnahDuaDisplay.savedPayload(from: row) else {
                    return false
                }
                return SunnahDuaDisplay.savedItemKey(categoryId: savedPayload.category, duaId: savedPayload.id) == key
            }
        }

        let normalizedText = dua.duaText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedText.isEmpty else { return nil }

        return rows.first { row in
            guard kind(from: row) == .bespoke else { return false }
            return duaReceiver(from: row, userId: nil).duaText
                .trimmingCharacters(in: .whitespacesAndNewlines) == normalizedText
        }
    }

    /// `SavedDuas.dua` / `SavedSunnahDuas.sunnahDua` may be plain text, JSON we encoded, or JSON from the server.
    static func duaReceiver(from row: SavedDuaDTO, userId: Int?) -> DuaReceiver {
        if let payload = SunnahDuaDisplay.savedPayload(from: row) {
            let text = SunnahDuaDisplay.cardBody(from: payload)
            let explanations = [
                ExplanationModel(name: payload.title, explanation: payload.translation),
                ExplanationModel(name: "Source", explanation: payload.source),
            ]
            if let uid = userId,
               let cached = SavedDuaReflectionsCache.explanations(userId: uid, duaId: row.duaId),
               !cached.isEmpty {
                return DuaReceiver(duaText: text, explanations: cached, storageJSON: row.dua)
            }
            return DuaReceiver(duaText: text, explanations: explanations, storageJSON: row.dua)
        }

        let raw = row.dua.trimmingCharacters(in: .whitespacesAndNewlines)
        var text = raw
        var explanations: [ExplanationModel] = []

        if raw.hasPrefix("{"), let data = raw.data(using: .utf8) {
            struct FlexibleSavedDuaJSON: Decodable {
                let dua: String?
                let duaText: String?
                let explanations: [GeneratedExplanationDTO]?
            }
            if let flex = try? JSONDecoder().decode(FlexibleSavedDuaJSON.self, from: data) {
                text = flex.dua ?? flex.duaText ?? raw
                explanations = (flex.explanations ?? []).map {
                    ExplanationModel(name: $0.name, explanation: $0.explanation)
                }
            }
        }

        if explanations.isEmpty,
           let uid = userId,
           let cached = SavedDuaReflectionsCache.explanations(userId: uid, duaId: row.duaId),
           !cached.isEmpty {
            explanations = cached
        }

        return DuaReceiver(duaText: text, explanations: explanations)
    }

    static func previewText(from row: SavedDuaDTO, userId: Int?, maxLength: Int = 120) -> String {
        let text = duaReceiver(from: row, userId: userId).duaText
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if text.count <= maxLength { return text }
        return String(text.prefix(maxLength)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }

    /// JSON payload for `SavedDuas` when explanations should travel with the text.
    static func encodeForStorage(duaText: String, explanations: [ExplanationModel]) -> String {
        guard !explanations.isEmpty else { return duaText }
        struct Payload: Encodable {
            let dua: String
            let duaText: String
            let explanations: [Row]
            struct Row: Encodable {
                let name: String
                let explanation: String
            }
        }
        let rows = explanations.map { Payload.Row(name: $0.name, explanation: $0.explanation) }
        let payload = Payload(dua: duaText, duaText: duaText, explanations: rows)
        guard let data = try? JSONEncoder().encode(payload),
              let str = String(data: data, encoding: .utf8) else {
            return duaText
        }
        return str
    }
}
