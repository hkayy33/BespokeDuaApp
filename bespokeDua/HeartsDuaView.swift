import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

enum HeartsDuaDestination: Hashable {
    case allSavedDuas
    case makeCollection
    case collection(String)
}

struct HeartsDuaHubView: View {
    @Binding var navigationPath: NavigationPath

    @Environment(AppSession.self) private var session
    @Environment(SubscriptionManager.self) private var subscriptionManager
    @Environment(\.presentUpgradeModal) private var presentUpgradeModal
    @Environment(\.mainTabBarClearance) private var mainTabBarClearance

    init(navigationPath: Binding<NavigationPath> = .constant(NavigationPath())) {
        _navigationPath = navigationPath
    }

    var body: some View {
        BespokeSubpageLayout(
            title: "Saved",
            subtitle: "Your personal library of duas and collections.",
            showsBackButton: false,
            showsMenuButton: true,
            centersTitle: true,
            usesHomeBackground: true
        ) {
            Group {
                if !session.isLoggedIn {
                    signedOutContent
                } else {
                    signedInContent
                }
            }
        }
        .navigationBarBackButtonHidden(true)
        .navigationDestination(for: HeartsDuaDestination.self) { destination in
            switch destination {
            case .allSavedDuas:
                AllSavedDuasListView()
            case .makeCollection:
                MakeDuaCollectionView()
            case let .collection(id):
                DuaCollectionDetailView(collectionId: id)
            }
        }
        .onAppear {
            session.scheduleSavedDuasRefresh()
            session.scheduleDuaCollectionsRefresh()
        }
    }

    private var signedOutContent: some View {
        GeometryReader { geo in
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    signedOutCard
                    Spacer(minLength: 0)
                }
                .frame(minHeight: geo.size.height)
                .frame(maxWidth: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .scrollIndicators(.hidden, axes: .vertical)
    }

    private var signedOutCard: some View {
        VStack(spacing: 28) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [BespokeColor.forest.opacity(0.14), BespokeColor.forest.opacity(0.06)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 96, height: 96)
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 38, weight: .medium))
                    .foregroundStyle(
                        LinearGradient(
                            colors: [BespokeColor.forest, BespokeColor.forest.opacity(0.75)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .accessibilityHidden(true)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Bookmarks")

            VStack(spacing: 12) {
                Text("My heart's duas")
                    .font(BespokeFont.display(30))
                    .foregroundStyle(BespokeColor.forest)
                    .multilineTextAlignment(.center)

                Text("Sign in to keep your favourite duas in one place, so you can return to them anytime.")
                    .font(BespokeFont.inter(16, weight: .regular))
                    .foregroundStyle(BespokeColor.muted)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 4)

            Button {
                session.presentAuth()
            } label: {
                Text("Sign in")
                    .font(BespokeFont.inter(17, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(LinearGradient.bespokeGold)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .bespokeButtonHitArea(cornerRadius: 16)
                    .shadow(color: .black.opacity(0.14), radius: 14, x: 0, y: 6)
            }
            .buttonStyle(BespokePlainButtonStyle())
        }
        .padding(32)
        .frame(maxWidth: 480)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(BespokeColor.cardBorder, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.06), radius: 20, x: 0, y: 8)
        .padding(.horizontal, 20)
    }

    private var signedInContent: some View {
        ScrollView {
            VStack(spacing: 0) {
                if session.duaCollectionsLoading && session.duaCollections.isEmpty {
                    loadingState
                        .padding(.top, 16)
                } else {
                    if let error = session.duaCollectionsError, session.duaCollections.isEmpty {
                        collectionsErrorBanner(error)
                            .padding(.top, 16)
                    }
                    hubCards
                        .padding(.top, 16)
                }
            }
            .padding(.bottom, mainTabBarClearance)
        }
        .scrollIndicators(.hidden, axes: .vertical)
    }

    private let hubCardColumns = [
        GridItem(.flexible(), spacing: 12),
        GridItem(.flexible(), spacing: 12)
    ]

    private var hubCards: some View {
        VStack(alignment: .leading, spacing: 0) {
            NavigationLink(value: HeartsDuaDestination.allSavedDuas) {
                HeartsDuaActionCard(
                    title: "All saved duas",
                    subtitle: savedDuasSubtitle,
                    symbolName: "bookmark.fill",
                    accentColors: HeartsDuaCardPalette.savedAll
                )
            }
            .buttonStyle(HeartsDuaCardButtonStyle())
            .padding(.horizontal, 20)

            Text("Collections")
                .font(BespokeFont.inter(12, weight: .semibold))
                .foregroundStyle(BespokeColor.muted)
                .textCase(.uppercase)
                .tracking(0.9)
                .padding(.horizontal, 20)
                .padding(.top, 24)
                .padding(.bottom, 12)

            if session.duaCollections.isEmpty {
                collectionsEmptyState
            } else {
                makeCollectionControl
                    .padding(.horizontal, 20)
                    .padding(.bottom, 14)

                collectionsGrid
            }
        }
    }

    private var sortedCollections: [DuaCollectionSummaryDTO] {
        session.duaCollections.sorted { $0.updatedAt > $1.updatedAt }
    }

    private var collectionsEmptyState: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Text("No collections yet")
                    .font(BespokeFont.inter(17, weight: .semibold))
                    .foregroundStyle(BespokeColor.forest)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("Create your first collection to group saved duas.")
                    .font(BespokeFont.inter(15, weight: .regular))
                    .foregroundStyle(BespokeColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            makeCollectionControl
        }
        .padding(.horizontal, 20)
    }

    private var makeCollectionControl: some View {
        Button(action: handleCreateCollectionTap) {
            MakeCollectionCard()
        }
        .buttonStyle(HeartsDuaCardButtonStyle())
    }

    private func handleCreateCollectionTap() {
        if subscriptionManager.isSubscribed {
            navigationPath.append(HeartsDuaDestination.makeCollection)
        } else {
            presentUpgradeModal?()
        }
    }

    private var collectionsGrid: some View {
        LazyVGrid(columns: hubCardColumns, spacing: 14) {
            ForEach(Array(sortedCollections.enumerated()), id: \.element.id) { index, collection in
                NavigationLink(value: HeartsDuaDestination.collection(collection.collectionId)) {
                    HeartsDuaCollectionCard(
                        collection: collection,
                        paletteIndex: index,
                        symbolName: CollectionIconCache.symbol(
                            userId: session.currentUser?.userId,
                            collectionId: collection.collectionId
                        )
                    )
                }
                .buttonStyle(HeartsDuaCardButtonStyle())
            }
        }
        .padding(.horizontal, 20)
    }

    private var savedDuasSubtitle: String {
        let count = session.savedDuas.count
        if session.savedDuasLoading && count == 0 {
            return "Loading…"
        }
        switch count {
        case 0:
            return "No duas yet"
        case 1:
            return "1 dua"
        default:
            return "\(count) duas"
        }
    }

    private var loadingState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(BespokeColor.forest)
                .scaleEffect(1.1)
            Text("Loading your collections…")
                .font(BespokeFont.inter(16, weight: .medium))
                .foregroundStyle(BespokeColor.muted)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 48)
    }

    private func collectionsErrorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 16))
                .foregroundStyle(BespokeColor.error.opacity(0.85))

            VStack(alignment: .leading, spacing: 6) {
                Text("Collections unavailable")
                    .font(BespokeFont.inter(14, weight: .semibold))
                    .foregroundStyle(BespokeColor.bodyText)

                Text(message)
                    .font(BespokeFont.inter(13, weight: .regular))
                    .foregroundStyle(BespokeColor.muted)
                    .fixedSize(horizontal: false, vertical: true)

                Button("Try again") {
                    session.scheduleDuaCollectionsRefresh()
                }
                .font(BespokeFont.inter(13, weight: .semibold))
                .foregroundStyle(BespokeColor.forest)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(BespokeColor.error.opacity(0.2), lineWidth: 1)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 12)
    }
}

struct SavedDuaKindToggle: View {
    @Binding var selection: SavedDuaKind

