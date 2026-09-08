import SwiftUI

enum SavedDuaCollectionPickerLayout {
    static let rowSpacing: CGFloat = 10
    static let rowHeight: CGFloat = 64
    static let maxVisibleRows = 3

    static var collectionsScrollHeight: CGFloat {
        let rows = CGFloat(maxVisibleRows)
        return rows * rowHeight + max(0, rows - 1) * rowSpacing
    }
}

struct SavedDuaMoveModalView: View {
    @Environment(AppSession.self) private var session

    @Binding var isPresented: Bool
    let duaIds: Set<String>
    let duaKind: SavedDuaKind
    let canUseCollections: Bool
    var onAddCollections: (() -> Void)?
    var onSaved: (() -> Void)?

    @State private var selectedCollectionIds: Set<String> = []
    @State private var loadingMembership = true
    @State private var saveInFlight = false
    @State private var saveError: String?

    private var userId: Int? { session.currentUser?.userId }

    private var availableCollections: [DuaCollectionSummaryDTO] {
        session.duaCollections.sorted { lhs, rhs in
            let lhsMatchesKind = DuaCollectionDisplay.kind(for: lhs, userId: userId) == duaKind
            let rhsMatchesKind = DuaCollectionDisplay.kind(for: rhs, userId: userId) == duaKind
            if lhsMatchesKind != rhsMatchesKind { return lhsMatchesKind }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    private var modalBinding: Binding<Bool> {
        Binding(
            get: { isPresented },
            set: { newValue in
                guard !saveInFlight else { return }
                isPresented = newValue
            }
        )
    }

    var body: some View {
        BespokeCardModalView(isPresented: modalBinding, title: "Where to save?") {
            Text(helperText)
                .font(BespokeFont.inter(15, weight: .regular))
                .foregroundStyle(BespokeColor.muted)
                .fixedSize(horizontal: false, vertical: true)

            if let saveError, !saveError.isEmpty {
                Text(saveError)
                    .font(BespokeFont.inter(14, weight: .regular))
                    .foregroundStyle(BespokeColor.error)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 10) {
                SavedDuaMoveRow(
                    symbolName: "bookmark.fill",
                    title: "General",
                    subtitle: "Always saved in your library",
                    isSelected: true,
                    isLocked: true
                )

                if canUseCollections {
                    collectionsSection
                } else if let onAddCollections {
                    Button(action: onAddCollections) {
                        HStack(spacing: 10) {
                            Image(systemName: "folder.badge.plus")
                                .font(.system(size: 16, weight: .semibold))
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Add collections")
                                    .font(BespokeFont.inter(16, weight: .semibold))
                                Text(BespokePlusOfferCopy.freeMonthHeadline)
                                    .font(BespokeFont.inter(13, weight: .medium))
                                    .foregroundStyle(BespokeColor.muted)
                            }
                        }
                        .foregroundStyle(BespokeColor.forest)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(BespokeColor.cardBorder, lineWidth: 1)
                        )
                        .bespokeButtonHitArea(cornerRadius: 14)
                    }
                    .buttonStyle(BespokePlainButtonStyle())
                }
            }

            Button {
                Task { await saveSelection() }
            } label: {
                Group {
                    if saveInFlight {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Save")
                            .font(BespokeFont.inter(17, weight: .semibold))
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background {
                    if !saveInFlight {
                        LinearGradient.bespokeGold
                    } else {
                        BespokeColor.muted.opacity(0.35)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(BespokePlainButtonStyle())
            .disabled(saveInFlight || loadingMembership)
            .padding(.top, 6)
        }
        .task(id: duaIds) {
            await loadMembership()
        }
        .task(id: isPresented) {
            guard isPresented, canUseCollections else { return }
            await session.refreshDuaCollections()
        }
    }

    private var helperText: String {
        if canUseCollections {
            "Choose which collections these duas belong to. General always keeps them in your library."
        } else {
            "These duas stay in your main library."
        }
    }

    @ViewBuilder
    private var collectionsSection: some View {
        if loadingMembership && session.duaCollections.isEmpty {
            HStack(spacing: 10) {
                ProgressView()
                    .tint(BespokeColor.forest)
                Text("Loading collections…")
                    .font(BespokeFont.inter(14, weight: .regular))
                    .foregroundStyle(BespokeColor.muted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 8)
        } else if !availableCollections.isEmpty {
            Text("Collections")
                .font(BespokeFont.inter(12, weight: .semibold))
                .foregroundStyle(BespokeColor.muted)
                .textCase(.uppercase)
                .tracking(0.9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)

            ScrollView {
                VStack(spacing: SavedDuaCollectionPickerLayout.rowSpacing) {
                    ForEach(availableCollections) { collection in
                        SavedDuaMoveRow(
                            symbolName: CollectionIconCache.symbol(
                                userId: userId,
                                collectionId: collection.collectionId
                            ),
                            title: collection.name,
                            subtitle: collectionCountSubtitle(collection.duaCount),
                            isSelected: selectedCollectionIds.contains(collection.collectionId)
                        ) {
                            toggleCollection(collection.collectionId)
                        }
                    }
                }
            }
            .frame(maxHeight: SavedDuaCollectionPickerLayout.collectionsScrollHeight)
        }
    }

    private func collectionCountSubtitle(_ count: Int) -> String {
        switch count {
        case 0: return "No duas yet"
        case 1: return "1 dua"
        default: return "\(count) duas"
        }
    }

    private func toggleCollection(_ id: String) {
        if selectedCollectionIds.contains(id) {
            selectedCollectionIds.remove(id)
        } else {
            selectedCollectionIds.insert(id)
        }
    }

    @MainActor
    private func loadMembership() async {
        loadingMembership = true
        defer { loadingMembership = false }

        selectedCollectionIds = await SavedDuaCollectionMembership.collectionIdsContainingAll(
            duaIds: duaIds,
            session: session
        )
    }

    @MainActor
    private func saveSelection() async {
        guard !saveInFlight else { return }
        saveInFlight = true
        saveError = nil
        defer { saveInFlight = false }

        do {
            if canUseCollections {
                try await SavedDuaCollectionMembership.apply(
                    duaIds: duaIds,
                    toCollectionIds: selectedCollectionIds,
                    session: session
                )
            }
            BespokeHaptics.success()
            onSaved?()
            isPresented = false
        } catch {
            saveError = (error as? LocalizedError)?.errorDescription ?? "Couldn't update collections. Try again."
        }
    }
}

private struct SavedDuaMoveRow: View {
    let symbolName: String
    let title: String
    let subtitle: String
    var isSelected: Bool
    var isLocked: Bool = false
    var action: (() -> Void)?

    var body: some View {
        Group {
            if isLocked {
                rowContent
            } else {
                Button {
                    action?()
                } label: {
                    rowContent
                }
                .buttonStyle(BespokePlainButtonStyle())
            }
        }
    }

    private var rowContent: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(BespokeColor.forest.opacity(isSelected ? 0.16 : 0.10))
                    .frame(width: 40, height: 40)
                Image(systemName: symbolName)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(BespokeColor.forest)
            }
            .fixedSize()

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(BespokeFont.inter(16, weight: .semibold))
                    .foregroundStyle(BespokeColor.bodyText)
                Text(subtitle)
                    .font(BespokeFont.inter(13, weight: .regular))
                    .foregroundStyle(BespokeColor.muted)
            }

            Spacer(minLength: 0)

            Image(systemName: isLocked ? "lock.fill" : (isSelected ? "checkmark.circle.fill" : "circle"))
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(isLocked ? BespokeColor.muted : (isSelected ? BespokeColor.forest : BespokeColor.cardBorder))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isSelected ? BespokeColor.forest.opacity(0.35) : BespokeColor.cardBorder, lineWidth: 1)
        )
    }
}
