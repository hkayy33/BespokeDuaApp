import SwiftUI

struct DuaFeedView: View {
    @Binding var navigationPath: NavigationPath
    var isTabActive: Bool = true

    @Environment(AppSession.self) private var session
    @Environment(SubscriptionManager.self) private var subscriptionManager
    @Environment(\.mainTabBarClearance) private var mainTabBarClearance
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.selectMainTab) private var selectMainTab
    @Environment(\.presentUpgradeModal) private var presentUpgradeModal
    @State private var selectedFilter: DuaFeedFilter = .recent
    @State private var togglingPostIDs: Set<UUID> = []
    @State private var deletingPostIDs: Set<UUID> = []
    @State private var postPendingDelete: DuaFeedPost?
    @State private var deleteInFlight = false
    @State private var deleteError: String?
    @State private var quotaRefresh = 0

    private var posts: [DuaFeedPost] { session.duaFeedPosts }
    private var userActivePosts: [DuaFeedPost] { session.duaFeedUserActivePosts }
    private var isLoading: Bool { session.duaFeedIsLoading }
    private var loadError: String? { session.duaFeedLoadError }
    private var hasMore: Bool { session.duaFeedHasMore }

    init(navigationPath: Binding<NavigationPath> = .constant(NavigationPath()), isTabActive: Bool = true) {
        _navigationPath = navigationPath
        self.isTabActive = isTabActive
    }

    private var filteredPosts: [DuaFeedPost] {
        let active = posts.filter(\.isActive)
        switch selectedFilter {
        case .recent:
            return active.sorted { $0.createdAt > $1.createdAt }
        case .mostDuas:
            return active.sorted { $0.duaCount > $1.duaCount }
        case .myPosts:
            guard session.isLoggedIn else { return [] }
            return active.filter(\.isOwnPost).sorted { $0.createdAt > $1.createdAt }
        }
    }

    private var canShowPostAction: Bool {
        _ = quotaRefresh
        guard !hasFeedConnectionIssue else { return false }
        guard session.isLoggedIn, hasSavedDuas,
              let userId = session.currentUser?.userId else { return false }
        return DuaFeedPostingQuota.canPostToday(userId: userId)
    }

    private var hasSavedDuas: Bool {
        session.savedDuas.contains { SavedDuaDisplay.kind(from: $0) == .bespoke }
    }

    private var hasFeedConnectionIssue: Bool {
        guard session.isLoggedIn else { return false }
        if session.isReconnecting { return true }
        if loadError != nil, posts.isEmpty { return true }
        if session.savedDuasError != nil, !hasSavedDuas { return true }
        return false
    }

    private var isFeedLocked: Bool {
        !subscriptionManager.isSubscribed
    }

    private var previewPosts: [DuaFeedPost] {
        let active = isFeedLocked && filteredPosts.isEmpty
            ? DuaFeedSampleData.posts
            : filteredPosts
        return active
    }

    private var feedHeroState: FeedHeroState {
        _ = quotaRefresh
        if !session.isLoggedIn { return .signedOut }
        if hasFeedConnectionIssue { return .connectionError }
        if let userId = session.currentUser?.userId,
           !DuaFeedPostingQuota.canPostToday(userId: userId) {
            return .dailyLimitReached
        }
        if !userActivePosts.isEmpty { return .livePost }
        if !hasSavedDuas { return .needsSavedDua }
        return .readyToPost
    }

    var body: some View {
        ZStack {
            feedContent
                .blur(radius: isFeedLocked ? 10 : 0)
                .allowsHitTesting(!isFeedLocked)

            if isFeedLocked {
                DuaFeedPaywallOverlay(
                    onUnlock: { presentUpgradeModal?() },
                    onDismiss: { selectMainTab(.home) }
                )
            }
        }
        .task {
            if session.duaFeedPosts.isEmpty {
                await session.refreshDuaFeed(showLoading: true)
            }
        }
        .refreshable {
            await session.refreshDuaFeed(showLoading: true)
        }
        .onChange(of: isTabActive) { _, active in
            guard active, navigationPath.isEmpty else { return }
            Task { await session.refreshDuaFeed(showLoading: false) }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active, navigationPath.isEmpty else { return }
            Task { await session.refreshDuaFeed(showLoading: false) }
        }
        .onChange(of: navigationPath.count) { oldCount, newCount in
            guard newCount < oldCount, navigationPath.isEmpty else { return }
            Task { await session.refreshDuaFeed(showLoading: false) }
        }
        .navigationDestination(for: DuaFeedRoute.self) { route in
            switch route {
            case .postDua:
                PostDuaView(
                    onPost: { newPost in
                        var post = newPost
                        post.isOwnPost = true
                        session.insertDuaFeedPost(post)
                    },
                    onDelete: { postID in
                        session.removeDuaFeedPost(id: postID)
                    }
                )
            case .pickDuaToPost:
                PostDuaView(
                    onPost: { newPost in
                        var post = newPost
                        post.isOwnPost = true
                        session.insertDuaFeedPost(post)
                    },
                    onDelete: { postID in
                        session.removeDuaFeedPost(id: postID)
                    },
                    opensPickerDirectly: true
                )
            }
        }
        .overlay {
            if let post = postPendingDelete {
                BespokeConfirmModal(
                    title: "Delete post?",
                    message: "This removes your dua from the feed. You can share it again later.",
                    confirmTitle: "Delete",
                    inFlight: deleteInFlight,
                    errorMessage: deleteError,
                    onCancel: {
                        deleteError = nil
                        postPendingDelete = nil
                    },
                    onConfirm: { Task { await confirmDeletePost(post) } }
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.28), value: postPendingDelete != nil)
    }

    private var feedContent: some View {
        BespokeSubpageLayout(
            title: "Dua Feed",
            showsBackButton: false,
            showsMenuButton: false,
            reservesLeadingButtonSpace: true,
            centersTitle: true,
            usesHomeBackground: true,
            trailing: {
                if canShowPostAction {
                    postNavButton
                }
            }
        ) {
            VStack(spacing: 0) {
                feedFixedHeader

                ScrollView {
                    VStack(spacing: 0) {
                        feedList
                            .padding(.horizontal, BespokeLayout.libraryHorizontalPadding)
                            .padding(.top, 14)

                        if let loadError, !isFeedLocked, !hasFeedConnectionIssue {
                            Text(loadError)
                                .font(BespokeFont.inter(13, weight: .regular))
                                .foregroundStyle(BespokeColor.muted)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, BespokeLayout.libraryHorizontalPadding)
                                .padding(.top, 8)
                        }

                        footnote
                            .padding(.horizontal, BespokeLayout.libraryHorizontalPadding)
                            .padding(.top, 20)
                            .padding(.bottom, 24 + mainTabBarClearance)
                    }
                    .bespokeLibraryContentFrame()
                }
                .scrollIndicators(.hidden, axes: .vertical)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private var feedFixedHeader: some View {
        VStack(spacing: 0) {
            heroCard
                .padding(.horizontal, BespokeLayout.libraryHorizontalPadding)
                .padding(.top, heroCardIsEmpty ? 8 : 16)

            feedSectionHeader
                .padding(.horizontal, BespokeLayout.libraryHorizontalPadding)
                .padding(.top, heroCardIsEmpty ? 12 : 14)

            if !userActivePosts.isEmpty {
                livePostsBanner
                    .padding(.horizontal, BespokeLayout.libraryHorizontalPadding)
                    .padding(.top, 12)
            }

            filterChips
                .padding(.top, userActivePosts.isEmpty ? 12 : 10)
                .padding(.bottom, 12)
        }
        .background(LinearGradient.bespokeHomeCanvas)
    }

    private var feedHadithSubtitle: some View {
        VStack(spacing: 6) {
            Text("“There is no believing servant who supplicates for his brother behind his back (in his absence) that the Angels do not say: The same be for you too.”")
                .font(BespokeFont.inter(13, weight: .regular))
                .foregroundStyle(BespokeColor.muted)
                .multilineTextAlignment(.center)
                .lineSpacing(4)
                .fixedSize(horizontal: false, vertical: true)

            Text("Sahih Muslim 2732a")
                .font(BespokeFont.inter(12, weight: .semibold))
                .foregroundStyle(BespokeColor.homeGold)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 6)
        .padding(.bottom, 12)
    }

    private var heroCardIsEmpty: Bool {
        switch feedHeroState {
        case .readyToPost, .livePost, .connectionError:
            true
        case .signedOut, .needsSavedDua, .dailyLimitReached:
            false
        }
    }

    // MARK: - Hero

    private var heroCard: some View {
        Group {
            switch feedHeroState {
            case .signedOut:
                signedOutHero
            case .livePost:
                EmptyView()
            case .needsSavedDua:
                needsSavedDuaHero
            case .dailyLimitReached:
                dailyLimitBanner
            case .readyToPost:
                EmptyView()
            case .connectionError:
                EmptyView()
            }
        }
    }

    private var signedOutHero: some View {
        feedHeroShell(
            icon: "person.crop.circle.badge.plus",
            title: "Join the feed",
            message: "Browse community duas below. Sign in to share one of your saved duas anonymously."
        ) {
            Button {
                session.presentAuth()
            } label: {
                heroPrimaryButtonLabel("Sign in to post")
            }
            .buttonStyle(BespokePlainButtonStyle())
        }
    }

    private var needsSavedDuaHero: some View {
        feedHeroShell(
            icon: "bookmark",
            title: "Save a bespoke dua first",
            message: "You can only share bespoke duas you've saved. Create one on Home, then post it here for 24 hours."
        ) {
            VStack(spacing: 10) {
                Button {
                    selectMainTab(.home)
                } label: {
                    heroPrimaryButtonLabel("Create a dua")
                }
                .buttonStyle(BespokePlainButtonStyle())

                Button {
                    selectMainTab(.saved)
                } label: {
                    Text("View saved duas")
                        .font(BespokeFont.inter(14, weight: .semibold))
                        .foregroundStyle(BespokeColor.forest)
                }
                .buttonStyle(BespokePlainButtonStyle())
            }
        }
    }

    private var dailyLimitBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(BespokeColor.muted)

            Text("You've shared \(DuaFeedPostingQuota.dailyLimit) duas today (UTC). You can post again tomorrow.")
                .font(BespokeFont.inter(13, weight: .regular))
                .foregroundStyle(BespokeColor.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BespokeColor.feedSurface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var livePostsBanner: some View {
        let liveCount = userActivePosts.count
        let totalDuas = userActivePosts.reduce(0) { $0 + $1.duaCount }
        let soonestExpiry = userActivePosts.compactMap(\.timeRemainingText).first

        return HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(liveCount == 1 ? "Your dua is live" : "Your duas are live")
                    .font(BespokeFont.inter(15, weight: .semibold))
                    .foregroundStyle(BespokeColor.forest)

                HStack(spacing: 5) {
                    Text("\(liveCount) \(liveCount == 1 ? "post" : "posts")")
                        .font(BespokeFont.inter(13, weight: .medium))
                        .foregroundStyle(BespokeColor.muted)

                    Text("•")
                        .foregroundStyle(BespokeColor.subtle)

                    Text("🤲")
                        .font(.system(size: 12))

                    Text("\(totalDuas) made dua")
                        .font(BespokeFont.inter(13, weight: .medium))
                        .foregroundStyle(BespokeColor.muted)

                    if liveCount == 1, let soonestExpiry {
                        Text("•")
                            .foregroundStyle(BespokeColor.subtle)

                        Text(soonestExpiry)
                            .font(BespokeFont.inter(13, weight: .medium))
                            .foregroundStyle(BespokeColor.forest.opacity(0.75))
                    }
                }
            }

            Spacer(minLength: 8)

            Button {
                navigationPath.append(DuaFeedRoute.postDua)
            } label: {
                HStack(spacing: 3) {
                    Text("Manage")
                        .font(BespokeFont.inter(12, weight: .semibold))

                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(BespokeColor.forest)
                .clipShape(Capsule())
            }
            .buttonStyle(BespokePlainButtonStyle())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(BespokeColor.feedSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func feedHeroShell<Actions: View>(
        icon: String,
        title: String,
        message: String,
        @ViewBuilder actions: () -> Actions
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .fill(BespokeColor.forest)
                        .frame(width: 44, height: 44)

                    Image(systemName: icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                }

                Text(title)
                    .font(BespokeFont.inter(17, weight: .semibold))
                    .foregroundStyle(BespokeColor.forest)
            }

            Text(message)
                .font(BespokeFont.inter(14, weight: .regular))
                .foregroundStyle(BespokeColor.muted)
                .fixedSize(horizontal: false, vertical: true)

            actions()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BespokeColor.feedSurface)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func heroPrimaryButtonLabel(_ title: String) -> some View {
        Text(title)
            .font(BespokeFont.inter(15, weight: .semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(BespokeColor.forest)
            .clipShape(Capsule())
    }

    // MARK: - Feed section

    private var feedSectionHeader: some View {
        feedHadithSubtitle
    }

    private var postNavButton: some View {
        Button {
            navigationPath.append(DuaFeedRoute.pickDuaToPost)
        } label: {
            HStack(spacing: 4) {
                Text("Post dua")
                    .font(BespokeFont.inter(13, weight: .semibold))

                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(LinearGradient.bespokeGold)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.14), radius: 6, x: 0, y: 2)
        }
        .buttonStyle(BespokePlainButtonStyle())
        .accessibilityLabel("Post a saved dua")
    }

    private var filterChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(DuaFeedFilter.allCases) { filter in
                    filterChip(filter)
                }
            }
            .padding(.horizontal, BespokeLayout.libraryHorizontalPadding)
        }
    }

    private func filterChip(_ filter: DuaFeedFilter) -> some View {
        let isSelected = selectedFilter == filter

        return Button {
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedFilter = filter
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

    // MARK: - Feed list

    private var feedList: some View {
        VStack(spacing: 16) {
            if isLoading && posts.isEmpty && !isFeedLocked && !hasFeedConnectionIssue {
                ProgressView()
                    .padding(.vertical, 48)
            } else if hasFeedConnectionIssue && !isFeedLocked {
                NamesLibraryConnectionComfortView(
                    title: "Having trouble connecting",
                    message: "Check your connection and try again when you're back online.",
                    onRetry: { await session.reconnectAppContent() }
                )
                .padding(.vertical, 8)
            } else if posts.isEmpty && !isFeedLocked {
                emptyFeedState
            } else if filteredPosts.isEmpty && !isFeedLocked {
                filterEmptyState
            } else {
                ForEach(previewPosts) { post in
                    DuaFeedPostCard(
                        post: previewPostBinding(for: post),
                        onMakeDua: { Task { await toggleMakeDua(for: post.id) } },
                        onDelete: post.isOwnPost ? { postPendingDelete = post } : nil
                    )
                }

                if hasMore, !isFeedLocked {
                    Button {
                        Task { await session.loadMoreDuaFeed() }
                    } label: {
                        Group {
                            if isLoading {
                                ProgressView()
                            } else {
                                Text("Load more")
                                    .font(BespokeFont.inter(14, weight: .semibold))
                            }
                        }
                        .foregroundStyle(BespokeColor.forest)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(BespokePlainButtonStyle())
                    .disabled(isLoading)
                }
            }
        }
    }

    private var emptyFeedState: some View {
        VStack(spacing: 14) {
            Image(systemName: "hands.sparkles")
                .font(.system(size: 34, weight: .regular))
                .foregroundStyle(BespokeColor.tabBarInactive)

            Text(emptyFeedTitle)
                .font(BespokeFont.inter(17, weight: .semibold))
                .foregroundStyle(BespokeColor.forest)

            Text(emptyFeedMessage)
                .font(BespokeFont.inter(14, weight: .regular))
                .foregroundStyle(BespokeColor.muted)
                .multilineTextAlignment(.center)

            if let action = emptyFeedAction {
                Button(action: action.handler) {
                    Text(action.title)
                        .font(BespokeFont.inter(14, weight: .semibold))
                        .foregroundStyle(BespokeColor.forest)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 10)
                        .background(Color.white)
                        .clipShape(Capsule())
                        .overlay {
                            Capsule()
                                .stroke(BespokeColor.cardBorder, lineWidth: 1)
                        }
                }
                .buttonStyle(BespokePlainButtonStyle())
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 36)
    }

    private var filterEmptyState: some View {
        VStack(spacing: 8) {
            Text(filterEmptyTitle)
                .font(BespokeFont.inter(15, weight: .semibold))
                .foregroundStyle(BespokeColor.forest)

            if selectedFilter != .myPosts {
                Button {
                    selectedFilter = .recent
                } label: {
                    Text("Show recent")
                        .font(BespokeFont.inter(14, weight: .semibold))
                        .foregroundStyle(BespokeColor.forest)
                }
                .buttonStyle(BespokePlainButtonStyle())
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    private var filterEmptyTitle: String {
        switch selectedFilter {
        case .recent, .mostDuas:
            "No duas in this view"
        case .myPosts:
            session.isLoggedIn ? "You haven't posted yet" : "Sign in to see your posts"
        }
    }

    private var emptyFeedTitle: String {
        switch feedHeroState {
        case .signedOut:
            "No community duas yet"
        case .livePost:
            "You're the only one sharing right now"
        case .needsSavedDua:
            "Nothing on the feed yet"
        case .dailyLimitReached:
            "No community duas yet"
        case .readyToPost:
            "Be the first to share today"
        case .connectionError:
            ""
        }
    }

    private var emptyFeedMessage: String {
        switch feedHeroState {
        case .signedOut:
            "When others share saved duas, they'll appear here for you to make dua."
        case .livePost:
            "Your dua is live in the banner above. Check back as more people join the feed."
        case .needsSavedDua:
            "Save a dua from Home, then share it here when you're ready."
        case .dailyLimitReached:
            "You've used today's posts. Browse duas below and make dua for others."
        case .readyToPost:
            "Tap Post dua above to share a bespoke saved dua anonymously."
        case .connectionError:
            ""
        }
    }

    private var emptyFeedAction: (title: String, handler: () -> Void)? {
        switch feedHeroState {
        case .signedOut:
            return nil
        case .livePost:
            return nil
        case .needsSavedDua:
            return ("Go to Home", { selectMainTab(.home) })
        case .dailyLimitReached:
            return nil
        case .readyToPost:
            return ("Post a saved dua", { navigationPath.append(DuaFeedRoute.pickDuaToPost) })
        case .connectionError:
            return nil
        }
    }

    private var footnote: some View {
        Text("Anonymous · moderated · Up to \(DuaFeedPostingQuota.dailyLimit) posts per UTC day · expire after 7 days")
            .font(BespokeFont.inter(12, weight: .regular))
            .foregroundStyle(BespokeColor.subtle)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }

    // MARK: - Actions

    private func postBinding(for post: DuaFeedPost) -> Binding<DuaFeedPost> {
        session.duaFeedPostBinding(for: post)
    }

    private func previewPostBinding(for post: DuaFeedPost) -> Binding<DuaFeedPost> {
        if isFeedLocked, !posts.contains(where: { $0.id == post.id }) {
            return .constant(post)
        }
        return postBinding(for: post)
    }

    private func toggleMakeDua(for id: UUID) async {
        guard let userId = session.currentUser?.userId else {
            session.presentAuth()
            return
        }
        guard let index = posts.firstIndex(where: { $0.id == id }),
              !posts[index].isOwnPost,
              !togglingPostIDs.contains(id) else { return }

        togglingPostIDs.insert(id)
        defer { togglingPostIDs.remove(id) }

        do {
            _ = try await session.toggleDuaFeedMakeDua(postId: id, userId: userId)
        } catch {
            session.recordDuaFeedError(error)
        }
    }

    private func confirmDeletePost(_ post: DuaFeedPost) async {
        guard let userId = session.currentUser?.userId else { return }

        deleteInFlight = true
        deleteError = nil
        deletingPostIDs.insert(post.id)
        defer {
            deleteInFlight = false
            deletingPostIDs.remove(post.id)
        }

        do {
            try await session.api().deleteDuaFeedPost(
                postId: post.serverPostId,
                userId: userId
            )
            session.removeDuaFeedPost(id: post.id)
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

// MARK: - Hero state

private enum FeedHeroState {
    case signedOut
    case needsSavedDua
    case dailyLimitReached
    case readyToPost
    case livePost
    case connectionError
}

// MARK: - Feed card

private enum DuaFeedPostCardLayout {
    static let cornerRadius: CGFloat = 16
    static let horizontalPadding: CGFloat = 16
    static let verticalPadding: CGFloat = 14
}

private struct DuaFeedPostCard: View {
    @Environment(\.openURL) private var openURL

    @Binding var post: DuaFeedPost
    let onMakeDua: () -> Void
    var onDelete: (() -> Void)? = nil

    private var theme: DuaFeedAvatar.Style {
        DuaFeedAvatar.style(for: post.id)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerSection
                .padding(.bottom, 12)

            bodySection
                .padding(.bottom, 14)

            footerSection
        }
        .padding(.horizontal, DuaFeedPostCardLayout.horizontalPadding)
        .padding(.vertical, DuaFeedPostCardLayout.verticalPadding)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: DuaFeedPostCardLayout.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: DuaFeedPostCardLayout.cornerRadius, style: .continuous)
                .stroke(BespokeColor.cardBorder.opacity(0.8), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.04), radius: 8, x: 0, y: 2)
    }

    private var headerSection: some View {
        HStack(alignment: .top, spacing: 12) {
            DuaFeedAvatarView(postID: post.id, size: 40)

            VStack(alignment: .leading, spacing: 3) {
                Text(post.displayAuthorName)
                    .font(BespokeFont.inter(15, weight: .semibold))
                    .foregroundStyle(theme.accent)

                Text(post.hoursAgoText)
                    .font(BespokeFont.inter(12, weight: .regular))
                    .foregroundStyle(BespokeColor.subtle)
            }

            Spacer(minLength: 4)

            HStack(spacing: 6) {
                duaCountBadge
                postActionsMenu
            }
        }
    }

    private var postActionsMenu: some View {
        Menu {
            if post.isOwnPost {
                Button(role: .destructive) {
                    onDelete?()
                } label: {
                    Label("Delete post", systemImage: "trash")
                }
                .disabled(onDelete == nil)
            } else {
                Button {
                    reportPost()
                } label: {
                    Label("Report post", systemImage: "exclamationmark.bubble")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(BespokeColor.muted)
                .rotationEffect(.degrees(90))
                .frame(width: 28, height: 28)
                .contentShape(Rectangle())
        }
        .accessibilityLabel("Post options")
    }

    private func reportPost() {
        let preview = post.body
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .prefix(280)
        BespokeAppMetadata.openEmail(
            url: BespokeAppMetadata.reportDuaFeedPostMailURL(
                postId: post.serverPostId,
                preview: String(preview)
            ),
            openURL: { openURL($0) }
        )
    }

    private var duaCountBadge: some View {
        HStack(spacing: 4) {
            Text("🤲")
                .font(.system(size: 12))

            Text("\(post.duaCount)")
                .font(BespokeFont.inter(12, weight: .semibold))
                .foregroundStyle(BespokeColor.bodyText)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(theme.background)
        .clipShape(Capsule())
        .accessibilityLabel("\(post.duaCount) made dua")
    }

    private func themeBadge(_ text: String) -> some View {
        Text(text)
            .font(BespokeFont.inter(12, weight: .semibold))
            .foregroundStyle(theme.accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(theme.background)
            .clipShape(Capsule())
    }

    private var bodySection: some View {
        Text(post.body)
            .font(BespokeFont.inter(15, weight: .regular))
            .foregroundStyle(BespokeColor.bodyText)
            .lineSpacing(5)
            .multilineTextAlignment(.leading)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var footerSection: some View {
        HStack(alignment: .center, spacing: 12) {
            if post.isOwnPost {
                HStack(spacing: 7) {
                    Image(systemName: "person.crop.circle")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(BespokeColor.muted)

                    Text("Your post")
                        .font(BespokeFont.inter(14, weight: .semibold))
                        .foregroundStyle(BespokeColor.muted)
                }
                .accessibilityLabel("Your post")
            } else {
                MakeDuaHandsButton(hasMadeDua: post.hasMadeDua, action: onMakeDua)
            }

            Spacer(minLength: 8)

            if let timeRemaining = post.timeRemainingText {
                themeBadge(timeRemaining)
            }
        }
    }
}

private struct MakeDuaHandsButton: View {
    let hasMadeDua: Bool
    let action: () -> Void

    @State private var glowScale: CGFloat = 0.2
    @State private var glowOpacity: Double = 0

    var body: some View {
        Button {
            if !hasMadeDua {
                playGlow()
            }
            action()
        } label: {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                BespokeColor.iconHandGold.opacity(0.75),
                                BespokeColor.homeGold.opacity(0.3),
                                .clear,
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: 26
                        )
                    )
                    .frame(width: 52, height: 52)
                    .scaleEffect(glowScale)
                    .opacity(glowOpacity)
                    .blur(radius: 2)
                    .allowsHitTesting(false)

                Group {
                    if hasMadeDua {
                        Text("🤲")
                            .font(.system(size: 24))
                    } else {
                        outlineHandsIcon
                    }
                }
            }
        }
        .buttonStyle(BespokePlainButtonStyle())
        .animation(.easeInOut(duration: 0.25), value: hasMadeDua)
        .accessibilityLabel(hasMadeDua ? "Dua made" : "Make dua")
    }

    private var outlineHandsIcon: some View {
        ZStack {
            Image("DuaHandsOutline")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(BespokeColor.goldDeep)
                .scaleEffect(1.03)

            Image("DuaHandsOutline")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .foregroundStyle(BespokeColor.goldDeep)
        }
        .frame(width: 36, height: 36)
        .shadow(color: BespokeColor.goldDeep, radius: 0, x: 0.25, y: 0)
        .shadow(color: BespokeColor.goldDeep, radius: 0, x: -0.25, y: 0)
        .shadow(color: BespokeColor.goldDeep, radius: 0, x: 0, y: 0.25)
        .shadow(color: BespokeColor.goldDeep, radius: 0, x: 0, y: -0.25)
    }

    private func playGlow() {
        glowScale = 0.2
        glowOpacity = 0

        withAnimation(.spring(response: 0.38, dampingFraction: 0.72)) {
            glowScale = 1.15
            glowOpacity = 1
        }

        withAnimation(.easeOut(duration: 0.55).delay(0.45)) {
            glowScale = 1.6
            glowOpacity = 0
        }
    }
}

#Preview {
    NavigationStack {
        DuaFeedView()
    }
    .bespokeSideMenuPreviewHarness()
}