    var body: some View {
        HStack(spacing: 4) {
            ForEach(SavedDuaKind.allCases) { kind in
                Button {
                    withAnimation(.easeInOut(duration: 0.22)) {
                        selection = kind
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: kind.iconName)
                            .font(.system(size: 13, weight: .semibold))

                        Text(kind.title)
                            .font(BespokeFont.inter(14, weight: .semibold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.85)
                    }
                    .foregroundStyle(selection == kind ? Color.white : BespokeColor.homeGold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background {
                        if selection == kind {
                            LinearGradient.bespokeGold
                        } else {
                            Color.clear
                        }
                    }
                    .clipShape(Capsule())
                    .bespokeButtonHitArea(Capsule())
                }
                .buttonStyle(BespokePlainButtonStyle())
            }
        }
        .padding(4)
        .background(Color.white.opacity(0.72))
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .stroke(BespokeColor.homeGold.opacity(0.22), lineWidth: 1)
        }
        .padding(.horizontal, 20)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - All saved duas

private enum SavedDuaListLayout {
    static let tipRowInsets = EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20)

    static func rowInsets(selectionMode: Bool) -> EdgeInsets {
        EdgeInsets(
            top: selectionMode ? 14 : 8,
            leading: 20,
            bottom: 8,
            trailing: selectionMode ? 26 : 20
        )
    }
}

private struct SavedDuaSelectionScreenModifier: ViewModifier {
    @Environment(\.mainTabBarVisibility) private var mainTabBarVisibility
    let isSelectionMode: Bool

    func body(content: Content) -> some View {
        Group {
            if isSelectionMode {
                content
                    .toolbar(.hidden, for: .tabBar)
                    .toolbarBackground(.hidden, for: .tabBar)
            } else {
                content
            }
        }
            .onChange(of: isSelectionMode) { _, hidden in
                mainTabBarVisibility(hidden)
            }
            .onAppear {
                mainTabBarVisibility(isSelectionMode)
            }
            .onDisappear {
                mainTabBarVisibility(false)
            }
    }
}

private extension View {
    func savedDuaSelectionScreen(isActive: Bool) -> some View {
        modifier(SavedDuaSelectionScreenModifier(isSelectionMode: isActive))
    }
}

struct AllSavedDuasListView: View {
    @Environment(AppSession.self) private var session
    @Environment(SubscriptionManager.self) private var subscriptionManager
    @Environment(\.presentUpgradeModal) private var presentUpgradeModal
    @Environment(\.dismiss) private var dismiss
    @Environment(\.mainTabBarClearance) private var mainTabBarClearance
    @State private var selectedCategory: SavedDuaKind = .bespoke
    @State private var selectedSortFilter: SavedLibraryFilter = .recent
    @State private var editingDuaRow: SavedDuaDTO?
    @State private var isSelectionMode = false
    @State private var selectedDuaIds: Set<String> = []
    @State private var showMoveModal = false
    @State private var showDeleteConfirm = false
    @State private var showWriteModal = false
    @State private var bulkActionInFlight = false

    private var categoryFilteredSavedDuas: [SavedDuaDTO] {
        session.savedDuas.filter { SavedDuaDisplay.kind(from: $0) == selectedCategory }
    }

    private var effectiveSortFilter: SavedLibraryFilter {
        selectedCategory == .bespoke ? selectedSortFilter : .recent
    }

    private var filteredSavedDuas: [SavedDuaDTO] {
        SavedLibraryFiltering.filteredSavedDuas(
            categoryFilteredSavedDuas,
            filter: effectiveSortFilter,
            userId: session.currentUser?.userId
        )
    }

    private var hasCategorySavedDuas: Bool {
        !categoryFilteredSavedDuas.isEmpty
    }

    private var selectedRows: [SavedDuaDTO] {
        filteredSavedDuas.filter { selectedDuaIds.contains($0.duaId) }
    }

    private var selectionKind: SavedDuaKind? {
        let kinds = Set(selectedRows.map { SavedDuaDisplay.kind(from: $0) })
        return kinds.count == 1 ? kinds.first : nil
    }

    var body: some View {
        allSavedDuasPage
            .toolbar(.hidden, for: .navigationBar)
            .navigationBarBackButtonHidden(true)
            .bespokeEdgeBackNavigation(hidesNavigationBar: true)
            .onAppear {
                session.scheduleSavedDuasRefresh()
            }
            .overlay { allSavedDuasEditOverlay }
            .overlay { allSavedDuasMoveOverlay }
            .overlay { allSavedDuasDeleteOverlay }
            .overlay { allSavedDuasWriteOverlay }
            .overlay(alignment: .bottom) {
                allSavedDuasSelectionBar
                    .ignoresSafeArea(edges: .bottom)
            }
            .savedDuaSelectionScreen(isActive: isSelectionMode)
            .onChange(of: selectedCategory) { _, category in
                if category == .sunnah {
                    selectedSortFilter = .recent
                }
            }
    }

