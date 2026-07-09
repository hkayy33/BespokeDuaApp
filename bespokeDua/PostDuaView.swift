import SwiftUI

struct PostDuaView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.mainTabBarClearance) private var mainTabBarClearance
    @Environment(AppSession.self) private var session

    var onPost: (DuaFeedPost) -> Void
    var onDelete: ((UUID) -> Void)?
    var opensPickerDirectly: Bool = false

    @State private var selectedDuaId: String?
    @State private var selectedSource: PostDuaSource = .allSaved
    @State private var activeCollectionDuaIds: Set<String> = []
    @State private var isLoadingSource = false
    @State private var livePosts: [DuaFeedPost] = []
    @State private var showsPicker = false
    @State private var isLoading = true
    @State private var isSubmitting = false
    @State private var deletingPostIDs: Set<UUID> = []
    @State private var postPendingDelete: DuaFeedPost?
    @State private var deleteError: String?
    @State private var actionError: String?
    @State private var quotaRefresh = 0

    private var bespokeSavedDuas: [SavedDuaDTO] {
        session.savedDuas.filter { SavedDuaDisplay.kind(from: $0) == .bespoke }
    }

    private var hasBespokeSavedDuas: Bool {
        !bespokeSavedDuas.isEmpty
    }

    private var selectedRow: SavedDuaDTO? {
        guard let selectedDuaId else { return nil }
        return bespokeSavedDuas.first { $0.duaId == selectedDuaId }
    }

    private var sortedSavedDuas: [SavedDuaDTO] {
        sourceSavedDuas.sorted { $0.createdAt > $1.createdAt }
    }

    private var sourceSavedDuas: [SavedDuaDTO] {
        switch selectedSource {
        case .allSaved:
            return bespokeSavedDuas
        case .collection:
            return bespokeSavedDuas.filter { activeCollectionDuaIds.contains($0.duaId) }
        }
    }

    private var postedSavedDuaIds: Set<String> {
        let postedBodies = Set(
            livePosts.map {
                $0.body.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        )
        guard !postedBodies.isEmpty else { return [] }

        var ids = Set<String>()
        for row in bespokeSavedDuas {
            let text = SavedDuaDisplay.duaReceiver(from: row, userId: userId)
                .duaText
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if postedBodies.contains(text) {
                ids.insert(row.duaId)
            }
        }
        return ids
    }

    private var sortedCollections: [DuaCollectionSummaryDTO] {
        session.duaCollections.sorted { $0.updatedAt > $1.updatedAt }
    }

    private var sourceTitle: String {
        switch selectedSource {
        case .allSaved:
            return "All saved duas"
        case let .collection(collectionId):
            return sortedCollections.first { $0.collectionId == collectionId }?.name ?? "Collection"
        }
    }

    private var sourceIcon: String {
        switch selectedSource {
        case .allSaved:
            return "bookmark.fill"
        case .collection:
            return CollectionIconCache.symbol(
                userId: userId,
                collectionId: selectedSource.collectionId ?? ""
            )
        }
    }

    private var userId: Int? {
        session.currentUser?.userId
    }

    private var postsRemainingToday: Int {
        guard let userId else { return 0 }
        return DuaFeedPostingQuota.postsRemainingToday(userId: userId)
    }

    private var hasLivePost: Bool {
        !livePosts.isEmpty
    }

    var body: some View {
        Group {
            if isLoading {
                loadingView
            } else if showsPicker || opensPickerDirectly {
                if !hasBespokeSavedDuas {
                    noSavedDuasView
                } else if !canPostToday {
                    dailyLimitReachedView
                } else {
                    pickerView
                }
            } else if hasLivePost {
                livePostsView
            } else if !hasBespokeSavedDuas {
                noSavedDuasView
            } else if !canPostToday {
                dailyLimitReachedView
            } else {
                pickerView
            }
        }
        .background(BespokeColor.pageBackground)
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .bespokeStyledNavigationBar(showsMainBar: false)
        .bespokeEdgeBackNavigation(hidesNavigationBar: true)
        .task {
            session.scheduleSavedDuasRefresh()
            session.scheduleDuaCollectionsRefresh()
            await loadInitialState()
        }
        .task(id: selectedSource) {
            await loadSelectedSource()
        }
        .overlay {
            if let post = postPendingDelete {
                BespokeConfirmModal(
                    title: "Delete post?",
                    message: "This removes your dua from the feed. You can share it again later.",
                    confirmTitle: "Delete",
                    inFlight: deletingPostIDs.contains(post.id),
                    errorMessage: deleteError,
                    onCancel: {
                        deleteError = nil
                        postPendingDelete = nil
                    },
                    onConfirm: { Task { await deletePost(post) } }
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.28), value: postPendingDelete != nil)
    }

    // MARK: - Loading

    private var loadingView: some View {
        VStack(spacing: 16) {
            backButton
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, BespokeLayout.libraryHorizontalPadding)
                .padding(.top, 8)

            Spacer()

            ProgressView()
                .tint(BespokeColor.forest)
                .scaleEffect(1.1)

            Text("Checking your posts…")
                .font(BespokeFont.inter(15, weight: .medium))
                .foregroundStyle(BespokeColor.muted)

            Spacer()
        }
    }

    // MARK: - Live posts

    private var livePostsView: some View {
        ScrollView {
            VStack(spacing: 0) {
                screenHeader(
                    title: livePosts.count == 1 ? "Your live post" : "Your live posts",
                    subtitle: livePostsSubtitle
                )

                LazyVStack(spacing: 12) {
                    ForEach(livePosts) { post in
                        livePostCard(post)
                    }
                }
                .padding(.horizontal, BespokeLayout.libraryHorizontalPadding)
                .padding(.top, 24)

                if let actionError {
                    errorText(actionError)
                        .padding(.top, 12)
                }

                if canPostToday && hasBespokeSavedDuas {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            showsPicker = true
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(.system(size: 13, weight: .bold))
                            Text("Post another dua")
                                .font(BespokeFont.inter(15, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(LinearGradient.bespokeGold)
                        .clipShape(Capsule())
                        .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
                    }
                    .buttonStyle(BespokePlainButtonStyle())
                    .padding(.horizontal, BespokeLayout.libraryHorizontalPadding)
                    .padding(.top, 20)
                }

                Button {
                    dismiss()
                } label: {
                    Text("Back to feed")
                        .font(BespokeFont.inter(16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(BespokeColor.forest)
                        .clipShape(Capsule())
                }
                .buttonStyle(BespokePlainButtonStyle())
                .padding(.horizontal, BespokeLayout.libraryHorizontalPadding)
                .padding(.top, 28)

                postingRulesFootnote
                    .padding(.horizontal, BespokeLayout.libraryHorizontalPadding)
                    .padding(.top, 20)
                    .padding(.bottom, 24 + mainTabBarClearance)
            }
            .bespokeLibraryContentFrame()
        }
        .scrollIndicators(.hidden, axes: .vertical)
    }

    private var livePostsSubtitle: String {
        _ = quotaRefresh
        guard let userId else { return "Live for 24 hours each." }
        let remaining = DuaFeedPostingQuota.postsRemainingToday(userId: userId)
        if remaining == 0 {
            return "Live for 24 hours each · All \(DuaFeedPostingQuota.dailyLimit) posts used today (UTC)."
        }
        return "Live for 24 hours each · \(remaining) of \(DuaFeedPostingQuota.dailyLimit) posts left today."
    }

    private func livePostCard(_ post: DuaFeedPost) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                Label("Live on feed", systemImage: "dot.radiowaves.left.and.right")
                    .font(BespokeFont.inter(12, weight: .semibold))
                    .foregroundStyle(BespokeColor.forest)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(BespokeColor.feedSurface)
                    .clipShape(Capsule())

                Spacer()

                if let remaining = post.timeRemainingText {
                    Text(remaining)
                        .font(BespokeFont.inter(12, weight: .semibold))
                        .foregroundStyle(BespokeColor.muted)
                }

                Menu {
                    Button(role: .destructive) {
                        deleteError = nil
                        postPendingDelete = post
                    } label: {
                        Label("Delete post", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(BespokeColor.subtle)
                        .frame(width: 32, height: 32)
                }
                .disabled(deletingPostIDs.contains(post.id))
            }

            Text(post.body)
                .font(BespokeFont.inter(15, weight: .regular))
                .foregroundStyle(BespokeColor.bodyText)
                .lineSpacing(5)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 6) {
                Text("🤲")
                    .font(.system(size: 13))

                Text("\(post.duaCount) made dua")
                    .font(BespokeFont.inter(13, weight: .medium))
                    .foregroundStyle(BespokeColor.muted)
            }
        }
        .padding(16)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(BespokeColor.cardBorder, lineWidth: 1)
        }
    }

    // MARK: - Daily limit

    private var canPostToday: Bool {
        guard let userId else { return false }
        return DuaFeedPostingQuota.canPostToday(userId: userId)
    }

    private var dailyLimitReachedView: some View {
        VStack(spacing: 0) {
            screenHeader(
                title: "Daily limit reached",
                subtitle: "You've shared \(DuaFeedPostingQuota.dailyLimit) duas today (UTC). You can post again tomorrow."
            )

            Spacer()

            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 36, weight: .regular))
                .foregroundStyle(BespokeColor.tabBarInactive)

            Spacer()

            Button(action: dismiss.callAsFunction) {
                Text("Back to feed")
                    .font(BespokeFont.inter(16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(BespokeColor.forest)
                    .clipShape(Capsule())
            }
            .buttonStyle(BespokePlainButtonStyle())
            .padding(.horizontal, BespokeLayout.libraryHorizontalPadding)
            .padding(.bottom, 24 + mainTabBarClearance)
        }
    }

    // MARK: - No saved duas

    private var noSavedDuasView: some View {
        VStack(spacing: 0) {
            screenHeader(
                title: "Post a dua",
                subtitle: "Save a bespoke dua first, then share it here for others to make dua for you."
            )

            Spacer()

            VStack(spacing: 12) {
                Image(systemName: "bookmark")
                    .font(.system(size: 36, weight: .regular))
                    .foregroundStyle(BespokeColor.tabBarInactive)

                Text("No bespoke duas saved yet")
                    .font(BespokeFont.inter(18, weight: .semibold))
                    .foregroundStyle(BespokeColor.forest)

                Text("Create or save a bespoke dua from Home, then come back to share it.")
                    .font(BespokeFont.inter(14, weight: .regular))
                    .foregroundStyle(BespokeColor.muted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
            }

            Spacer()

            Button(action: dismiss.callAsFunction) {
                Text("Go back")
                    .font(BespokeFont.inter(16, weight: .semibold))
                    .foregroundStyle(BespokeColor.forest)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(Color.white)
                    .clipShape(Capsule())
                    .overlay {
                        Capsule()
                            .stroke(BespokeColor.cardBorder, lineWidth: 1)
                    }
            }
            .buttonStyle(BespokePlainButtonStyle())
            .padding(.horizontal, BespokeLayout.libraryHorizontalPadding)
            .padding(.bottom, 24 + mainTabBarClearance)
        }
    }

    // MARK: - Picker

    private var pickerView: some View {
        VStack(spacing: 0) {
            pickerStickyHeader

            ScrollView {
                VStack(spacing: 0) {
                    if let error = session.savedDuasError, !hasBespokeSavedDuas {
                        errorText(error)
                            .padding(.top, 16)
                    }

                    sourceMenu
                        .padding(.horizontal, BespokeLayout.libraryHorizontalPadding)
                        .padding(.top, 16)

                    if isLoadingSource {
                        ProgressView()
                            .tint(BespokeColor.forest)
                            .padding(.top, 28)
                    } else if sortedSavedDuas.isEmpty {
                        sourceEmptyState
                            .padding(.top, 28)
                    } else {
                        LazyVStack(spacing: 10) {
                            ForEach(sortedSavedDuas) { row in
                                PostDuaPickerRow(
                                    row: row,
                                    userId: session.currentUser?.userId,
                                    isSelected: selectedDuaId == row.duaId,
                                    isAlreadyPosted: postedSavedDuaIds.contains(row.duaId)
                                ) {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        selectedDuaId = row.duaId
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, BespokeLayout.libraryHorizontalPadding)
                        .padding(.top, 16)
                    }

                    postingRulesFootnote
                        .padding(.horizontal, BespokeLayout.libraryHorizontalPadding)
                        .padding(.top, 20)
                        .padding(.bottom, 24)
                }
                .bespokeLibraryContentFrame()
            }
            .scrollIndicators(.hidden, axes: .vertical)
        }
        .background(BespokeColor.pageBackground)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            pickerFooter
        }
    }

    private var pickerStickyHeader: some View {
        VStack(spacing: 0) {
            screenHeader(
                title: "Post a dua",
                subtitle: pickerSubtitle
            )
        }
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background(BespokeColor.pageBackground)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(BespokeColor.sectionRule)
                .frame(height: 1)
        }
    }

    private var sourceMenu: some View {
        Menu {
            Button {
                selectSource(.allSaved)
            } label: {
                Label("All saved duas", systemImage: "bookmark.fill")
            }

            if !sortedCollections.isEmpty {
                Section("Collections") {
                    ForEach(sortedCollections) { collection in
                        Button {
                            selectSource(.collection(collection.collectionId))
                        } label: {
                            Label(
                                collection.name,
                                systemImage: CollectionIconCache.symbol(
                                    userId: userId,
                                    collectionId: collection.collectionId
                                )
                            )
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: sourceIcon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(BespokeColor.forest)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 2) {
                    Text("From")
                        .font(BespokeFont.inter(11, weight: .medium))
                        .foregroundStyle(BespokeColor.muted)

                    Text(sourceTitle)
                        .font(BespokeFont.inter(15, weight: .semibold))
                        .foregroundStyle(BespokeColor.bodyText)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                Image(systemName: "chevron.down")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(BespokeColor.muted)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(BespokeColor.cardBorder, lineWidth: 1)
            }
        }
        .buttonStyle(BespokePlainButtonStyle())
    }

    private var sourceEmptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "tray")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(BespokeColor.tabBarInactive)

            Text(selectedSource == .allSaved ? "No bespoke duas saved" : "No bespoke duas in this collection")
                .font(BespokeFont.inter(16, weight: .semibold))
                .foregroundStyle(BespokeColor.forest)
                .multilineTextAlignment(.center)

            Text("Choose another source or save a bespoke dua first.")
                .font(BespokeFont.inter(14, weight: .regular))
                .foregroundStyle(BespokeColor.muted)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 24)
    }

    private func selectSource(_ source: PostDuaSource) {
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedSource = source
            selectedDuaId = nil
        }
    }

    private func loadSelectedSource() async {
        guard case let .collection(collectionId) = selectedSource else {
            activeCollectionDuaIds = []
            return
        }

        isLoadingSource = true
        defer { isLoadingSource = false }

        guard let detail = try? await session.api().duaCollection(id: collectionId) else {
            activeCollectionDuaIds = []
            return
        }

        activeCollectionDuaIds = Set(
            detail.savedDuas
                .filter { SavedDuaDisplay.kind(from: $0) == .bespoke }
                .map(\.duaId)
        )

        if let selectedDuaId, !activeCollectionDuaIds.contains(selectedDuaId) {
            self.selectedDuaId = nil
        }
    }

    private var pickerSubtitle: String {
        guard let userId else {
            return "Pick a bespoke saved dua to share anonymously for 24 hours."
        }
        let remaining = DuaFeedPostingQuota.postsRemainingToday(userId: userId)
        if remaining == DuaFeedPostingQuota.dailyLimit {
            return "Pick a bespoke saved dua · up to \(DuaFeedPostingQuota.dailyLimit) posts today."
        }
        return "Pick a bespoke saved dua · \(remaining) of \(DuaFeedPostingQuota.dailyLimit) posts left today."
    }

    private var postingRulesFootnote: some View {
        Text("Up to \(DuaFeedPostingQuota.dailyLimit) posts per UTC day · anonymous · moderated · expire after 7 days")
            .font(BespokeFont.inter(12, weight: .regular))
            .foregroundStyle(BespokeColor.subtle)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }

    private var pickerFooter: some View {
        VStack(spacing: 10) {
            if let actionError {
                errorText(actionError)
            }

            Button {
                Task { await submitPost() }
            } label: {
                HStack(spacing: 8) {
                    if isSubmitting {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .bold))
                    }

                    Text(selectedRow == nil ? "Select a dua above" : "Post anonymously")
                        .font(BespokeFont.inter(16, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(LinearGradient.bespokeGold)
                .clipShape(Capsule())
                .opacity(canSubmit ? 1 : 0.55)
            }
            .buttonStyle(BespokePlainButtonStyle())
            .disabled(!canSubmit || isSubmitting)
        }
        .padding(.horizontal, BespokeLayout.libraryHorizontalPadding)
        .padding(.top, 10)
        .padding(.bottom, max(6, mainTabBarClearance - 20))
        .background {
            BespokeColor.pageBackground
                .ignoresSafeArea(edges: .bottom)
        }
    }

    // MARK: - Shared chrome

    private var backButton: some View {
        Button {
            dismiss()
        } label: {
            Image(systemName: "chevron.left")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(BespokeColor.forest)
                .padding(8)
                .contentShape(Rectangle())
        }
        .buttonStyle(BespokePlainButtonStyle())
        .accessibilityLabel("Back")
    }

    private func screenHeader(title: String, subtitle: String) -> some View {
        VStack(spacing: 0) {
            HStack {
                backButton
                Spacer()
            }
            .padding(.horizontal, BespokeLayout.libraryHorizontalPadding)
            .padding(.top, 8)

            Text(title)
                .font(BespokeFont.display(26))
                .foregroundStyle(BespokeColor.forest)
                .padding(.top, 4)

            Text(subtitle)
                .font(BespokeFont.inter(14, weight: .regular))
                .foregroundStyle(BespokeColor.muted)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
                .padding(.horizontal, BespokeLayout.libraryHorizontalPadding + 8)
        }
    }

    private func errorText(_ message: String) -> some View {
        Text(message)
            .font(BespokeFont.inter(13, weight: .regular))
            .foregroundStyle(BespokeColor.error)
            .multilineTextAlignment(.center)
            .padding(.horizontal, BespokeLayout.libraryHorizontalPadding)
    }

    // MARK: - Actions

    private var canSubmit: Bool {
        guard let selectedDuaId,
              canPostToday,
              session.currentUser != nil,
              !postedSavedDuaIds.contains(selectedDuaId) else { return false }
        return selectedRow != nil
    }

    private func loadInitialState() async {
        isLoading = true
        defer { isLoading = false }

        guard let userId else { return }

        while session.savedDuasLoading && session.savedDuas.isEmpty {
            try? await Task.sleep(for: .milliseconds(100))
            if Task.isCancelled { return }
        }

        livePosts = await session.api().userActiveFeedPosts(userId: userId)
        quotaRefresh += 1

        if let selectedDuaId, postedSavedDuaIds.contains(selectedDuaId) {
            self.selectedDuaId = nil
        }
    }

    private func submitPost() async {
        guard canSubmit,
              let userId,
              let savedDuaId = selectedRow?.duaId else { return }

        isSubmitting = true
        actionError = nil
        defer { isSubmitting = false }

        do {
            let dto = try await session.api().createDuaFeedPost(
                userId: userId,
                savedDuaId: savedDuaId,
                isAnonymous: true
            )
            guard let post = dto.asFeedPost() else {
                actionError = "Could not read the new post."
                return
            }
            await session.api().syncDuaFeedPostingQuota(userId: userId)
            quotaRefresh += 1
            var ownPost = post
            ownPost.isOwnPost = true
            onPost(ownPost)
            dismiss()
        } catch let error as BespokeAPIError {
            if case let .status(code, message) = error, code == 409 {
                DuaFeedPostingQuota.markDailyLimitReached(userId: userId)
                actionError = message ?? "You can only post \(DuaFeedPostingQuota.dailyLimit) times per day."
            } else {
                actionError = error.errorDescription
            }
        } catch {
            actionError = error.localizedDescription
        }
    }

    private func deletePost(_ post: DuaFeedPost) async {
        guard let userId else { return }

        deletingPostIDs.insert(post.id)
        deleteError = nil
        defer { deletingPostIDs.remove(post.id) }

        do {
            try await session.api().deleteDuaFeedPost(
                postId: post.serverPostId,
                userId: userId
            )
            onDelete?(post.id)
            withAnimation {
                livePosts.removeAll { $0.id == post.id }
            }
            await session.api().syncDuaFeedPostingQuota(userId: userId)
            quotaRefresh += 1
            postPendingDelete = nil
        } catch let error as BespokeAPIError {
            deleteError = error.errorDescription
        } catch {
            deleteError = error.localizedDescription
        }
    }
}

// MARK: - Source

private enum PostDuaSource: Hashable {
    case allSaved
    case collection(String)

    var collectionId: String? {
        if case let .collection(id) = self { return id }
        return nil
    }
}

// MARK: - Picker row

private struct PostDuaPickerRow: View {
    let row: SavedDuaDTO
    let userId: Int?
    let isSelected: Bool
    let isAlreadyPosted: Bool
    let onSelect: () -> Void

    private var kind: SavedDuaKind {
        SavedDuaDisplay.kind(from: row)
    }

    private var duaText: String {
        SavedDuaDisplay.duaReceiver(from: row, userId: userId).duaText
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var displayText: String {
        if isSelected { return duaText }
        return SavedDuaDisplay.previewText(from: row, userId: userId)
    }

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isAlreadyPosted ? "checkmark.circle" : (isSelected ? "checkmark.circle.fill" : "circle"))
                    .font(.system(size: 22))
                    .foregroundStyle(
                        isAlreadyPosted
                            ? BespokeColor.muted.opacity(0.45)
                            : (isSelected ? BespokeColor.forest : BespokeColor.muted.opacity(0.55))
                    )
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 6) {
                        Image(systemName: kind.iconName)
                            .font(.system(size: 11, weight: .semibold))
                        Text(kind == .sunnah ? "Sunnah" : "Bespoke")
                            .font(BespokeFont.inter(11, weight: .semibold))

                        if isAlreadyPosted {
                            Text("Posted")
                                .font(BespokeFont.inter(11, weight: .semibold))
                                .foregroundStyle(BespokeColor.muted)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(BespokeColor.muted.opacity(0.12))
                                .clipShape(Capsule())
                        }
                    }
                    .foregroundStyle(isAlreadyPosted ? BespokeColor.muted : BespokeColor.forest)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(isAlreadyPosted ? BespokeColor.muted.opacity(0.08) : BespokeColor.feedSurface)
                    .clipShape(Capsule())

                    Text(displayText)
                        .font(BespokeFont.inter(15, weight: .regular))
                        .foregroundStyle(isAlreadyPosted ? BespokeColor.muted : BespokeColor.bodyText)
                        .multilineTextAlignment(.leading)
                        .lineSpacing(isSelected ? 5 : 0)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(14)
            .background(isAlreadyPosted ? Color.white.opacity(0.72) : (isSelected ? BespokeColor.cream : Color.white))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(
                        isAlreadyPosted
                            ? BespokeColor.cardBorder.opacity(0.7)
                            : (isSelected ? BespokeColor.forest.opacity(0.22) : BespokeColor.cardBorder),
                        lineWidth: 1
                    )
            }
            .bespokeButtonHitArea(cornerRadius: 14)
        }
        .buttonStyle(BespokePlainButtonStyle())
        .disabled(isAlreadyPosted)
    }
}

#Preview {
    NavigationStack {
        PostDuaView { _ in }
    }
    .environment(AppSession())
}
