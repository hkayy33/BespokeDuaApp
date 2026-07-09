import SwiftUI

enum SavedLibraryFilter: String, CaseIterable, Identifiable {
    case recent
    case edited

    var id: String { rawValue }

    var title: String {
        switch self {
        case .recent: "Recent"
        case .edited: "Edited"
        }
    }

    var symbolName: String {
        switch self {
        case .recent: "clock"
        case .edited: "pencil"
        }
    }
}

struct SavedLibraryFilterChips: View {
    @Binding var selection: SavedLibraryFilter
    var showsEdited: Bool = true

    private var availableFilters: [SavedLibraryFilter] {
        showsEdited ? SavedLibraryFilter.allCases : [.recent]
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(availableFilters) { filter in
                filterChip(filter)
            }
            Spacer(minLength: 0)
        }
    }

    private func filterChip(_ filter: SavedLibraryFilter) -> some View {
        let isSelected = selection == filter

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selection = filter
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: filter.symbolName)
                    .font(.system(size: 12, weight: .semibold))

                Text(filter.title)
                    .font(BespokeFont.inter(13, weight: .medium))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? .white : BespokeColor.muted)
            .padding(.horizontal, 14)
            .padding(.vertical, 9)
            .background(isSelected ? BespokeColor.forest : Color.white)
            .clipShape(Capsule())
            .overlay {
                if !isSelected {
                    Capsule()
                        .stroke(BespokeColor.cardBorder, lineWidth: 1)
                }
            }
        }
        .buttonStyle(BespokePlainButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct SavedDuaSelectionTipCard: View {
    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.white)
                    .frame(width: 34, height: 34)
                    .shadow(color: .black.opacity(0.04), radius: 4, x: 0, y: 2)

                Image(systemName: "hand.tap.fill")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(BespokeColor.homeGold)
            }
            .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text("Tip: Press and hold any dua card to select multiple.")
                    .font(BespokeFont.inter(11.5, weight: .medium))
                    .foregroundStyle(BespokeColor.forest)
                    .lineLimit(1)
                    .minimumScaleFactor(0.84)

                Text("You can then move or delete selected duas.")
                    .font(BespokeFont.inter(11, weight: .regular))
                    .foregroundStyle(BespokeColor.muted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 11)
        .background {
            ZStack(alignment: .bottomTrailing) {
                BespokeColor.cream

                Image("HomeCardBackdropBespoke")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 108, maxHeight: 64)
                    .opacity(0.34)
                    .offset(x: 8, y: 6)
                    .allowsHitTesting(false)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(BespokeColor.homeGold.opacity(0.32), lineWidth: 1)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Tip: Press and hold any dua card to select multiple. You can then move or delete selected duas.")
    }
}

enum SavedLibraryFiltering {
    private static let collectionEditedThreshold: TimeInterval = 1

    static func filteredSavedDuas(
        _ duas: [SavedDuaDTO],
        filter: SavedLibraryFilter,
        userId: Int?
    ) -> [SavedDuaDTO] {
        switch filter {
        case .recent:
            return duas.sorted { $0.createdAt > $1.createdAt }
        case .edited:
            return duas
                .filter { SavedDuaDisplay.isEdited($0) }
                .sorted { ($0.updatedAt ?? $0.createdAt) > ($1.updatedAt ?? $1.createdAt) }
        }
    }

    static func filteredCollections(
        _ collections: [DuaCollectionSummaryDTO],
        filter: SavedLibraryFilter
    ) -> [DuaCollectionSummaryDTO] {
        switch filter {
        case .recent:
            return collections.sorted { $0.updatedAt > $1.updatedAt }
        case .edited:
            return collections
                .filter { $0.updatedAt.timeIntervalSince($0.createdAt) > collectionEditedThreshold }
                .sorted { $0.updatedAt > $1.updatedAt }
        }
    }
}
