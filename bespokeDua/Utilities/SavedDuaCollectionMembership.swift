import Foundation

enum SavedDuaCollectionMembership {
    @MainActor
    static func collectionIdsContainingAll(duaIds: Set<String>, session: AppSession) async -> Set<String> {
        guard !duaIds.isEmpty else { return [] }

        var matching = Set<String>()
        for summary in session.duaCollections {
            guard let detail = try? await session.api().duaCollection(id: summary.collectionId) else { continue }
            if duaIds.isSubset(of: Set(detail.savedDuaIds)) {
                matching.insert(summary.collectionId)
            }
        }
        return matching
    }

    @MainActor
    static func apply(
        duaIds: Set<String>,
        toCollectionIds: Set<String>,
        session: AppSession
    ) async throws {
        guard !duaIds.isEmpty else { return }

        for summary in session.duaCollections {
            let detail = try await session.api().duaCollection(id: summary.collectionId)
            var ids = detail.savedDuaIds
            let shouldContain = toCollectionIds.contains(summary.collectionId)
            var changed = false

            for duaId in duaIds {
                if shouldContain {
                    if !ids.contains(duaId) {
                        ids.append(duaId)
                        changed = true
                    }
                } else if ids.contains(duaId) {
                    ids.removeAll { $0 == duaId }
                    changed = true
                }
            }

            guard changed else { continue }

            let updated = try await session.api().updateDuaCollection(
                id: summary.collectionId,
                body: UpdateDuaCollectionRequest(
                    name: detail.name,
                    description: detail.description,
                    duaIds: ids
                )
            )
            session.upsertDuaCollection(from: updated)
        }
    }
}