    private var allSavedDuasPage: some View {
        BespokeSubpageLayout(
            title: isSelectionMode ? "Select duas" : "All saved duas",
            subtitle: isSelectionMode
                ? "\(selectedDuaIds.count) selected • Tap to choose what to save"
                : "Your saved reminders and supplications",
            trailing: {
                if !isSelectionMode {
                    WriteOwnDuaToolbarButton {
                        showWriteModal = true
                    }
                }
            }
        ) {
            Group {
                if session.savedDuasLoading && session.savedDuas.isEmpty {
                    loadingState
                } else if let error = session.savedDuasError, session.savedDuas.isEmpty {
                    errorState(error)
                } else if session.savedDuas.isEmpty {
                    emptyState
                } else {
                    savedDuasContent
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    @ViewBuilder
    private var allSavedDuasEditOverlay: some View {
        if let row = editingDuaRow {
            EditSavedDuaView(
                isPresented: Binding(
                    get: { editingDuaRow != nil },
                    set: { if !$0 { editingDuaRow = nil } }
                ),
                row: row,
                userId: session.currentUser?.userId
            )
        }
    }

    @ViewBuilder
    private var allSavedDuasMoveOverlay: some View {
        if showMoveModal, let kind = selectionKind {
            SavedDuaMoveModalView(
                isPresented: $showMoveModal,
                duaIds: selectedDuaIds,
                duaKind: kind,
                canUseCollections: subscriptionManager.isSubscribed,
                onAddCollections: { presentUpgradeModal?() },
                onSaved: {
                    exitSelectionMode()
                }
            )
        }
    }

    @ViewBuilder
    private var allSavedDuasWriteOverlay: some View {
        if showWriteModal {
            WriteOwnDuaModalView(
                isPresented: $showWriteModal,
                onSaved: { _ in
                    selectedCategory = .bespoke
                    selectedSortFilter = .recent
                }
            )
        }
    }

    @ViewBuilder
    private var allSavedDuasDeleteOverlay: some View {
        if showDeleteConfirm {
            BespokeConfirmModal(
                title: deleteConfirmTitle,
                message: deleteConfirmMessage,
                confirmTitle: bulkActionInFlight ? "Deleting…" : "Delete",
                confirmStyle: .destructive,
                inFlight: bulkActionInFlight,
                onCancel: {
                    guard !bulkActionInFlight else { return }
                    showDeleteConfirm = false
                },
                onConfirm: {
                    Task { await deleteSelected() }
                }
            )
        }
    }

    @ViewBuilder
    private var allSavedDuasSelectionBar: some View {
        if isSelectionMode {
            SavedDuaSelectionBar(
                selectedCount: selectedDuaIds.count,
                context: .library,
                showsMove: true,
                onDelete: { showDeleteConfirm = true },
                onMove: { beginMove() },
                onDone: { exitSelectionMode() }
            )
        }
    }

    private var deleteConfirmTitle: String {
        selectedDuaIds.count == 1 ? "Delete saved dua?" : "Delete \(selectedDuaIds.count) duas?"
    }

    private var deleteConfirmMessage: String {
        "This removes the selected duas from your library and any collections."
    }

    private func enterSelectionMode(selecting duaId: String) {
        isSelectionMode = true
        selectedDuaIds = [duaId]
    }

    private func toggleSelection(_ duaId: String) {
        if selectedDuaIds.contains(duaId) {
            selectedDuaIds.remove(duaId)
        } else {
            selectedDuaIds.insert(duaId)
        }
        BespokeHaptics.toggle()
        if selectedDuaIds.isEmpty {
            isSelectionMode = false
        }
    }

    private func exitSelectionMode() {
        isSelectionMode = false
        selectedDuaIds.removeAll()
        showMoveModal = false
        showDeleteConfirm = false
    }

    private func beginMove() {
        guard !selectedDuaIds.isEmpty else { return }
        guard selectionKind != nil else { return }
        if subscriptionManager.isSubscribed {
            showMoveModal = true
        } else {
            presentUpgradeModal?()
        }
    }

    private var savedDuasContent: some View {
        VStack(spacing: 0) {
            SavedDuaKindToggle(selection: $selectedCategory)
                .padding(.top, 18)
                .padding(.bottom, 12)

            if hasCategorySavedDuas, selectedCategory == .bespoke {
                SavedLibraryFilterChips(selection: $selectedSortFilter)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
            }

            if !hasCategorySavedDuas {
                filteredCategoryEmptyState
            } else if selectedCategory == .bespoke, filteredSavedDuas.isEmpty {
                filteredSortEmptyState
            } else {
                savedDuasList
            }
        }
    }

    private var filteredSortEmptyState: some View {
        ContentUnavailableView {
            Label("No edited duas", systemImage: "pencil")
        } description: {
            Text("Duas you edit will appear here.")
                .font(BespokeFont.inter(15, weight: .regular))
                .foregroundStyle(BespokeColor.muted)
                .multilineTextAlignment(.center)
        }
        .symbolRenderingMode(.hierarchical)
        .foregroundStyle(BespokeColor.muted)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var savedDuasList: some View {
        List {
            if !isSelectionMode {
                SavedDuaSelectionTipCard()
                    .listRowInsets(SavedDuaListLayout.tipRowInsets)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }

            ForEach(filteredSavedDuas) { row in
                SavedDuaCardView(
                    row: row,
                    userId: session.currentUser?.userId,
                    isSavedVisual: true,
                    onSave: {
                        Task { await delete(row) }
                    },
                    onEdit: !isSelectionMode && SavedDuaDisplay.kind(from: row) == .bespoke
                        ? { editingDuaRow = row }
                        : nil,
                    isSelectionMode: isSelectionMode,
                    isSelected: selectedDuaIds.contains(row.duaId),
                    onLongPress: {
                        if isSelectionMode {
                            toggleSelection(row.duaId)
                        } else {
                            BespokeHaptics.selectionModeEntered()
                            enterSelectionMode(selecting: row.duaId)
                        }
                    },
                    onToggleSelection: {
                        toggleSelection(row.duaId)
                    }
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .listRowInsets(SavedDuaListLayout.rowInsets(selectionMode: isSelectionMode))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
                .swipeActions(edge: .trailing, allowsFullSwipe: !isSelectionMode) {
                    Button(role: .destructive) {
                        Task { await delete(row) }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden, axes: .vertical)
        .contentMargins(.top, isSelectionMode ? BespokeSubpageLayoutMetrics.listTopSpacing : 0, for: .scrollContent)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: isSelectionMode ? SavedDuaSelectionBar.scrollClearanceHeight : mainTabBarClearance)
        }
    }

    private var loadingState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(BespokeColor.forest)
                .scaleEffect(1.1)
            Text("Loading your saved duas…")
                .font(BespokeFont.inter(16, weight: .medium))
                .foregroundStyle(BespokeColor.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private func errorState(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Saved duas unavailable", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
                .font(BespokeFont.inter(15, weight: .regular))
                .foregroundStyle(BespokeColor.muted)
                .multilineTextAlignment(.center)
        } actions: {
            Button("Try again") {
                session.scheduleSavedDuasRefresh()
            }
            .font(BespokeFont.inter(15, weight: .semibold))
        }
        .symbolRenderingMode(.hierarchical)
        .foregroundStyle(BespokeColor.error.opacity(0.85))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("Nothing saved yet", systemImage: "bookmark")
        } description: {
            Text("When you bookmark a dua, it appears here.")
                .font(BespokeFont.inter(15, weight: .regular))
                .foregroundStyle(BespokeColor.muted)
                .multilineTextAlignment(.center)
        }
        .symbolRenderingMode(.hierarchical)
        .foregroundStyle(BespokeColor.muted)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var filteredCategoryEmptyState: some View {
        ContentUnavailableView {
            Label("No \(selectedCategory.title.lowercased())", systemImage: selectedCategory.iconName)
        } description: {
            Text("You don't have any saved \(selectedCategory == .sunnah ? "sunnah" : "bespoke") duas yet.")
                .font(BespokeFont.inter(15, weight: .regular))
                .foregroundStyle(BespokeColor.muted)
                .multilineTextAlignment(.center)
        }
        .symbolRenderingMode(.hierarchical)
        .foregroundStyle(BespokeColor.muted)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private func delete(_ row: SavedDuaDTO) async {
        do {
            try await session.deleteSavedDuaRow(row)
            if let uid = session.currentUser?.userId {
                SavedDuaReflectionsCache.remove(userId: uid, duaId: row.duaId)
            }
        } catch {
            // Keep the list visible; user can swipe again later.
        }
    }

    @MainActor
    private func deleteSelected() async {
        guard !bulkActionInFlight else { return }
        bulkActionInFlight = true
        defer {
            bulkActionInFlight = false
            showDeleteConfirm = false
        }

        for row in selectedRows {
            do {
                try await session.deleteSavedDuaRow(row)
                if let uid = session.currentUser?.userId {
                    SavedDuaReflectionsCache.remove(userId: uid, duaId: row.duaId)
                }
            } catch {
                continue
            }
        }

        BespokeHaptics.success()
        exitSelectionMode()
    }
}

// MARK: - Make collection

private enum MakeCollectionField: Hashable {
    case name
    case description
}

struct MakeDuaCollectionView: View {
    @Environment(AppSession.self) private var session
    @Environment(SubscriptionManager.self) private var subscriptionManager
    @Environment(\.presentUpgradeModal) private var presentUpgradeModal
    @Environment(\.dismiss) private var dismiss
    @Environment(\.mainTabBarClearance) private var mainTabBarClearance

    @State private var pickerKind: SavedDuaKind = .bespoke

    @FocusState private var focusedField: MakeCollectionField?
    @State private var name = ""
    @State private var description = ""
    @State private var selectedIcon = DuaCollectionIcons.defaultSymbol
    @State private var selectedDuaIds: Set<String> = []
    @State private var submitInFlight = false
    @State private var submitError: String?

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        !trimmedName.isEmpty && !submitInFlight
    }

    private var matchingSavedDuas: [SavedDuaDTO] {
        session.savedDuas.filter { SavedDuaDisplay.kind(from: $0) == pickerKind }
    }

    private var selectedInCurrentPicker: Int {
        matchingSavedDuas.filter { selectedDuaIds.contains($0.duaId) }.count
    }

    var body: some View {
        BespokeSubpageLayout(
            title: "Make a collection",
            subtitle: "Name your collection — add saved duas now or later"
        ) {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    collectionFormFields

                    if let submitError {
                        Text(submitError)
                            .font(BespokeFont.inter(14, weight: .medium))
                            .foregroundStyle(BespokeColor.error)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    savedDuaPickerSection

                    Button {
                        Task { await submit() }
                    } label: {
                        Group {
                            if submitInFlight {
                                ProgressView()
                                    .tint(.white)
                            } else {
                                Text("Create collection")
                                    .font(BespokeFont.inter(17, weight: .semibold))
                            }
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(canSubmit ? AnyShapeStyle(LinearGradient.bespokeGold) : AnyShapeStyle(BespokeColor.muted.opacity(0.35)))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .bespokeButtonHitArea(cornerRadius: 16)
                    }
                    .buttonStyle(BespokePlainButtonStyle())
                    .disabled(!canSubmit)
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 28 + mainTabBarClearance)
            }
            .scrollIndicators(.hidden, axes: .vertical)
            .scrollDismissesKeyboard(.interactively)
        }
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .bespokeEdgeBackNavigation(hidesNavigationBar: true)
        .onAppear {
            session.scheduleSavedDuasRefresh()
            guard subscriptionManager.isSubscribed else {
                dismiss()
                presentUpgradeModal?()
                return
            }
        }
    }

    private var collectionFormFields: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Choose an icon")
                    .font(BespokeFont.inter(14, weight: .semibold))
                    .foregroundStyle(BespokeColor.fieldLabel)

                CollectionIconPicker(selectedSymbol: $selectedIcon)
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Collection name")
                    .font(BespokeFont.inter(14, weight: .semibold))
                    .foregroundStyle(BespokeColor.fieldLabel)

                TextField("e.g. Morning duas", text: $name)
                    .font(BespokeFont.inter(16, weight: .regular))
                    .focused($focusedField, equals: .name)
                    .submitLabel(.done)
                    .onSubmit { focusedField = nil }
                    .padding(14)
                    .background(BespokeColor.inputSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(BespokeColor.inputBorder, lineWidth: 1)
                    }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Description")
                    .font(BespokeFont.inter(14, weight: .semibold))
                    .foregroundStyle(BespokeColor.fieldLabel)

                TextField("Optional note about this collection", text: $description, axis: .vertical)
                    .font(BespokeFont.inter(16, weight: .regular))
                    .lineLimit(3 ... 6)
                    .focused($focusedField, equals: .description)
                    .submitLabel(.done)
                    .onSubmit { focusedField = nil }
                    .padding(14)
                    .background(BespokeColor.inputSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(BespokeColor.inputBorder, lineWidth: 1)
                    }
            }
        }
    }

    @ViewBuilder
    private var savedDuaPickerSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Add saved duas (optional)")
                .font(BespokeFont.inter(14, weight: .semibold))
                .foregroundStyle(BespokeColor.fieldLabel)

            SavedDuaKindToggle(selection: $pickerKind)
                .padding(.horizontal, -20)

            if session.savedDuasLoading && session.savedDuas.isEmpty {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(BespokeColor.forest)
                    Text("Loading saved duas…")
                        .font(BespokeFont.inter(15, weight: .medium))
                        .foregroundStyle(BespokeColor.muted)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 12)
            } else if matchingSavedDuas.isEmpty {
                Text("No saved \(pickerKind == .sunnah ? "sunnah" : "bespoke") duas yet. You can create the collection now and add duas later.")
                    .font(BespokeFont.inter(15, weight: .regular))
                    .foregroundStyle(BespokeColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                if selectedDuaIds.count > selectedInCurrentPicker {
                    Text("\(selectedDuaIds.count) duas selected in total")
                        .font(BespokeFont.inter(13, weight: .medium))
                        .foregroundStyle(BespokeColor.muted)
                }

                Text("\(selectedInCurrentPicker) of \(matchingSavedDuas.count) selected")
                    .font(BespokeFont.inter(13, weight: .medium))
                    .foregroundStyle(BespokeColor.muted)

                LazyVStack(spacing: 10) {
                    ForEach(matchingSavedDuas) { row in
                        SavedDuaSelectionRow(
                            row: row,
                            userId: session.currentUser?.userId,
                            isSelected: selectedDuaIds.contains(row.duaId),
                            style: .collectionPicker
                        ) {
                            toggleSelection(row.duaId)
                        }
                    }
                }
            }
        }
    }

    private func toggleSelection(_ duaId: String) {
        if selectedDuaIds.contains(duaId) {
            selectedDuaIds.remove(duaId)
        } else {
            selectedDuaIds.insert(duaId)
        }
    }

    @MainActor
    private func submit() async {
        guard let userId = session.currentUser?.userId else { return }
        guard canSubmit else { return }

        focusedField = nil
        submitInFlight = true
        submitError = nil
        defer { submitInFlight = false }

        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let created = try await session.api().createDuaCollection(
                CreateDuaCollectionRequest(
                    userId: userId,
                    name: trimmedName,
                    description: trimmedDescription.isEmpty ? nil : trimmedDescription,
                    duaIds: Array(selectedDuaIds)
                )
            )
            session.upsertDuaCollection(from: created)
            if let userId = session.currentUser?.userId {
                CollectionIconCache.store(userId: userId, collectionId: created.collectionId, symbolName: selectedIcon)
            }
            dismiss()
        } catch {
            submitError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

// MARK: - Collection detail / edit

struct DuaCollectionDetailView: View {
    @Environment(AppSession.self) private var session
    @Environment(SubscriptionManager.self) private var subscriptionManager
    @Environment(\.presentUpgradeModal) private var presentUpgradeModal
    @Environment(\.dismiss) private var dismiss
    @Environment(\.mainTabBarClearance) private var mainTabBarClearance

    let collectionId: String

    @State private var detail: DuaCollectionDetailDTO?
    @State private var loading = false
    @State private var loadError: String?
    @State private var isEditing = false
    @State private var editName = ""
    @State private var editDescription = ""
    @State private var editSelectedIcon = DuaCollectionIcons.defaultSymbol
    @State private var editSelectedDuaIds: Set<String> = []
    @State private var saveInFlight = false
    @State private var saveError: String?
    @State private var showDeleteCollectionConfirm = false
    @State private var deleteCollectionInFlight = false
    @State private var deleteCollectionError: String?
    @State private var selectedCategory: SavedDuaKind = .bespoke
    @State private var selectedSortFilter: SavedLibraryFilter = .recent
    @State private var editingDuaRow: SavedDuaDTO?
    @State private var isSelectionMode = false
    @State private var selectedDuaIds: Set<String> = []
    @State private var showMoveModal = false
    @State private var showRemoveConfirm = false
    @State private var showWriteModal = false
    @State private var bulkActionInFlight = false

    private var displayedDuas: [SavedDuaDTO] {
        if let detail, !detail.savedDuas.isEmpty {
            return detail.savedDuas
        }
        let ids = Set(detail?.savedDuaIds ?? [])
        return session.savedDuas.filter { ids.contains($0.duaId) }
    }

    private var categoryFilteredDisplayedDuas: [SavedDuaDTO] {
        displayedDuas.filter { SavedDuaDisplay.kind(from: $0) == selectedCategory }
    }

    private var effectiveSortFilter: SavedLibraryFilter {
        selectedCategory == .bespoke ? selectedSortFilter : .recent
    }

    private var filteredDisplayedDuas: [SavedDuaDTO] {
        SavedLibraryFiltering.filteredSavedDuas(
            categoryFilteredDisplayedDuas,
            filter: effectiveSortFilter,
            userId: session.currentUser?.userId
        )
    }

    private var hasCategoryDisplayedDuas: Bool {
        !categoryFilteredDisplayedDuas.isEmpty
    }

    private var selectedRows: [SavedDuaDTO] {
        filteredDisplayedDuas.filter { selectedDuaIds.contains($0.duaId) }
    }

    private var selectionKind: SavedDuaKind? {
        let kinds = Set(selectedRows.map { SavedDuaDisplay.kind(from: $0) })
        return kinds.count == 1 ? kinds.first : nil
    }

    private var trimmedEditName: String {
        editName.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSaveEdits: Bool {
        isEditing && !trimmedEditName.isEmpty && !saveInFlight
    }

    private var collectionKind: SavedDuaKind {
        if let detail {
            return DuaCollectionDisplay.inferredKind(from: detail.savedDuas)
                ?? CollectionKindCache.kind(userId: session.currentUser?.userId, collectionId: collectionId)
                ?? .bespoke
        }
        return CollectionKindCache.kind(userId: session.currentUser?.userId, collectionId: collectionId) ?? .bespoke
    }

    private var selectableSavedDuas: [SavedDuaDTO] {
        session.savedDuas.filter { SavedDuaDisplay.kind(from: $0) == selectedCategory }
    }

    var body: some View {
        collectionPage
            .toolbar(.hidden, for: .navigationBar)
            .navigationBarBackButtonHidden(true)
            .bespokeEdgeBackNavigation(hidesNavigationBar: true)
            .task(id: collectionId) {
                await loadDetail()
            }
            .onAppear {
                session.scheduleSavedDuasRefresh()
            }
            .onChange(of: detail?.collectionId) { _, _ in
                selectedCategory = collectionKind
            }
            .onChange(of: selectedCategory) { _, category in
                if category == .sunnah {
                    selectedSortFilter = .recent
                }
            }
            .overlay { collectionEditOverlay }
            .overlay { collectionDeleteOverlay }
            .overlay { collectionRemoveOverlay }
            .overlay { collectionMoveOverlay }
            .overlay { collectionWriteOverlay }
            .overlay(alignment: .bottom) {
                collectionSelectionBar
                    .ignoresSafeArea(edges: .bottom)
            }
            .savedDuaSelectionScreen(isActive: isSelectionMode)
    }

    private var collectionPage: some View {
        BespokeSubpageLayout(
            title: collectionHeaderTitle,
            subtitle: headerSubtitle,
            trailing: {
                collectionHeaderTrailing
            },
            content: {
                Group {
                    if loading && detail == nil {
                        loadingState
                    } else if let loadError, detail == nil {
                        errorState(loadError)
                    } else if isEditing {
                        editContent
                    } else if displayedDuas.isEmpty {
                        emptyCollectionState
                    } else if !hasCategoryDisplayedDuas {
                        filteredCategoryEmptyState
                    } else if selectedCategory == .bespoke, filteredDisplayedDuas.isEmpty {
                        filteredCollectionSortEmptyState
                    } else {
                        collectionDetailContent
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        )
    }

    @ViewBuilder
    private var collectionHeaderTrailing: some View {
        if isSelectionMode {
            EmptyView()
        } else if isEditing {
            Button("Cancel") {
                cancelEditing()
            }
            .font(BespokeFont.inter(15, weight: .semibold))
            .foregroundStyle(.white)
        } else {
            HStack(spacing: 2) {
                WriteOwnDuaToolbarButton {
                    showWriteModal = true
                }

                if detail != nil && !loading {
                    collectionMoreMenu
                }
            }
        }
    }

    private var collectionMoreMenu: some View {
        Menu {
            Button {
                beginEditing()
            } label: {
                Label("Edit collection", systemImage: "pencil")
            }

            Button(role: .destructive) {
                deleteCollectionError = nil
                showDeleteCollectionConfirm = true
            } label: {
                Label("Delete collection", systemImage: "trash")
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
    }

    @ViewBuilder
    private var collectionEditOverlay: some View {
        if let row = editingDuaRow {
            EditSavedDuaView(
                isPresented: Binding(
                    get: { editingDuaRow != nil },
                    set: { if !$0 { editingDuaRow = nil } }
                ),
                row: row,
                userId: session.currentUser?.userId,
                onSaved: { updated in
                    patchDetailDua(updated)
                }
            )
        }
    }

    @ViewBuilder
    private var collectionDeleteOverlay: some View {
        if showDeleteCollectionConfirm {
            BespokeConfirmModal(
                title: "Delete collection?",
                message: "“\(detail?.name ?? "This collection")” will be removed. Your saved duas stay in your library.",
                confirmTitle: deleteCollectionInFlight ? "Deleting…" : "Delete",
                confirmStyle: .destructive,
                inFlight: deleteCollectionInFlight,
                errorMessage: deleteCollectionError,
                onCancel: {
                    guard !deleteCollectionInFlight else { return }
                    showDeleteCollectionConfirm = false
                    deleteCollectionError = nil
                },
                onConfirm: {
                    Task { await deleteCollection() }
                }
            )
        }
    }

    @ViewBuilder
    private var collectionRemoveOverlay: some View {
        if showRemoveConfirm {
            BespokeConfirmModal(
                title: removeConfirmTitle,
                message: "They'll stay in your main library.",
                confirmTitle: bulkActionInFlight ? "Removing…" : "Remove",
                confirmStyle: .destructive,
                inFlight: bulkActionInFlight,
                onCancel: {
                    guard !bulkActionInFlight else { return }
                    showRemoveConfirm = false
                },
                onConfirm: {
                    Task { await removeSelectedFromCollection() }
                }
            )
        }
    }

    @ViewBuilder
    private var collectionWriteOverlay: some View {
        if showWriteModal {
            WriteOwnDuaModalView(
                isPresented: $showWriteModal,
                collectionId: collectionId,
                onSaved: { saved in
                    selectedCategory = .bespoke
                    selectedSortFilter = .recent
                    appendWrittenDua(saved)
                }
            )
        }
    }

    @ViewBuilder
    private var collectionMoveOverlay: some View {
        if showMoveModal, let kind = selectionKind {
            SavedDuaMoveModalView(
                isPresented: $showMoveModal,
                duaIds: selectedDuaIds,
                duaKind: kind,
                canUseCollections: subscriptionManager.isSubscribed,
                onAddCollections: { presentUpgradeModal?() },
                onSaved: {
                    Task { await loadDetail() }
                    exitSelectionMode()
                }
            )
        }
    }

    @ViewBuilder
    private var collectionSelectionBar: some View {
        if isSelectionMode {
            SavedDuaSelectionBar(
                selectedCount: selectedDuaIds.count,
                context: .collection,
                showsMove: true,
                onDelete: { showRemoveConfirm = true },
                onMove: { beginMove() },
                onDone: { exitSelectionMode() }
            )
        }
    }

    private var collectionHeaderTitle: String {
        if isSelectionMode {
            return "Select duas"
        }
        if isEditing {
            return "Edit collection"
        }
        return detail?.name ?? "Collection"
    }

    private var removeConfirmTitle: String {
        selectedDuaIds.count == 1
            ? "Remove from collection?"
            : "Remove \(selectedDuaIds.count) duas from collection?"
    }

    private var collectionDetailContent: some View {
        VStack(spacing: 0) {
            SavedDuaKindToggle(selection: $selectedCategory)
                .padding(.top, 18)
                .padding(.bottom, 12)

            if selectedCategory == .bespoke {
                SavedLibraryFilterChips(selection: $selectedSortFilter)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 12)
            }

            collectionDuasList
        }
    }

    private var filteredCollectionSortEmptyState: some View {
        ContentUnavailableView {
            Label("No edited duas", systemImage: "pencil")
        } description: {
            Text("Duas you edit in this collection will appear here.")
                .font(BespokeFont.inter(15, weight: .regular))
                .foregroundStyle(BespokeColor.muted)
                .multilineTextAlignment(.center)
        }
        .symbolRenderingMode(.hierarchical)
        .foregroundStyle(BespokeColor.muted)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var headerSubtitle: String? {
        if isSelectionMode {
            return "\(selectedDuaIds.count) selected • Tap to choose what to save"
        }
        if isEditing {
            return "Update the name, description, or duas"
        }
        if let description = detail?.description?.trimmingCharacters(in: .whitespacesAndNewlines),
           !description.isEmpty {
            return description
        }
        let count = displayedDuas.count
        switch count {
        case 0:
            return nil
        case 1:
            return "1 dua"
        default:
            return "\(count) duas"
        }
    }

    private var editContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                SavedDuaKindToggle(selection: $selectedCategory)
                    .padding(.horizontal, -20)

                VStack(alignment: .leading, spacing: 10) {
                    Text("Choose an icon")
                        .font(BespokeFont.inter(14, weight: .semibold))
                        .foregroundStyle(BespokeColor.fieldLabel)

                    CollectionIconPicker(selectedSymbol: $editSelectedIcon)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Collection name")
                        .font(BespokeFont.inter(14, weight: .semibold))
                        .foregroundStyle(BespokeColor.fieldLabel)

                    TextField("Collection name", text: $editName)
                        .font(BespokeFont.inter(16, weight: .regular))
                        .padding(14)
                        .background(BespokeColor.inputSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(BespokeColor.inputBorder, lineWidth: 1)
                        }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Description")
                        .font(BespokeFont.inter(14, weight: .semibold))
                        .foregroundStyle(BespokeColor.fieldLabel)

                    TextField("Optional description", text: $editDescription, axis: .vertical)
                        .font(BespokeFont.inter(16, weight: .regular))
                        .lineLimit(3 ... 6)
                        .padding(14)
                        .background(BespokeColor.inputSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(BespokeColor.inputBorder, lineWidth: 1)
                        }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Saved duas in this collection")
                        .font(BespokeFont.inter(14, weight: .semibold))
                        .foregroundStyle(BespokeColor.fieldLabel)

                    Text("\(editSelectedDuaIds.count) selected")
                        .font(BespokeFont.inter(13, weight: .medium))
                        .foregroundStyle(BespokeColor.muted)

                    LazyVStack(spacing: 10) {
                        ForEach(selectableSavedDuas) { row in
                            SavedDuaSelectionRow(
                                row: row,
                                userId: session.currentUser?.userId,
                                isSelected: editSelectedDuaIds.contains(row.duaId)
                            ) {
                                toggleEditSelection(row.duaId)
                            }
                        }
                    }
                }

                if let saveError {
                    Text(saveError)
                        .font(BespokeFont.inter(14, weight: .medium))
                        .foregroundStyle(BespokeColor.error)
                }

                Button {
                    Task { await saveEdits() }
                } label: {
                    Group {
                        if saveInFlight {
                            ProgressView()
                                .tint(.white)
                        } else {
                            Text("Save changes")
                                .font(BespokeFont.inter(17, weight: .semibold))
                        }
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(canSaveEdits ? AnyShapeStyle(LinearGradient.bespokeGold) : AnyShapeStyle(BespokeColor.muted.opacity(0.35)))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .bespokeButtonHitArea(cornerRadius: 16)
                }
                .buttonStyle(BespokePlainButtonStyle())
                .disabled(!canSaveEdits)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 28 + mainTabBarClearance)
        }
        .scrollIndicators(.hidden, axes: .vertical)
    }

    private var collectionDuasList: some View {
        List {
            if !isSelectionMode {
                SavedDuaSelectionTipCard()
                    .listRowInsets(SavedDuaListLayout.tipRowInsets)
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
            }

            ForEach(filteredDisplayedDuas) { row in
                SavedDuaCardView(
                    row: row,
                    userId: session.currentUser?.userId,
                    isSavedVisual: true,
                    onSave: {
                        Task { await unsaveFromCollectionContext(row) }
                    },
                    onEdit: !isSelectionMode && SavedDuaDisplay.kind(from: row) == .bespoke
                        ? { editingDuaRow = row }
                        : nil,
                    isSelectionMode: isSelectionMode,
                    isSelected: selectedDuaIds.contains(row.duaId),
                    onLongPress: {
                        if isSelectionMode {
                            toggleSelection(row.duaId)
                        } else {
                            BespokeHaptics.selectionModeEntered()
                            enterSelectionMode(selecting: row.duaId)
                        }
                    },
                    onToggleSelection: {
                        toggleSelection(row.duaId)
                    }
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                .listRowInsets(SavedDuaListLayout.rowInsets(selectionMode: isSelectionMode))
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .scrollIndicators(.hidden, axes: .vertical)
        .contentMargins(.top, isSelectionMode ? BespokeSubpageLayoutMetrics.listTopSpacing : 0, for: .scrollContent)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: isSelectionMode ? SavedDuaSelectionBar.scrollClearanceHeight : mainTabBarClearance)
        }
    }

    private var loadingState: some View {
        VStack(spacing: 16) {
            ProgressView()
                .tint(BespokeColor.forest)
                .scaleEffect(1.1)
            Text("Loading collection…")
                .font(BespokeFont.inter(16, weight: .medium))
                .foregroundStyle(BespokeColor.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private func errorState(_ message: String) -> some View {
        ContentUnavailableView {
            Label("Couldn't load collection", systemImage: "wifi.exclamationmark")
        } description: {
            Text(message)
                .font(BespokeFont.inter(15, weight: .regular))
                .foregroundStyle(BespokeColor.muted)
                .multilineTextAlignment(.center)
        } actions: {
            Button("Try again") {
                Task { await loadDetail() }
            }
            .font(BespokeFont.inter(15, weight: .semibold))
        }
        .symbolRenderingMode(.hierarchical)
        .foregroundStyle(BespokeColor.error.opacity(0.85))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var emptyCollectionState: some View {
        ContentUnavailableView {
            Label("No duas yet", systemImage: "tray")
        } description: {
            Text("Use the menu to edit this collection and add saved duas.")
                .font(BespokeFont.inter(15, weight: .regular))
                .foregroundStyle(BespokeColor.muted)
                .multilineTextAlignment(.center)
        }
        .symbolRenderingMode(.hierarchical)
        .foregroundStyle(BespokeColor.muted)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var filteredCategoryEmptyState: some View {
        VStack(spacing: 0) {
            SavedDuaKindToggle(selection: $selectedCategory)
                .padding(.top, 18)
                .padding(.bottom, 12)

            ContentUnavailableView {
                Label("No \(selectedCategory.title.lowercased())", systemImage: selectedCategory.iconName)
            } description: {
                Text("This collection has no saved \(selectedCategory == .sunnah ? "sunnah" : "bespoke") duas yet.")
                    .font(BespokeFont.inter(15, weight: .regular))
                    .foregroundStyle(BespokeColor.muted)
                    .multilineTextAlignment(.center)
            }
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(BespokeColor.muted)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
        }
    }

    private func beginEditing() {
        guard let detail else { return }
        editName = detail.name
        editDescription = detail.description ?? ""
        editSelectedDuaIds = Set(detail.savedDuaIds)
        editSelectedIcon = CollectionIconCache.symbol(
            userId: session.currentUser?.userId,
            collectionId: collectionId
        )
        selectedCategory = collectionKind
        saveError = nil
        isEditing = true
    }

    private func cancelEditing() {
        isEditing = false
        saveError = nil
    }

    private func toggleEditSelection(_ duaId: String) {
        if editSelectedDuaIds.contains(duaId) {
            editSelectedDuaIds.remove(duaId)
        } else {
            editSelectedDuaIds.insert(duaId)
        }
    }

    @MainActor
    private func loadDetail() async {
        loading = true
        loadError = nil
        defer { loading = false }

        do {
            let loaded = try await session.api().duaCollection(id: collectionId)
            detail = loaded
            selectedCategory = DuaCollectionDisplay.inferredKind(from: loaded.savedDuas)
                ?? CollectionKindCache.kind(userId: session.currentUser?.userId, collectionId: collectionId)
                ?? .bespoke
            session.upsertDuaCollection(from: loaded)
            loadError = nil
        } catch {
            if error is CancellationError { return }
            if let urlError = error as? URLError, urlError.code == .cancelled { return }
            loadError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    @MainActor
    private func saveEdits() async {
        guard canSaveEdits else { return }

        saveInFlight = true
        saveError = nil
        defer { saveInFlight = false }

        let trimmedDescription = editDescription.trimmingCharacters(in: .whitespacesAndNewlines)

        do {
            let updated = try await session.api().updateDuaCollection(
                id: collectionId,
                body: UpdateDuaCollectionRequest(
                    name: trimmedEditName,
                    description: trimmedDescription.isEmpty ? nil : trimmedDescription,
                    duaIds: Array(editSelectedDuaIds)
                )
            )
            detail = updated
            session.upsertDuaCollection(from: updated)
            if let userId = session.currentUser?.userId {
                CollectionIconCache.store(userId: userId, collectionId: collectionId, symbolName: editSelectedIcon)
            }
            isEditing = false
        } catch {
            saveError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func appendWrittenDua(_ saved: SavedDuaDTO) {
        guard let current = detail else {
            Task {
                await loadDetail()
                selectedCategory = .bespoke
            }
            return
        }
        guard !current.savedDuas.contains(where: { $0.duaId == saved.duaId }) else { return }
        var savedDuas = current.savedDuas
        savedDuas.insert(saved, at: 0)
        detail = DuaCollectionDetailDTO(
            collectionId: current.collectionId,
            name: current.name,
            description: current.description,
            createdAt: current.createdAt,
            updatedAt: current.updatedAt,
            savedDuas: savedDuas
        )
    }

    private func patchDetailDua(_ updated: SavedDuaDTO) {
        guard let current = detail else { return }
        guard let index = current.savedDuas.firstIndex(where: { $0.duaId == updated.duaId }) else { return }
        var savedDuas = current.savedDuas
        savedDuas[index] = updated
        detail = DuaCollectionDetailDTO(
            collectionId: current.collectionId,
            name: current.name,
            description: current.description,
            createdAt: current.createdAt,
            updatedAt: current.updatedAt,
            savedDuas: savedDuas
        )
    }

    private func enterSelectionMode(selecting duaId: String) {
        isSelectionMode = true
        selectedDuaIds = [duaId]
    }

    private func toggleSelection(_ duaId: String) {
        if selectedDuaIds.contains(duaId) {
            selectedDuaIds.remove(duaId)
        } else {
            selectedDuaIds.insert(duaId)
        }
        BespokeHaptics.toggle()
        if selectedDuaIds.isEmpty {
            isSelectionMode = false
        }
    }

    private func exitSelectionMode() {
        isSelectionMode = false
        selectedDuaIds.removeAll()
        showMoveModal = false
        showRemoveConfirm = false
    }

    private func beginMove() {
        guard !selectedDuaIds.isEmpty else { return }
        guard selectionKind != nil else { return }
        if subscriptionManager.isSubscribed {
            showMoveModal = true
        } else {
            presentUpgradeModal?()
        }
    }

    @MainActor
    private func removeSelectedFromCollection() async {
        guard !bulkActionInFlight, var current = detail else { return }
        bulkActionInFlight = true
        defer {
            bulkActionInFlight = false
            showRemoveConfirm = false
        }

        var duaIds = current.savedDuaIds
        for duaId in selectedDuaIds {
            duaIds.removeAll { $0 == duaId }
        }

        do {
            let updated = try await session.api().updateDuaCollection(
                id: collectionId,
                body: UpdateDuaCollectionRequest(
                    name: current.name,
                    description: current.description,
                    duaIds: duaIds
                )
            )
            detail = updated
            session.upsertDuaCollection(from: updated)
            BespokeHaptics.success()
            exitSelectionMode()
        } catch {
            // Keep selection visible so the user can retry.
        }
    }

    private func unsaveFromCollectionContext(_ row: SavedDuaDTO) async {
        do {
            try await session.deleteSavedDuaRow(row)
            if let uid = session.currentUser?.userId {
                SavedDuaReflectionsCache.remove(userId: uid, duaId: row.duaId)
            }
            await loadDetail()
        } catch {
            // Keep collection visible; user can try again.
        }
    }

    @MainActor
    private func deleteCollection() async {
        guard !deleteCollectionInFlight else { return }

        deleteCollectionInFlight = true
        deleteCollectionError = nil
        defer { deleteCollectionInFlight = false }

        do {
            try await session.api().deleteDuaCollection(id: collectionId)
            session.removeDuaCollection(id: collectionId)
            if let userId = session.currentUser?.userId {
                CollectionIconCache.remove(userId: userId, collectionId: collectionId)
            }
            showDeleteCollectionConfirm = false
            dismiss()
        } catch {
            deleteCollectionError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}

// MARK: - Shared components

private enum HeartsDuaCardLayout {
    static let cornerRadius: CGFloat = 20
    static let contentPadding: CGFloat = 24
    static let textBottomInset: CGFloat = 36
    static let heroHeight: CGFloat = 240
}

private enum HeartsDuaSquareCardStyle {
    static let cornerRadius: CGFloat = HeartsDuaCardLayout.cornerRadius
}

private struct HeartsDuaCardFrame<Content: View>: View {
    enum Style {
        case square
        case hero
    }

    let style: Style
    @ViewBuilder let content: () -> Content

    var body: some View {
        Group {
            switch style {
            case .square:
                Color.clear
                    .aspectRatio(1, contentMode: .fit)
            case .hero:
                Color.clear
                    .frame(height: HeartsDuaCardLayout.heroHeight)
            }
        }
        .frame(maxWidth: .infinity)
        .overlay {
            content()
        }
        .clipShape(RoundedRectangle(cornerRadius: HeartsDuaCardLayout.cornerRadius, style: .continuous))
    }
}

private struct HeartsDuaCardTextBlock: View {
    let title: String
    let subtitle: String
    var titleColor: Color = .white
    var subtitleColor: Color = Color.white.opacity(0.82)

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title)
                .font(BespokeFont.inter(15, weight: .semibold))
                .foregroundStyle(titleColor)
                .multilineTextAlignment(.leading)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            Text(subtitle)
                .font(BespokeFont.inter(12, weight: .medium))
                .foregroundStyle(subtitleColor)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct HeartsDuaCardBody<Icon: View>: View {
    @ViewBuilder let icon: () -> Icon
    let title: String
    let subtitle: String
    var titleColor: Color = .white
    var subtitleColor: Color = Color.white.opacity(0.82)

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            icon()

            Spacer(minLength: 0)

            HeartsDuaCardTextBlock(
                title: title,
                subtitle: subtitle,
                titleColor: titleColor,
                subtitleColor: subtitleColor
            )
        }
        .padding(.horizontal, HeartsDuaCardLayout.contentPadding)
        .padding(.top, HeartsDuaCardLayout.contentPadding)
        .padding(.bottom, HeartsDuaCardLayout.textBottomInset)
    }
}

private enum HeartsDuaCardPalette {
    /// Primary library card — deep emerald, aligned with the app header.
    static let savedAll: [Color] = [
        Color(red: 15 / 255, green: 74 / 255, blue: 56 / 255),
        Color(red: 20 / 255, green: 92 / 255, blue: 69 / 255),
        Color(red: 10 / 255, green: 51 / 255, blue: 40 / 255)
    ]

    /// Secondary accent colours for user-created collections.
    static let collectionPalettes: [[Color]] = [
        [Color(red: 154 / 255, green: 115 / 255, blue: 64 / 255), Color(red: 115 / 255, green: 83 / 255, blue: 46 / 255)],
        [Color(red: 92 / 255, green: 58 / 255, blue: 102 / 255), Color(red: 62 / 255, green: 36 / 255, blue: 72 / 255)],
        [Color(red: 74 / 255, green: 98 / 255, blue: 120 / 255), Color(red: 46 / 255, green: 66 / 255, blue: 84 / 255)],
        [Color(red: 160 / 255, green: 90 / 255, blue: 66 / 255), Color(red: 116 / 255, green: 64 / 255, blue: 48 / 255)]
    ]

    static func collectionColors(at index: Int) -> [Color] {
        collectionPalettes[index % collectionPalettes.count]
    }
}

private struct HeartsDuaSquareCardFrame<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        HeartsDuaCardFrame(style: .square, content: content)
    }
}

private struct HeartsDuaHeroCardFrame<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        HeartsDuaCardFrame(style: .hero, content: content)
    }
}

private struct HeartsDuaActionCard: View {
    let title: String
    let subtitle: String
    let symbolName: String
    let accentColors: [Color]

    var body: some View {
        HeartsDuaHeroCardFrame {
            ZStack(alignment: .topLeading) {
                HeartsDuaCardBackdrop(
                    accentColors: accentColors,
                    watermarkSymbol: "bookmark.fill",
                    showsRadialGlow: true
                )

                HeartsDuaCardBody(
                    icon: {
                        HeartsDuaCardIconBadge(symbolName: symbolName)
                    },
                    title: title,
                    subtitle: subtitle
                )
            }
            .overlay {
                RoundedRectangle(cornerRadius: HeartsDuaCardLayout.cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            }
            .shadow(color: BespokeColor.forest.opacity(0.22), radius: 14, x: 0, y: 8)
        }
    }
}

private struct MakeCollectionCard: View {
    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(BespokeColor.forest.opacity(0.10))
                    .frame(width: 40, height: 40)
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(BespokeColor.forest)
            }
            .fixedSize()

            VStack(alignment: .leading, spacing: 4) {
                Text("Create collection")
                    .font(BespokeFont.inter(15, weight: .semibold))
                    .foregroundStyle(BespokeColor.forest)
                    .lineLimit(1)

                Text("Group saved duas together")
                    .font(BespokeFont.inter(13, weight: .regular))
                    .foregroundStyle(BespokeColor.muted)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .layoutPriority(1)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(BespokeColor.muted.opacity(0.55))
                .fixedSize()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BespokeColor.forest.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(
                    BespokeColor.forest.opacity(0.22),
                    style: StrokeStyle(lineWidth: 1.5, dash: [7, 5])
                )
        }
        .bespokeButtonHitArea(cornerRadius: 16)
    }
}

private struct HeartsDuaCollectionCard: View {
    let collection: DuaCollectionSummaryDTO
    let paletteIndex: Int
    let symbolName: String

    private var accentColors: [Color] {
        HeartsDuaCardPalette.collectionColors(at: paletteIndex)
    }

    private var subtitle: String {
        switch collection.duaCount {
        case 0:
            return "No duas yet"
        case 1:
            return "1 dua"
        default:
            return "\(collection.duaCount) duas"
        }
    }

    var body: some View {
        HeartsDuaSquareCardFrame {
            ZStack(alignment: .topLeading) {
                HeartsDuaCardBackdrop(accentColors: accentColors)

                HeartsDuaCardBody(
                    icon: {
                        HeartsDuaCardIconBadge(symbolName: symbolName)
                    },
                    title: collection.name,
                    subtitle: subtitle
                )
            }
            .overlay {
                RoundedRectangle(cornerRadius: HeartsDuaCardLayout.cornerRadius, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            }
            .shadow(color: accentColors.first?.opacity(0.28) ?? .black.opacity(0.12), radius: 14, x: 0, y: 8)
        }
    }
}

private struct HeartsDuaCardIconBadge: View {
    let symbolName: String

    var body: some View {
        Image(systemName: symbolName)
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 40, height: 40)
            .background(Color.white.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct HeartsDuaCardBackdrop: View {
    let accentColors: [Color]
    var watermarkSymbol: String?
    var showsRadialGlow: Bool = false

    private var baseGradient: LinearGradient {
        if accentColors.count >= 3 {
            LinearGradient(
                stops: [
                    .init(color: accentColors[0], location: 0),
                    .init(color: accentColors[1], location: 0.55),
                    .init(color: accentColors[2], location: 1)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        } else {
            LinearGradient(
                colors: accentColors,
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        }
    }

    var body: some View {
        ZStack {
            baseGradient

            if showsRadialGlow {
                RadialGradient(
                    colors: [Color.white.opacity(0.12), Color.clear],
                    center: .topTrailing,
                    startRadius: 8,
                    endRadius: 220
                )
            }

            LinearGradient(
                colors: [Color.white.opacity(0.14), Color.clear],
                startPoint: .topLeading,
                endPoint: .center
            )

            if let watermarkSymbol {
                Image(systemName: watermarkSymbol)
                    .font(.system(size: 96, weight: .regular))
                    .foregroundStyle(Color.white.opacity(0.08))
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                    .offset(x: 18, y: 14)
            }
        }
    }
}

private struct SavedDuaCardView: View {
    let row: SavedDuaDTO
    let userId: Int?
    let isSavedVisual: Bool
    let onSave: () -> Void
    var onEdit: (() -> Void)? = nil
    var isSelectionMode: Bool = false
    var isSelected: Bool = false
    var onLongPress: (() -> Void)? = nil
    var onToggleSelection: (() -> Void)? = nil

    private var showsActions: Bool {
        !isSelectionMode
    }

    var body: some View {
        cardContent
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay {
                if isSelectionMode, isSelected {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(BespokeColor.forest, lineWidth: 1.5)
                }
            }
            .overlay(alignment: .topTrailing) {
                if isSelectionMode {
                    selectionIndicator
                        .offset(x: 10, y: -10)
                }
            }
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .onLongPressGesture(minimumDuration: 0.45) {
                onLongPress?()
            }
            .onTapGesture {
                if isSelectionMode {
                    onToggleSelection?()
                }
            }
    }

    @ViewBuilder
    private var cardContent: some View {
        if SavedDuaDisplay.kind(from: row) == .sunnah,
           let payload = SunnahDuaDisplay.savedPayload(from: row) {
            SunnahDuaCard(
                item: SunnahDuaDisplay.item(from: payload),
                isSavedVisual: isSavedVisual,
                showsActions: showsActions,
                reservesActionBarSpace: isSelectionMode,
                onSave: onSave
            )
        } else {
            BespokeDuaCard(
                dua: SavedDuaDisplay.duaReceiver(from: row, userId: userId),
                isSavedVisual: isSavedVisual,
                onSave: onSave,
                showsActions: showsActions,
                reservesActionBarSpace: isSelectionMode,
                showsEditMenu: onEdit != nil && showsActions,
                onEdit: onEdit
            )
        }
    }

    private var selectionIndicator: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 26, weight: .regular))
            .symbolRenderingMode(.monochrome)
            .foregroundStyle(isSelected ? BespokeColor.forest : BespokeColor.muted.opacity(0.45))
            .background {
                Circle()
                    .fill(Color.white)
                    .padding(2)
            }
            .shadow(color: .black.opacity(0.08), radius: 3, x: 0, y: 1)
    }
}

struct SavedDuaSelectionRow: View {
    enum Style {
        case compact
        case collectionPicker
    }

    let row: SavedDuaDTO
    let userId: Int?
    let isSelected: Bool
    var style: Style = .compact
    let onToggle: () -> Void

    private var isSunnah: Bool {
        SavedDuaDisplay.kind(from: row) == .sunnah
    }

    var body: some View {
        switch style {
        case .compact:
            compactRow
        case .collectionPicker where isSunnah:
            sunnahPickerCard
        case .collectionPicker:
            bespokePickerRow
        }
    }

    private var sunnahPickerCard: some View {
        Button(action: onToggle) {
            ZStack(alignment: .topTrailing) {
                if let payload = SunnahDuaDisplay.savedPayload(from: row) {
                    SunnahDuaCard(
                        item: SunnahDuaDisplay.item(from: payload),
                        isSavedVisual: true,
                        showsActions: false,
                        onSave: {}
                    )
                }

                selectionIndicator
                    .padding(12)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(isSelected ? BespokeColor.forest.opacity(0.35) : Color.clear, lineWidth: 2)
            }
            .bespokeButtonHitArea(cornerRadius: 18)
        }
        .buttonStyle(BespokePlainButtonStyle())
    }

    private var bespokePickerRow: some View {
        Button(action: onToggle) {
            HStack(alignment: .top, spacing: 12) {
                selectionIndicator
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 6) {
                    Text(bespokeDisplayText)
                        .font(BespokeFont.inter(15, weight: .regular))
                        .foregroundStyle(BespokeColor.bodyText)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    if !isSelected {
                        Text(SavedDuaDisplay.dateFormatter.string(from: row.createdAt))
                            .font(BespokeFont.inter(12, weight: .medium))
                            .foregroundStyle(BespokeColor.muted)
                    }
                }

                Spacer(minLength: 0)
            }
            .padding(14)
            .background(isSelected ? BespokeColor.cream : Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? BespokeColor.forest.opacity(0.22) : BespokeColor.cardBorder, lineWidth: 1)
            }
            .bespokeButtonHitArea(cornerRadius: 14)
        }
        .buttonStyle(BespokePlainButtonStyle())
    }

    private var compactRow: some View {
        Button(action: onToggle) {
            HStack(alignment: .top, spacing: 12) {
                selectionIndicator
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 6) {
                    Text(SavedDuaDisplay.previewText(from: row, userId: userId))
                        .font(BespokeFont.inter(15, weight: .regular))
                        .foregroundStyle(BespokeColor.bodyText)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(SavedDuaDisplay.dateFormatter.string(from: row.createdAt))
                        .font(BespokeFont.inter(12, weight: .medium))
                        .foregroundStyle(BespokeColor.muted)
                }

                Spacer(minLength: 0)
            }
            .padding(14)
            .background(isSelected ? BespokeColor.cream : Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(isSelected ? BespokeColor.forest.opacity(0.22) : BespokeColor.cardBorder, lineWidth: 1)
            }
            .bespokeButtonHitArea(cornerRadius: 14)
        }
        .buttonStyle(BespokePlainButtonStyle())
    }

    private var selectionIndicator: some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 22))
            .foregroundStyle(isSelected ? BespokeColor.forest : BespokeColor.muted.opacity(0.55))
    }

    private var bespokeDisplayText: String {
        if isSelected {
            return SavedDuaDisplay.duaReceiver(from: row, userId: userId).duaText
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return SavedDuaDisplay.previewText(from: row, userId: userId)
    }
}

private struct HeartsDuaCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
            .opacity(configuration.isPressed ? 0.94 : 1)
            .animation(.spring(response: 0.28, dampingFraction: 0.74), value: configuration.isPressed)
    }
}

#Preview {
    NavigationStack {
        HeartsDuaHubView()
            .environment(AppSession())
    }
}
