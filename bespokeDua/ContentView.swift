//
//  ContentView.swift
//  bespokeDua
//
//  Created by Hassan Kambala on 25/03/2026.
//

import SwiftUI
#if canImport(UIKit)
import UIKit
#endif
#if canImport(AppKit)
import AppKit
#endif

// MARK: - Reflection modal (presented from dua cards via environment)

private struct PresentReflectionModalKey: EnvironmentKey {
    static var defaultValue: (([ExplanationModel]) -> Void)? { nil }
}

extension EnvironmentValues {
    var presentReflectionModal: (([ExplanationModel]) -> Void)? {
        get { self[PresentReflectionModalKey.self] }
        set { self[PresentReflectionModalKey.self] = newValue }
    }
}

// MARK: - Upgrade modal (presented from paywalled features via environment)

private struct PresentUpgradeModalKey: EnvironmentKey {
    static var defaultValue: (() -> Void)? { nil }
}

extension EnvironmentValues {
    var presentUpgradeModal: (() -> Void)? {
        get { self[PresentUpgradeModalKey.self] }
        set { self[PresentUpgradeModalKey.self] = newValue }
    }
}

private struct PresentUpgradeModalForDailyLimitKey: EnvironmentKey {
    static var defaultValue: (() -> Void)? { nil }
}

extension EnvironmentValues {
    var presentUpgradeModalForDailyLimit: (() -> Void)? {
        get { self[PresentUpgradeModalForDailyLimitKey.self] }
        set { self[PresentUpgradeModalForDailyLimitKey.self] = newValue }
    }
}

struct ContentView: View {
    @Environment(AppSession.self) private var session
    @Environment(SubscriptionManager.self) private var subscriptionManager
    @Environment(\.scenePhase) private var scenePhase
    @State private var requestText = ""
    @State private var generated: [DuaReceiver] = []
    @State private var generateInFlight = false
    @State private var generateError: String?
    @State private var selectedTab: MainTab = .home
    @State private var emptyRequestWarning = false
    @State private var savedDuaIDs: Set<UUID> = []
    /// Server `SavedDuas` id for each generated card, required to DELETE when unsaving.
    @State private var savedDuaServerIdByLocalId: [UUID: String] = [:]
    @FocusState private var duaFieldFocused: Bool
    @State private var showUpgradeInfoModal = false
    @State private var upgradeModalBecauseQuota = false
    /// Bumps when quota should be re-read from `UserDefaults` (after a generation or app resume).
    @State private var dailyQuotaRefresh = 0
    @State private var showReflectionModal = false
    @State private var reflectionModalExplanations: [ExplanationModel] = []
    @State private var showSaveDestinationModal = false
    @State private var duaPendingSave: DuaReceiver?
    @State private var isKeyboardVisible = false
    @State private var mainTabBarHeight: CGFloat = 0
    @State private var duaFeedTabRootID = UUID()
    @State private var savedTabRootID = UUID()
    @State private var profileTabRootID = UUID()
    @State private var homePath = NavigationPath()
    @State private var duaFeedPath = NavigationPath()
    @State private var savedPath = NavigationPath()
    @State private var homeActivityRefresh = 0
    @State private var homeScrollPosition = ScrollPosition()
    @State private var sunnahRestoreSnapshot: HomeRecentActivity.SunnahSnapshot?
  @State private var nameOfTheDay: AllahNameDetail?
    @State private var nameOfTheDayLoading = false
    /// Bumps at local midnight (and on resume) so today's name always reloads.
    @State private var nameOfTheDayDayKey = HomeNameOfTheDayService.localDayKey()
    @State private var showNameReflectionModal = false
    @State private var recentSearchesExpanded = false
    @State private var sideMenu = BespokeSideMenuCoordinator()
    @State private var hidesMainTabBar = false

    private var mainTabBarClearance: CGFloat {
        (isKeyboardVisible || hidesMainTabBar) ? 0 : mainTabBarHeight
    }

    private var tabBarChromeHeight: CGFloat {
        MainTabBarLayout.bottomCoverHeight(customTabBarHeight: mainTabBarHeight)
    }

    private var allowsSideMenuEdgeSwipe: Bool {
        switch selectedTab {
        case .home:
            homePath.isEmpty
        case .duaFeed:
            duaFeedPath.isEmpty
        case .saved:
            savedPath.isEmpty
        case .profile, .sunnah, .names:
            false
        }
    }

    var body: some View {
        tabViewSessionHandlers
    }

    private var tabViewWithModalOverlays: some View {
        tabViewWithModalOverlayStack
            .animation(.easeInOut(duration: 0.28), value: showUpgradeInfoModal)
            .animation(.easeInOut(duration: 0.28), value: showReflectionModal)
            .animation(.easeInOut(duration: 0.28), value: showNameReflectionModal)
            .animation(.easeInOut(duration: 0.28), value: showSaveDestinationModal)
    }

    private var tabViewWithModalOverlayStack: some View {
        configuredTabView
            .overlay { modalOverlayStack }
    }

    @ViewBuilder
    private var modalOverlayStack: some View {
        upgradeInfoOverlay
        reflectionOverlay
        nameReflectionOverlay
        saveDestinationOverlay
    }

    @ViewBuilder
    private var tabViewSessionHandlers: some View {
        tabViewWithLifecycleHandlers
            .fullScreenCover(isPresented: authSheetBinding) {
                AuthModalView()
                    .environment(session)
            }
            .task(id: session.currentUser?.userId) {
                subscriptionManager.updateDatabaseSubscriptionStatus(plan: session.currentUser?.plan)
                await subscriptionManager.refreshEntitlements()
                session.scheduleSavedDuasRefresh()
                session.scheduleDuaCollectionsRefresh()
                await session.warmUpAppContent()
                session.startDuaFeedAutoRefresh()
            }
    }

    @ViewBuilder
    private var tabViewWithLifecycleHandlers: some View {
        tabViewWithModalOverlays
            .onChange(of: session.isLoggedIn) { _, loggedIn in
                if !loggedIn {
                    selectedTab = .home
                    homePath = NavigationPath()
                    clearHomeSessionState()
                    subscriptionManager.clearDatabaseSubscriptionStatus()
                } else {
                    subscriptionManager.updateDatabaseSubscriptionStatus(plan: session.currentUser?.plan)
                }
            }
            .onChange(of: session.currentUser?.plan) { _, plan in
                subscriptionManager.updateDatabaseSubscriptionStatus(plan: plan)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    nameOfTheDayDayKey = HomeNameOfTheDayService.localDayKey()
                    dailyQuotaRefresh += 1
                    session.startDuaFeedAutoRefresh()
                    Task {
                        subscriptionManager.updateDatabaseSubscriptionStatus(plan: session.currentUser?.plan)
                        await subscriptionManager.refreshEntitlements()
                        await session.refreshDuaFeed(showLoading: false)
                    }
                } else {
                    session.stopDuaFeedAutoRefresh()
                }
            }
            .task {
                while !Task.isCancelled {
                    let seconds = HomeNameOfTheDayService.secondsUntilNextLocalMidnight()
                    try? await Task.sleep(for: .seconds(seconds))
                    guard !Task.isCancelled else { break }
                    nameOfTheDayDayKey = HomeNameOfTheDayService.localDayKey()
                }
            }
            .onChange(of: showUpgradeInfoModal) { _, shown in
                if !shown { upgradeModalBecauseQuota = false }
            }
    }

    private var authSheetBinding: Binding<Bool> {
        Binding(
            get: { session.showAuthSheet },
            set: { session.showAuthSheet = $0 }
        )
    }

    private var configuredTabView: some View {
        tabViewWithTabBarOverlay
            .bespokeSideMenuOverlay(coordinator: sideMenu, allowsEdgeSwipe: allowsSideMenuEdgeSwipe)
            .fullScreenCover(isPresented: sideMenuPresentationBinding(\.accountSettingsPresented)) {
                AccountSettingsView(initialTab: sideMenu.accountSettingsTab)
                    .environment(sideMenu)
                    .environment(\.openSideMenu, { sideMenu.open() })
                    .onDisappear {
                        sideMenu.accountSettingsTab = .profile
                    }
            }
            .onPreferenceChange(MainTabBarHeightKey.self) { mainTabBarHeight = $0 }
            #if canImport(UIKit)
            .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
                guard
                    let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
                else { return }
                let screenHeight = UIScreen.main.bounds.height
                isKeyboardVisible = frame.minY < screenHeight - 1
            }
            #endif
    }

    private var tabViewWithTabBarOverlay: some View {
        tabViewWithPresentationEnvironments
            .overlay(alignment: .bottom) {
                bottomTabBarOverlay
            }
            .animation(.easeOut(duration: 0.2), value: isKeyboardVisible)
            .animation(.easeOut(duration: 0.2), value: hidesMainTabBar)
    }

    private var tabViewWithPresentationEnvironments: some View {
        tabViewWithCoreEnvironments
            .environment(\.presentReflectionModal) { explanations in
                reflectionModalExplanations = explanations
                showReflectionModal = true
            }
            .environment(\.presentUpgradeModal) {
                upgradeModalBecauseQuota = false
                showUpgradeInfoModal = true
            }
            .environment(\.presentUpgradeModalForDailyLimit) {
                presentUpgradeSheetForDailyLimit()
            }
            .environment(\.presentSaveDuaModal) { dua in
                Task { await handleSaveTap(dua) }
            }
    }

    private var tabViewWithCoreEnvironments: some View {
        mainTabView
            .toolbar(.hidden, for: .tabBar)
            .toolbarBackground(.hidden, for: .tabBar)
            .safeAreaPadding(.bottom, hidesMainTabBar ? -tabBarChromeHeight : 0)
            #if canImport(UIKit)
            .background {
                SystemTabBarHider(isHidden: true)
                    .frame(width: 0, height: 0)
            }
            #endif
            .environment(sideMenu)
            .environment(\.openSideMenu, { sideMenu.open() })
            .environment(\.mainTabBarClearance, mainTabBarClearance)
            .environment(\.mainTabBarHidden, hidesMainTabBar)
            .environment(\.mainTabBarVisibility, MainTabBarVisibilityAction(setHidden: { hidesMainTabBar = $0 }))
            .environment(\.selectMainTab, SelectMainTabAction { selectedTab = $0 })
            .onChange(of: selectedTab) { previousTab, _ in
                resetTabRootIfNeeded(previousTab)
            }
    }

    private var mainTabView: some View {
        TabView(selection: $selectedTab) {
            homeTab
            duaFeedTab
            savedTab
            profileTab
        }
        .disablingTabBarMinimize()
    }

    private var homeTab: some View {
        NavigationStack(path: $homePath) {
            homeNavigationRoot
                .navigationDestination(for: HomeRoute.self) { route in
                    homeRouteDestination(route)
                }
                .onChange(of: homePath.count) { oldCount, newCount in
                    if newCount < oldCount, newCount > 0 {
                        homeActivityRefresh += 1
                    }
                }
        }
        .environment(\.openSideMenu, { sideMenu.open() })
        .tag(MainTab.home)
    }

    @ViewBuilder
    private func homeRouteDestination(_ route: HomeRoute) -> some View {
        switch route {
        case .bespoke:
            bespokeDuaFlowView
        case .sunnah:
            SunnahDuasView(
                restoreSnapshot: sunnahRestoreSnapshot,
                onActivityChanged: { homeActivityRefresh += 1 }
            )
        case .names:
            NamesLibraryView { destination in
                homePath.append(HomeRoute.namesCategory(destination))
            }
        case let .namesCategory(destination):
            NamesFilteredListView(destination: destination)
        }
    }

    private var duaFeedTab: some View {
        NavigationStack(path: $duaFeedPath) {
            DuaFeedView(
                navigationPath: $duaFeedPath,
                isTabActive: selectedTab == .duaFeed
            )
                .toolbar(.hidden, for: .navigationBar)
                .bespokeStyledNavigationBar(showsMainBar: false)
                .navigationBarBackButtonHidden(true)
                #if canImport(UIKit)
                .background {
                    BespokeNavBarLeadingButtonHost(
                        icon: .menu,
                        onTap: { sideMenu.open() },
                        overlaysWhenBarHidden: true,
                        isVisible: duaFeedPath.isEmpty
                    )
                }
                #endif
        }
        .environment(\.openSideMenu, { sideMenu.open() })
        .id(duaFeedTabRootID)
        .tag(MainTab.duaFeed)
    }

    private var savedTab: some View {
        NavigationStack(path: $savedPath) {
            HeartsDuaHubView(navigationPath: $savedPath)
                .toolbar(.hidden, for: .navigationBar)
                .bespokeStyledNavigationBar(showsMainBar: false)
                .navigationBarBackButtonHidden(true)
        }
        .environment(\.openSideMenu, { sideMenu.open() })
        .id(savedTabRootID)
        .tag(MainTab.saved)
    }

    private var profileTab: some View {
        NavigationStack {
            ProfileView()
                .bespokeMainNavigationToolbar(title: MainTab.profile.navigationTitle)
                .bespokeStyledNavigationBar()
        }
        .environment(\.openSideMenu, { sideMenu.open() })
        .id(profileTabRootID)
        .tag(MainTab.profile)
    }

    @ViewBuilder
    private var bottomTabBarOverlay: some View {
        if !isKeyboardVisible, !hidesMainTabBar {
            MainTabBar(
                selection: $selectedTab,
                homeNavigationDepth: homePath.count,
                savedNavigationDepth: savedPath.count,
                onPopHomeStack: {
                    guard !homePath.isEmpty else { return }
                    var transaction = Transaction()
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        homePath.removeLast(homePath.count)
                    }
                },
                onPopSavedStack: {
                    guard !savedPath.isEmpty else { return }
                    withAnimation(.easeInOut(duration: 0.32)) {
                        savedPath.removeLast(savedPath.count)
                    }
                }
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var upgradeInfoOverlay: some View {
        if showUpgradeInfoModal {
            UpgradeInfoModalView(
                isPresented: $showUpgradeInfoModal,
                emphasizeDailyLimit: upgradeModalBecauseQuota
            )
            .transition(.opacity)
        }
    }

    @ViewBuilder
    private var reflectionOverlay: some View {
        if showReflectionModal {
            reflectionModalContent()
        }
    }

    private func reflectionModalContent() -> some View {
        ReflectionModalOverlay(
            isPresented: $showReflectionModal,
            explanations: $reflectionModalExplanations
        )
    }

    @ViewBuilder
    private var nameReflectionOverlay: some View {
        if showNameReflectionModal, let nameOfTheDay {
            nameReflectionModalContent(nameOfTheDay)
        }
    }

    private func nameReflectionModalContent(_ nameOfTheDay: AllahNameDetail) -> some View {
        NameReflectionModalOverlay(
            isPresented: $showNameReflectionModal,
            nameOfTheDay: nameOfTheDay
        )
    }

    @ViewBuilder
    private var saveDestinationOverlay: some View {
        if showSaveDestinationModal, let dua = duaPendingSave {
            saveDestinationModalContent(for: dua)
        }
    }

    private func saveDestinationModalContent(for dua: DuaReceiver) -> some View {
        SaveDuaDestinationModalView(
            isPresented: $showSaveDestinationModal,
            dua: dua,
            canUseCollections: subscriptionManager.isSubscribed,
            onSave: { dua, collectionIds in
                await saveDua(dua, toCollectionIds: collectionIds)
            },
            onAddCollections: {
                showSaveDestinationModal = false
                duaPendingSave = nil
                selectedTab = .saved
            }
        )
        .transition(.opacity)
    }

    /// Free tier has used today’s allowance; primary CTA becomes Upgrade instead of Generate.
    private var shouldShowUpgradeInsteadOfGenerate: Bool {
        guard session.isLoggedIn, let uid = session.currentUser?.userId else { return false }
        guard !subscriptionManager.isSubscribed else { return false }
        return !DailyGenerationQuota.hasRemainingFreeGenerations(userId: uid)
    }

    private func presentUpgradeSheetForDailyLimit() {
        upgradeModalBecauseQuota = true
        showUpgradeInfoModal = true
    }

    // MARK: - Home dashboard

    private enum HomeRoute: Hashable {
        case bespoke
        case sunnah
        case names
        case namesCategory(NamesLibraryDestination)
    }

    private var recentBespokeActivity: HomeRecentActivity.Snapshot? {
        guard let uid = session.currentUser?.userId else { return nil }
        _ = homeActivityRefresh
        return HomeRecentActivity.load(userId: uid)
    }

    private var recentSunnahActivity: HomeRecentActivity.SunnahSnapshot? {
        guard let uid = session.currentUser?.userId else { return nil }
        _ = homeActivityRefresh
        return HomeRecentActivity.loadSunnah(userId: uid)
    }

    private var showsHomeContinueSection: Bool {
        recentBespokeActivity != nil || recentSunnahActivity != nil
    }

    private var showsHomeMainNavigationBar: Bool {
        homePath.isEmpty
    }

    @ViewBuilder
    private var homeNavigationRoot: some View {
        homeNavigationScrollView
            .bespokeStyledNavigationBar(showsMainBar: showsHomeMainNavigationBar)
            .modifier(HomeMainNavigationChrome(
                showsMainBar: showsHomeMainNavigationBar,
                title: MainTab.home.navigationTitle
            ))
            .animation(nil, value: showsHomeMainNavigationBar)
    }

    private var homeNavigationScrollView: some View {
        ScrollView {
            homeDashboardContent
                .padding(.bottom, mainTabBarClearance)
        }
        .scrollPosition($homeScrollPosition)
        .scrollIndicators(.hidden, axes: .vertical)
        .background {
            LinearGradient.bespokeHomeCanvas
                .ignoresSafeArea()
        }
        .id(HomeScrollIdentity.root)
    }

    private enum HomeCardLayout {
        static let sectionSpacing: CGFloat = 32
        static let cardSpacing: CGFloat = HomeFeatureCardLayout.cardSpacing
        static let horizontalPadding: CGFloat = HomeFeatureCardLayout.pageHorizontalPadding
        /// Pulls action cards up toward the bottom edge of the hero artwork.
        static let heroCardsOverlap: CGFloat = 96
        static let heroArtHeight: CGFloat = 280
        static let profileTrailingInset: CGFloat = 16
        static let profileIconSize: CGFloat = 22
        /// At `heroArtHeight`, distance from the PNG’s trailing edge to the chain centre line.
        static let heroArtChainAnchorFromTrailing: CGFloat = 0
        /// Extra nudge after profile alignment (negative = left, positive = right).
        static let heroArtHorizontalFineTune: CGFloat = 35
        static let heroHeadlineTopPadding: CGFloat = 44
        static let heroStarHeight: CGFloat = 17
        /// Positive values move the star down relative to the headline.
        static let heroStarVerticalNudge: CGFloat = 8
        /// Lifts hero art so the arch point is slightly clipped at the top.
        static let heroArtVerticalOffset: CGFloat = -24

        static var profileCenterFromTrailing: CGFloat {
            profileTrailingInset + profileIconSize / 2
        }

        static var heroArtTrailingPadding: CGFloat {
            profileTrailingInset
        }

        static var heroArtHorizontalOffset: CGFloat {
            let scaledChainAnchor = heroArtChainAnchorFromTrailing * (heroArtHeight / 280)
            return profileCenterFromTrailing - profileTrailingInset - scaledChainAnchor + heroArtHorizontalFineTune
        }

        static var heroStarOffsetY: CGFloat {
            -(heroHeadlineTopPadding / 2 + heroStarHeight / 2) + heroStarVerticalNudge
        }
    }

    private var homeDashboardContent: some View {
        VStack(spacing: HomeCardLayout.sectionSpacing) {
            VStack(spacing: 0) {
                homeHeroSection

                VStack(spacing: HomeCardLayout.cardSpacing) {
                    HomeFeatureCard(content: .bespoke) {
                        openBespokeFlow(restore: nil)
                    }

                    HomeFeatureCard(content: .sunnah) {
                        openSunnahFlow(restore: nil)
                    }

                    HomeFeatureCard(content: .names) {
                        homePath.append(HomeRoute.names)
                    }
                }
                .padding(.horizontal, HomeCardLayout.horizontalPadding)
                .padding(.top, -HomeCardLayout.heroCardsOverlap)
            }

            homeNameADaySection

            if showsHomeContinueSection {
                homeContinueSection
            }
        }
        .padding(.bottom, 24)
    }

    private func homeSectionHeader(
        title: String,
        titleSize: CGFloat = 22,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(BespokeFont.display(titleSize))
                .foregroundStyle(BespokeColor.forest)

            Spacer(minLength: 8)

            if let actionTitle, let action {
                Button(action: action) {
                    HStack(spacing: 4) {
                        Text(actionTitle)
                            .font(BespokeFont.inter(14, weight: .medium))
                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                    }
                    .foregroundStyle(BespokeColor.homeGold)
                }
                .buttonStyle(BespokePlainButtonStyle())
            }
        }
        .padding(.horizontal, HomeCardLayout.horizontalPadding)
    }

    private var homeHeroSection: some View {
        ZStack(alignment: .topLeading) {
            Image("HomeHeroArt")
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
                .frame(height: HomeCardLayout.heroArtHeight)
                .frame(maxWidth: .infinity, maxHeight: HomeCardLayout.heroArtHeight, alignment: .trailing)
                .padding(.trailing, HomeCardLayout.heroArtTrailingPadding)
                .offset(
                    x: HomeCardLayout.heroArtHorizontalOffset,
                    y: HomeCardLayout.heroArtVerticalOffset
                )
                .frame(maxWidth: .infinity)
                .frame(height: HomeCardLayout.heroArtHeight, alignment: .top)
                .clipped()
                .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 10) {
                homeHeroHeadline

                Text("Your feelings matter. Share, discover, and grow closer to Allah through dua.")
                    .font(BespokeFont.inter(14, weight: .regular))
                    .foregroundStyle(BespokeColor.muted)
                    .multilineTextAlignment(.leading)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: 268, alignment: .leading)
            .padding(.horizontal, HomeCardLayout.horizontalPadding)
            .padding(.top, HomeCardLayout.heroHeadlineTopPadding)
        }
        .frame(maxWidth: .infinity)
        .frame(height: HomeCardLayout.heroArtHeight, alignment: .topLeading)
    }

    private var homeHeroHeadline: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(alignment: .firstTextBaseline, spacing: 0) {
                Text("How can ")
                Text("we")
                    .overlay(alignment: .top) {
                        HomeHeroStarMark()
                            .offset(y: HomeCardLayout.heroStarOffsetY)
                    }
                Text(" help")
            }

            Text("you make dua today?")
        }
        .font(BespokeFont.display(26))
        .foregroundStyle(BespokeColor.forest)
        .multilineTextAlignment(.leading)
        .lineSpacing(2)
        .fixedSize(horizontal: false, vertical: true)
    }

    private var homeNameADaySection: some View {
        Group {
            if nameOfTheDayLoading, nameOfTheDay == nil {
                HomeNameOfTheDayCard.loading
            } else if let nameOfTheDay {
                HomeNameOfTheDayCard(name: nameOfTheDay) {
                    showNameReflectionModal = true
                }
            } else {
                HomeNameOfTheDayCard.dhikrFallback
            }
        }
        .padding(.horizontal, HomeCardLayout.horizontalPadding)
        .task(id: "\(homeActivityRefresh)-\(nameOfTheDayDayKey)") {
            await loadNameOfTheDay()
        }
    }

    @MainActor
    private func loadNameOfTheDay() async {
        nameOfTheDayLoading = true
        defer { nameOfTheDayLoading = false }

        nameOfTheDay = try? await HomeNameOfTheDayService.todaysName()
    }

    private var homeContinueSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline) {
                    Text("Most recent searches")
                        .font(BespokeFont.display(22))
                        .foregroundStyle(BespokeColor.forest)

                    Spacer(minLength: 8)

                    Button {
                        withAnimation(.easeInOut(duration: 0.25)) {
                            recentSearchesExpanded.toggle()
                        }
                    } label: {
                        HStack(spacing: 4) {
                            Text("View all")
                                .font(BespokeFont.inter(14, weight: .medium))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .semibold))
                                .rotationEffect(.degrees(recentSearchesExpanded ? 0 : -90))
                                .animation(.easeInOut(duration: 0.25), value: recentSearchesExpanded)
                        }
                        .foregroundStyle(BespokeColor.homeGold)
                    }
                    .buttonStyle(BespokePlainButtonStyle())
                }

                Text("Return to what you were looking for")
                    .font(BespokeFont.inter(14, weight: .regular))
                    .foregroundStyle(BespokeColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, HomeCardLayout.horizontalPadding)

            if recentSearchesExpanded {
                VStack(spacing: 0) {
                    if let activity = recentBespokeActivity {
                        HomeRecentSearchRow(
                            symbolName: "square.and.pencil",
                            iconBackground: BespokeColor.homeMintIcon,
                            iconForeground: BespokeColor.forest,
                            title: "Bespoke Dua",
                            queryText: activity.requestText,
                            statusText: continueStatusText(
                                isGenerating: activity.isGenerating && activity.generated.isEmpty,
                                generatingLabel: "Crafting your duas…",
                                savedAt: activity.savedAt
                            ),
                            showDivider: recentSunnahActivity != nil
                        ) {
                            openBespokeFlow(restore: activity)
                        }
                    }

                    if let activity = recentSunnahActivity {
                        HomeRecentSearchRow(
                            symbolName: "book.closed.fill",
                            iconBackground: BespokeColor.homeBeigeIcon,
                            iconForeground: BespokeColor.homeGold,
                            title: "Sunnah Duas",
                            queryText: activity.requestText,
                            statusText: continueStatusText(
                                isGenerating: activity.isGenerating && activity.categories.isEmpty,
                                generatingLabel: "Finding your duas…",
                                savedAt: activity.savedAt
                            ),
                            showDivider: false
                        ) {
                            openSunnahFlow(restore: activity)
                        }
                    }
                }
                .homeListChrome(cornerRadius: 14)
                .padding(.horizontal, HomeCardLayout.horizontalPadding)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func continueStatusText(isGenerating: Bool, generatingLabel: String, savedAt: Date) -> String {
        isGenerating ? generatingLabel : relativeDateString(for: savedAt)
    }

    private var bespokeDuaFlowView: some View {
        BespokeFlowScreen(title: "Bespoke my dua", onExit: persistBespokeSession) {
            ScrollView {
                VStack(spacing: 0) {
                    inputSection

                    if !generateInFlight {
                        Rectangle()
                            .fill(BespokeColor.sectionRule)
                            .frame(maxWidth: .infinity)
                            .frame(height: 1)
                            .padding(.top, 12)
                            .padding(.bottom, 12)
                        duaResultsSection
                    }
                }
                .padding(.bottom, mainTabBarClearance)
            }
            .scrollIndicators(.hidden, axes: .vertical)
            .scrollDismissesKeyboard(.interactively)
            .background(BespokeColor.pageBackground)
        }
    }

    private func persistBespokeSession() {
        guard let uid = session.currentUser?.userId else { return }
        let trimmed = requestText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if generateInFlight {
            HomeRecentActivity.save(
                userId: uid,
                requestText: trimmed,
                generated: generated,
                isGenerating: true
            )
        } else if !generated.isEmpty {
            HomeRecentActivity.save(
                userId: uid,
                requestText: trimmed,
                generated: generated,
                isGenerating: false
            )
        }
        homeActivityRefresh += 1
    }

    private func openBespokeFlow(restore activity: HomeRecentActivity.Snapshot?) {
        sunnahRestoreSnapshot = nil
        if let activity {
            requestText = activity.requestText
            generated = HomeRecentActivity.duaReceivers(from: activity)
            savedDuaIDs = []
            savedDuaServerIdByLocalId = [:]

            if activity.isGenerating && generated.isEmpty && !generateInFlight {
                let trimmed = activity.requestText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty else { return }
                generateError = nil
                generateInFlight = true
                Task {
                    await runGenerate(trimmed: trimmed)
                }
            }
        } else {
            requestText = ""
            generated = []
            savedDuaIDs = []
            savedDuaServerIdByLocalId = [:]
        }
        generateError = nil
        emptyRequestWarning = false
        homePath.append(HomeRoute.bespoke)
    }

    private func openSunnahFlow(restore snapshot: HomeRecentActivity.SunnahSnapshot?) {
        sunnahRestoreSnapshot = snapshot
        homePath.append(HomeRoute.sunnah)
    }

    private func relativeDateString(for date: Date) -> String {
        let interval = Date.now.timeIntervalSince(date)
        if interval < 60 {
            return "Just now"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter.localizedString(for: date, relativeTo: .now)
    }

    // MARK: - Input (`input-section.scss`)

    private var inputSection: some View {
        VStack(spacing: 20) {
            Text("Write your heart’s duas")
                .font(BespokeFont.display(28))
                .foregroundStyle(BespokeColor.forest)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .padding(.top, 16)

            if session.isLoggedIn, let quotaUid = session.currentUser?.userId, !subscriptionManager.isSubscribed {
                let remaining = DailyGenerationQuota.duasRemainingToday(userId: quotaUid)
                let cap = DailyGenerationQuota.freeDailyLimit
                Text("\(remaining)/\(cap) duas left")
                    .font(BespokeFont.inter(15, weight: .semibold))
                    .foregroundStyle(BespokeColor.forest)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 16)
                    .background(BespokeColor.sectionRule)
                    .clipShape(Capsule())
                    .frame(maxWidth: .infinity)
                    .accessibilityLabel("\(remaining) of \(cap) free duas left today")
                    .id(dailyQuotaRefresh)
            }

            VStack(alignment: .leading, spacing: 12) {
                BespokePlaceholderTextEditor(
                    text: $requestText,
                    placeholder: "Type your dua here…",
                    focus: $duaFieldFocused
                )
                .padding(12)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(duaFieldFocused ? BespokeColor.gold : BespokeColor.inputBorder, lineWidth: duaFieldFocused ? 2 : 1)
                )

                Text("Example: “O Allah, grant me success in…”")
                    .font(BespokeFont.inter(13, weight: .regular))
                    .foregroundStyle(BespokeColor.muted)
            }
            .padding(18)
            .frame(maxWidth: .infinity)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(BespokeColor.cardBorder, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.06), radius: 16, x: 0, y: 6)

            Group {
                if shouldShowUpgradeInsteadOfGenerate && !generateInFlight {
                    Button {
                        presentUpgradeSheetForDailyLimit()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Upgrade")
                                .font(BespokeFont.inter(17, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(LinearGradient.bespokeGold)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .bespokeButtonHitArea(cornerRadius: 16)
                        .shadow(color: .black.opacity(0.14), radius: 12, x: 0, y: 6)
                    }
                    .buttonStyle(BespokePlainButtonStyle())
                } else {
                    Button {
                        submitGenerate()
                    } label: {
                        HStack(spacing: 10) {
                            if generateInFlight {
                                ProgressView()
                                    .tint(.white)
                                Text("Generating…")
                                    .font(BespokeFont.inter(17, weight: .semibold))
                            } else {
                                Text("Bespoke my dua")
                                    .font(BespokeFont.inter(17, weight: .semibold))
                            }
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(LinearGradient.bespokeGold)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .bespokeButtonHitArea(cornerRadius: 16)
                        .shadow(color: generateInFlight ? .clear : .black.opacity(0.14), radius: 12, x: 0, y: 6)
                    }
                    .buttonStyle(BespokePlainButtonStyle())
                    .disabled(generateInFlight)
                    .opacity(generateInFlight ? 0.72 : 1)
                }
            }
            .id(dailyQuotaRefresh)

            if emptyRequestWarning {
                Label("Please write your dua first.", systemImage: "exclamationmark.circle.fill")
                    .font(BespokeFont.inter(14, weight: .medium))
                    .foregroundStyle(BespokeColor.error)
            }

            if generateError != nil {
                Label("Something went wrong. Try again.", systemImage: "wifi.exclamationmark")
                    .font(BespokeFont.inter(14, weight: .medium))
                    .foregroundStyle(BespokeColor.error)
            }

            if generateInFlight {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Preparing your duas")
                        .font(BespokeFont.inter(20, weight: .semibold))
                        .foregroundStyle(BespokeColor.forest)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    DuaCraftingDhikrCarousel()
                }
                .padding(.top, 4)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.25), value: generateInFlight)
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity)
    }

    // MARK: - Results (`dua-result` + list + card)

    private var duaResultsSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Your duas")
                .font(BespokeFont.inter(20, weight: .semibold))
                .foregroundStyle(BespokeColor.forest)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)

            Group {
                if generated.isEmpty {
                    DuaCraftingResultsPlaceholder()
                } else {
                    LazyVStack(spacing: 14) {
                        ForEach(generated) { dua in
                            BespokeDuaCard(
                                dua: dua,
                                isSavedVisual: savedDuaIDs.contains(dua.id)
                            ) {
                                Task { await handleSaveTap(dua) }
                            }
                        }

                        Button {
                            withAnimation(.easeInOut(duration: 0.2)) {
                                generated = []
                                savedDuaIDs = []
                                savedDuaServerIdByLocalId = [:]
                            }
                            if let uid = session.currentUser?.userId {
                                HomeRecentActivity.clear(userId: uid)
                            }
                            homeActivityRefresh += 1
                        } label: {
                            Text("Clear results")
                                .font(BespokeFont.inter(15, weight: .semibold))
                                .foregroundStyle(BespokeColor.forest)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(BespokeColor.cream.opacity(0.9))
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                                        .stroke(BespokeColor.forest.opacity(0.15), lineWidth: 1)
                                )
                                .bespokeButtonHitArea(cornerRadius: 14)
                        }
                        .buttonStyle(BespokePlainButtonStyle())
                        .padding(.top, 4)
                    }
                }
            }
            .frame(
                maxWidth: .infinity,
                minHeight: generated.isEmpty ? CraftingDhikrMetrics.panelHeight : nil,
                alignment: .top
            )
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 32)
    }

    private func submitGenerate() {
        duaFieldFocused = false
        guard session.isLoggedIn else {
            session.presentAuth()
            return
        }
        if shouldShowUpgradeInsteadOfGenerate {
            presentUpgradeSheetForDailyLimit()
            return
        }
        let trimmed = requestText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            emptyRequestWarning = true
            return
        }
        emptyRequestWarning = false
        generateError = nil
        withAnimation(.easeInOut(duration: 0.25)) {
            generated = []
            generateInFlight = true
        }
        Task {
            await runGenerate(trimmed: trimmed)
        }
    }

    private func runGenerate(trimmed: String) async {
        if let id = session.currentUser?.userId {
            HomeRecentActivity.save(
                userId: id,
                requestText: trimmed,
                generated: [],
                isGenerating: true
            )
            homeActivityRefresh += 1
        }
        defer { generateInFlight = false }
        let uid = session.currentUser?.userId
        do {
            let duas = try await session.api().generateDuas(text: trimmed, userId: uid)
            generated = duas
            savedDuaIDs = []
            savedDuaServerIdByLocalId = [:]
            if let id = session.currentUser?.userId {
                HomeRecentActivity.save(
                    userId: id,
                    requestText: trimmed,
                    generated: duas,
                    isGenerating: false
                )
                homeActivityRefresh += 1
            }
            if !subscriptionManager.isSubscribed, let id = session.currentUser?.userId {
                DailyGenerationQuota.recordGeneration(userId: id)
                dailyQuotaRefresh += 1
            }
        } catch {
            generateError = "x"
            if let id = session.currentUser?.userId {
                HomeRecentActivity.save(
                    userId: id,
                    requestText: trimmed,
                    generated: generated,
                    isGenerating: false
                )
                homeActivityRefresh += 1
            }
        }
    }

    private func clearHomeSessionState() {
        requestText = ""
        generated = []
        savedDuaIDs = []
        savedDuaServerIdByLocalId = [:]
        generateInFlight = false
        generateError = nil
        emptyRequestWarning = false
        duaFieldFocused = false
        showSaveDestinationModal = false
        duaPendingSave = nil
        showReflectionModal = false
        reflectionModalExplanations = []
    }

    private func sideMenuPresentationBinding(
        _ keyPath: ReferenceWritableKeyPath<BespokeSideMenuCoordinator, Bool>
    ) -> Binding<Bool> {
        Binding(
            get: { sideMenu[keyPath: keyPath] },
            set: { sideMenu[keyPath: keyPath] = $0 }
        )
    }

    private func resetTabRootIfNeeded(_ tab: MainTab) {
        switch tab {
        case .home, .sunnah, .names:
            break
        case .duaFeed:
            duaFeedPath = NavigationPath()
        case .saved:
            savedPath = NavigationPath()
        case .profile:
            break
        }
    }

    private func handleSaveTap(_ dua: DuaReceiver) async {
        guard session.currentUser?.userId != nil else {
            session.presentAuth()
            return
        }
        if savedDuaIDs.contains(dua.id) {
            await unsaveDua(dua)
            return
        }
        session.scheduleDuaCollectionsRefresh()
        duaPendingSave = dua
        showSaveDestinationModal = true
    }

    private func unsaveDua(_ dua: DuaReceiver) async {
        guard let uid = session.currentUser?.userId else { return }
        guard let serverId = savedDuaServerIdByLocalId[dua.id] else {
            savedDuaIDs.remove(dua.id)
            return
        }
        do {
            if SavedDuaDisplay.kind(for: dua) == .sunnah {
                try await session.api().deleteSavedSunnahDua(id: serverId)
            } else {
                try await session.api().deleteSavedDua(id: serverId)
            }
            savedDuaIDs.remove(dua.id)
            savedDuaServerIdByLocalId[dua.id] = nil
            session.removeSavedDua(id: serverId)
            SavedDuaReflectionsCache.remove(userId: uid, duaId: serverId)
        } catch {
            generateError = "x"
        }
    }

    private func markDuaAsSaved(_ dua: DuaReceiver, saved: SavedDuaDTO) {
        guard let uid = session.currentUser?.userId else { return }
        savedDuaIDs.insert(dua.id)
        savedDuaServerIdByLocalId[dua.id] = saved.duaId
        session.insertSavedDua(saved)
        SavedDuaReflectionsCache.store(userId: uid, duaId: saved.duaId, explanations: dua.explanations)
    }

    private func dismissSaveDestinationModal() {
        showSaveDestinationModal = false
        duaPendingSave = nil
    }

    private func existingSavedRow(for dua: DuaReceiver) -> SavedDuaDTO? {
        if let serverId = savedDuaServerIdByLocalId[dua.id] {
            return session.savedDuas.first { $0.duaId == serverId }
        }
        return SavedDuaDisplay.existingRow(matching: dua, in: session.savedDuas)
    }

    private func saveDua(_ dua: DuaReceiver, toCollectionIds collectionIds: Set<String>) async -> String? {
        guard let uid = session.currentUser?.userId else {
            return "Something went wrong. Try again."
        }

        let saved: SavedDuaDTO
        do {
            if let existing = existingSavedRow(for: dua) {
                saved = existing
            } else if SavedDuaDisplay.kind(for: dua) == .sunnah, let payload = dua.storageJSON {
                let sunnahSaved = try await session.api().saveSunnahDua(userId: uid, sunnahDua: payload)
                saved = sunnahSaved.asSavedDuaDTO()
            } else {
                let stored = dua.storageJSON ?? SavedDuaDisplay.encodeForStorage(
                    duaText: dua.duaText,
                    explanations: dua.explanations
                )
                saved = try await session.api().saveDua(userId: uid, duaText: stored)
            }
        } catch {
            return Self.friendlySaveErrorMessage(for: error)
        }

        var collectionFailures = 0
        for collectionId in collectionIds {
            do {
                let detail = try await session.api().duaCollection(id: collectionId)
                var duaIds = detail.savedDuaIds
                if !duaIds.contains(saved.duaId) {
                    duaIds.append(saved.duaId)
                }
                let updated = try await session.api().updateDuaCollection(
                    id: collectionId,
                    body: UpdateDuaCollectionRequest(
                        name: detail.name,
                        description: detail.description,
                        duaIds: duaIds
                    )
                )
                session.upsertDuaCollection(from: updated)
            } catch {
                collectionFailures += 1
            }
        }

        markDuaAsSaved(dua, saved: saved)

        if collectionFailures > 0 {
            return collectionIds.count == 1
                ? "Saved to your library, but couldn't add it to the collection. Try again."
                : "Saved to your library, but couldn't add it to some collections. Try again."
        }

        dismissSaveDestinationModal()
        return nil
    }

    private static func friendlySaveErrorMessage(for error: Error) -> String {
        if let localized = error as? LocalizedError,
           let description = localized.errorDescription,
           !description.isEmpty {
            return description
        }
        return "Something went wrong. Try again."
    }

    /// Embeds reflections in the `dua` string when the API keeps JSON; `SavedDuaReflectionsCache` also stores them by server id when the API only keeps plain text.
    private static func jsonForSavedDuaField(_ dua: DuaReceiver) -> String {
        SavedDuaDisplay.encodeForStorage(duaText: dua.duaText, explanations: dua.explanations)
    }
}

// MARK: - Loader (`dua-result-list.scss`)

private struct BespokeLoaderDots: View {
    var body: some View {
        // ~8 updates/sec is enough for the pulse; 30/sec was unnecessary main-thread work during generation.
        TimelineView(.animation(minimumInterval: 0.12, paused: false)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 8) {
                ForEach(0 ..< 3, id: \.self) { i in
                    let phase = (t * 1.2 + Double(i) * 0.15).truncatingRemainder(dividingBy: 1)
                    let s = abs(sin(phase * .pi * 2))
                    let scale = 0.9 + 0.3 * s
                    let opacity = 0.3 + 0.7 * s
                    Circle()
                        .fill(
                            LinearGradient(
                                colors: [BespokeColor.loaderIndigo, BespokeColor.loaderGreen],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 10, height: 10)
                        .scaleEffect(scale)
                        .opacity(opacity)
                }
            }
        }
    }
}

struct BespokeDuaCard: View {
    @Environment(\.presentReflectionModal) private var presentReflectionModal

    let dua: DuaReceiver
    var isSavedVisual: Bool
    var onSave: () -> Void
    var showsActions: Bool = true
    var reservesActionBarSpace: Bool = false
    var showsEditMenu: Bool = false
    var onEdit: (() -> Void)? = nil

    @State private var copied = false

    private static let actionBarHeight: CGFloat = 30

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(dua.duaText)
                .font(BespokeFont.inter(15, weight: .regular))
                .foregroundStyle(BespokeColor.bodyText)
                .fixedSize(horizontal: false, vertical: true)

            if showsActions {
            HStack(spacing: 8) {
                if showsEditMenu, let onEdit {
                    Button(action: onEdit) {
                        HStack(spacing: 5) {
                            Image(systemName: "pencil")
                                .font(.system(size: 15))
                            Text("Edit dua")
                                .font(BespokeFont.inter(13, weight: .regular))
                        }
                        .foregroundStyle(BespokeColor.clearBtnText)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Color(red: 242 / 255, green: 242 / 255, blue: 242 / 255))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .bespokeButtonHitArea(cornerRadius: 8)
                    }
                    .buttonStyle(BespokePlainButtonStyle())
                }

                Spacer(minLength: 0)
                Button {
                    presentReflectionModal?(dua.explanations)
                } label: {
                    Image(systemName: "lightbulb")
                        .font(.system(size: 16))
                        .foregroundStyle(BespokeColor.nameGold)
                        .padding(6)
                        .background(BespokeColor.cardBorder.opacity(0.35))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .bespokeButtonHitArea(cornerRadius: 8)
                }
                .buttonStyle(BespokePlainButtonStyle())

                Button(action: onSave) {
                    Image(systemName: isSavedVisual ? "bookmark.fill" : "bookmark")
                        .font(.system(size: 16))
                        .foregroundStyle(BespokeColor.nameGold)
                        .padding(6)
                        .background(BespokeColor.cardBorder.opacity(0.35))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .bespokeButtonHitArea(cornerRadius: 8)
                }
                .buttonStyle(BespokePlainButtonStyle())

                Button {
                    copyToClipboard(dua.duaText)
                    copied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        copied = false
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 15))
                        Text(copied ? "Copied!" : "Copy")
                            .font(BespokeFont.inter(13, weight: .regular))
                    }
                    .foregroundStyle(BespokeColor.clearBtnText)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color(red: 242 / 255, green: 242 / 255, blue: 242 / 255))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    .bespokeButtonHitArea(cornerRadius: 8)
                }
                .buttonStyle(BespokePlainButtonStyle())
            }
            } else if reservesActionBarSpace {
                Color.clear
                    .frame(height: Self.actionBarHeight)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(BespokeColor.cardBorder, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.07), radius: 14, x: 0, y: 6)
    }

    private func copyToClipboard(_ text: String) {
        #if canImport(UIKit)
        UIPasteboard.general.string = text
        #elseif canImport(AppKit)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        #endif
    }
}

// MARK: - Bespoke card modal (upgrade, aim, reflection)

enum BespokeModalTheme {
    case standard
    case plus
}

struct BespokeCardModalView<Content: View>: View {
    @Binding var isPresented: Bool
    let title: String
    var theme: BespokeModalTheme = .standard
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            BespokeColor.authBackdrop
                .ignoresSafeArea()
                .background(.ultraThinMaterial.opacity(0.2))
                .onTapGesture {
                    isPresented = false
                }

            VStack(spacing: 0) {
                HStack {
                    Spacer(minLength: 0)
                    Button {
                        isPresented = false
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title2)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(theme == .plus ? BespokeColor.homeGold : BespokeColor.muted)
                            .padding(4)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(BespokePlainButtonStyle())
                    .accessibilityLabel("Close")
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)

                VStack(alignment: .leading, spacing: 18) {
                    modalTitle
                    content()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .frame(maxWidth: 540)
            .fixedSize(horizontal: false, vertical: true)
            .background(modalBackground)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(modalBorderColor, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.18), radius: 35, x: 0, y: 25)
            .padding(16)
        }
    }

    @ViewBuilder
    private var modalTitle: some View {
        switch theme {
        case .standard:
            Text(title)
                .font(BespokeFont.inter(29.6, weight: .semibold))
                .foregroundStyle(BespokeColor.forest)
        case .plus:
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "diamond.fill")
                        .font(.system(size: 9, weight: .bold))
                    Text("Premium")
                        .font(BespokeFont.inter(11.5, weight: .semibold))
                        .textCase(.uppercase)
                        .tracking(0.45)
                }
                .foregroundStyle(BespokeColor.goldDeep)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(BespokeColor.homeGold.opacity(0.16))
                .clipShape(Capsule())
                .overlay {
                    Capsule()
                        .stroke(BespokeColor.homeGold.opacity(0.22), lineWidth: 1)
                }

                HStack(spacing: 8) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(BespokeColor.homeGold)
                    Text(title)
                        .font(BespokeFont.display(30))
                        .foregroundStyle(BespokeColor.forest)
                }
            }
        }
    }

    @ViewBuilder
    private var modalBackground: some View {
        if theme == .plus {
            ZStack {
                BespokeColor.authCard
                LinearGradient(
                    colors: [
                        BespokeColor.homeGold.opacity(0.12),
                        Color.clear,
                    ],
                    startPoint: .top,
                    endPoint: UnitPoint(x: 0.5, y: 0.38)
                )
            }
        } else {
            BespokeColor.authCard
        }
    }

    private var modalBorderColor: Color {
        switch theme {
        case .standard:
            BespokeColor.forest.opacity(0.18)
        case .plus:
            BespokeColor.homeGold.opacity(0.28)
        }
    }
}

// MARK: - Save destination picker

private struct SaveDuaDestinationModalView: View {
    @Environment(AppSession.self) private var session

    @Binding var isPresented: Bool
    let dua: DuaReceiver
    let canUseCollections: Bool
    let onSave: (DuaReceiver, Set<String>) async -> String?
    let onAddCollections: () -> Void

    @State private var selectedCollectionIds: Set<String> = []
    @State private var saveInFlight = false
    @State private var saveError: String?

    private var userId: Int? { session.currentUser?.userId }

    private var duaKind: SavedDuaKind {
        SavedDuaDisplay.kind(for: dua)
    }

    private var availableCollections: [DuaCollectionSummaryDTO] {
        session.duaCollections.sorted { lhs, rhs in
            let lhsMatchesKind = DuaCollectionDisplay.kind(for: lhs, userId: userId) == duaKind
            let rhsMatchesKind = DuaCollectionDisplay.kind(for: rhs, userId: userId) == duaKind
            if lhsMatchesKind != rhsMatchesKind { return lhsMatchesKind }
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
    }

    var body: some View {
        BespokeCardModalView(isPresented: saveModalBinding, title: "Where to save?") {
            saveDestinationModalBody
        }
        .onAppear {
            if canUseCollections {
                session.scheduleDuaCollectionsRefresh()
            }
        }
    }

    @ViewBuilder
    private var saveDestinationModalBody: some View {
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
            SaveDuaDestinationRow(
                symbolName: "bookmark.fill",
                title: "General",
                subtitle: generalSubtitle,
                isSelected: true,
                isLocked: true
            )

            if canUseCollections {
                collectionsSection
            } else {
                nonSubscriberCollectionsSection
            }
        }

        saveDestinationButton
    }

    private var saveDestinationButton: some View {
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
        .disabled(saveInFlight)
        .padding(.top, 6)
    }

    private var helperText: String {
        if canUseCollections {
            "Every dua is saved to General. Optionally add it to collections too."
        } else {
            "Your dua will be saved to your main library."
        }
    }

    @ViewBuilder
    private var collectionsSection: some View {
        if session.duaCollectionsLoading && session.duaCollections.isEmpty {
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
                        SaveDuaDestinationRow(
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

    private var nonSubscriberCollectionsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Collections")
                .font(BespokeFont.inter(12, weight: .semibold))
                .foregroundStyle(BespokeColor.muted)
                .textCase(.uppercase)
                .tracking(0.9)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)

            Button(action: onAddCollections) {
                HStack(spacing: 10) {
                    Image(systemName: "folder.badge.plus")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Add collections")
                        .font(BespokeFont.inter(16, weight: .semibold))
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

    private var saveModalBinding: Binding<Bool> {
        Binding(
            get: { isPresented },
            set: { newValue in
                guard !saveInFlight else { return }
                isPresented = newValue
            }
        )
    }

    private var generalSubtitle: String {
        let count = session.savedDuas.count
        switch count {
        case 0: return "Your main library"
        case 1: return "1 saved dua"
        default: return "\(count) saved duas"
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
    private func saveSelection() async {
        guard !saveInFlight else { return }
        saveInFlight = true
        saveError = nil

        let collectionIds = canUseCollections ? selectedCollectionIds : []
        let errorMessage = await onSave(dua, collectionIds)
        saveInFlight = false

        if let errorMessage {
            saveError = errorMessage
        }
    }
}

private struct SaveDuaDestinationRow: View {
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

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(BespokeFont.inter(15, weight: .semibold))
                    .foregroundStyle(BespokeColor.forest)
                    .lineLimit(1)
                Text(subtitle)
                    .font(BespokeFont.inter(13, weight: .regular))
                    .foregroundStyle(BespokeColor.muted)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 22, weight: .medium))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isSelected ? BespokeColor.forest : BespokeColor.muted.opacity(0.45))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(isSelected ? BespokeColor.forest.opacity(0.06) : Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(isSelected ? BespokeColor.forest.opacity(0.28) : BespokeColor.cardBorder, lineWidth: 1)
        )
        .bespokeButtonHitArea(cornerRadius: 14)
        .animation(nil, value: isSelected)
    }
}

// MARK: - Upgrade info (full-screen modal)

struct UpgradeInfoModalView: View {
    @Environment(AppSession.self) private var session
    @Environment(SubscriptionManager.self) private var subscriptionManager
    @Environment(\.openURL) private var openURL
    @Binding var isPresented: Bool
    @State private var showTransferConfirmation = false
    var emphasizeDailyLimit: Bool

    private static let manageSubscriptionsURL = URL(string: "https://apps.apple.com/account/subscriptions")!
    private static let privacyPolicyURL = URL(
        string: "https://www.bespokedua.com/privacy-policy"
    )!
    /// Standard Apple Terms of Use (EULA) for auto-renewable subscriptions.
    private static let appleStandardEULAURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    private static let renewalDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter
    }()

    var body: some View {
        BespokeCardModalView(isPresented: $isPresented, title: "Bespoke Plus", theme: .plus) {
            if subscriptionManager.isSubscribed {
                subscribedContent
            } else {
                upgradeContent
            }

            legalLinks
        }
        .task {
            subscriptionManager.updateDatabaseSubscriptionStatus(plan: session.currentUser?.plan)
            await subscriptionManager.loadProduct()
            await subscriptionManager.refreshEntitlements()
        }
    }

    private var subscribedContent: some View {
        Group {
            Text("You’re subscribed. Enjoy unlimited bespoke duas.")
                .font(BespokeFont.inter(16, weight: .regular))
                .foregroundStyle(BespokeColor.bodyText)
                .fixedSize(horizontal: false, vertical: true)

            plusFeaturesPanel {
                EmptyView()
            }

            if let renewalDate = subscriptionManager.appleSubscriptionRenewalDate {
                Text("Renews on \(Self.renewalDateFormatter.string(from: renewalDate)).")
                    .font(BespokeFont.inter(15, weight: .semibold))
                    .foregroundStyle(BespokeColor.goldDeep)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Renewal details are available in your Apple subscription settings.")
                    .font(BespokeFont.inter(14, weight: .regular))
                    .foregroundStyle(BespokeColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 10) {
                Button {
                    openURL(Self.manageSubscriptionsURL)
                } label: {
                    Text("Manage in App Store")
                        .font(BespokeFont.inter(16, weight: .semibold))
                        .foregroundStyle(BespokeColor.goldDeep)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
                .tint(BespokeColor.homeGold)

                Button {
                    openURL(Self.manageSubscriptionsURL)
                } label: {
                    Text("Cancel subscription")
                        .font(BespokeFont.inter(16, weight: .semibold))
                        .foregroundStyle(BespokeColor.cream)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(BespokeColor.error)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .bespokeButtonHitArea(cornerRadius: 16)
                }
                .buttonStyle(BespokePlainButtonStyle())
            }
            .padding(.top, 4)
        }
    }

    private var upgradeContent: some View {
        Group {
            if emphasizeDailyLimit {
                Text("You’ve used all \(DailyGenerationQuota.freeDailyLimit) free duas for today. Subscribe to continue.")
                    .font(BespokeFont.inter(16, weight: .regular))
                    .foregroundStyle(BespokeColor.bodyText)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Subscribe for unlimited duas. Free accounts can create up to \(DailyGenerationQuota.freeDailyLimit) duas per day.")
                    .font(BespokeFont.inter(16, weight: .regular))
                    .foregroundStyle(BespokeColor.bodyText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            plusFeaturesPanel {
                Group {
                    if subscriptionManager.loadInFlight && subscriptionManager.product == nil {
                        HStack(spacing: 10) {
                            ProgressView()
                                .tint(BespokeColor.homeGold)
                            Text("Loading subscription…")
                                .font(BespokeFont.inter(15, weight: .medium))
                                .foregroundStyle(BespokeColor.muted)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else if let priceLine = subscriptionManager.plusMonthlyDisplayPrice {
                        Text(priceLine)
                            .font(BespokeFont.inter(20, weight: .semibold))
                            .foregroundStyle(LinearGradient.bespokeGold)
                    }
                }
            }

            if let err = subscriptionManager.lastErrorMessage, !err.isEmpty {
                Text(err)
                    .font(BespokeFont.inter(14, weight: .medium))
                    .foregroundStyle(BespokeColor.error)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(spacing: 10) {
                Button {
                    Task {
                        await subscriptionManager.purchase()
                        guard subscriptionManager.hasActiveAppleSubscription, session.isLoggedIn else { return }
                        do {
                            try await session.syncSubscribedPlan(
                                originalTransactionId: subscriptionManager.appleOriginalTransactionID
                            )
                        } catch {
                            subscriptionManager.setSyncErrorMessage(
                                (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                            )
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Subscribe")
                            .font(BespokeFont.inter(17, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(LinearGradient.bespokeGold)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .bespokeButtonHitArea(cornerRadius: 16)
                    .shadow(color: BespokeColor.goldDeep.opacity(0.28), radius: 10, x: 0, y: 5)
                }
                .buttonStyle(BespokePlainButtonStyle())
                .disabled(subscriptionManager.purchaseInFlight || subscriptionManager.product == nil)
                .opacity(subscriptionManager.purchaseInFlight || subscriptionManager.product == nil ? 0.55 : 1)

                Button {
                    Task {
                        await subscriptionManager.restorePurchases()
                        guard subscriptionManager.hasActiveAppleSubscription, session.isLoggedIn else { return }
                        do {
                            try await session.syncSubscribedPlan(
                                originalTransactionId: subscriptionManager.appleOriginalTransactionID
                            )
                            showTransferConfirmation = false
                        } catch {
                            let message = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                            if message.localizedCaseInsensitiveContains("confirm transfer") {
                                showTransferConfirmation = true
                                subscriptionManager.setSyncErrorMessage(
                                    "This Apple subscription is linked to another account. Confirm transfer to move it here."
                                )
                            } else {
                                subscriptionManager.setSyncErrorMessage(message)
                            }
                        }
                    }
                } label: {
                    Text("Restore purchases")
                        .font(BespokeFont.inter(15, weight: .semibold))
                        .foregroundStyle(BespokeColor.goldDeep)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(Color.white.opacity(0.55))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(BespokeColor.homeGold.opacity(0.35), lineWidth: 1)
                        }
                }
                .buttonStyle(BespokePlainButtonStyle())
                .disabled(subscriptionManager.purchaseInFlight)

                if showTransferConfirmation {
                    Button {
                        Task {
                            guard session.isLoggedIn else { return }
                            do {
                                try await session.syncSubscribedPlan(
                                    originalTransactionId: subscriptionManager.appleOriginalTransactionID,
                                    confirmTransfer: true
                                )
                                showTransferConfirmation = false
                            } catch {
                                subscriptionManager.setSyncErrorMessage(
                                    (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                                )
                            }
                        }
                    } label: {
                        Text("Confirm transfer to this account")
                            .font(BespokeFont.inter(15, weight: .semibold))
                            .foregroundStyle(BespokeColor.cream)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                            .background(BespokeColor.error)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .bespokeButtonHitArea(cornerRadius: 16)
                    }
                    .buttonStyle(BespokePlainButtonStyle())
                    .disabled(subscriptionManager.purchaseInFlight)
                    .opacity(subscriptionManager.purchaseInFlight ? 0.55 : 1)
                }
            }
            .padding(.top, 4)

            Text("Payment will be charged to your Apple ID. Subscription renews monthly until cancelled in Settings.")
                .font(BespokeFont.inter(12, weight: .regular))
                .foregroundStyle(BespokeColor.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func plusFeaturesPanel<Trailing: View>(
        @ViewBuilder trailing: () -> Trailing
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Features")
                .font(BespokeFont.inter(16, weight: .semibold))
                .foregroundStyle(BespokeColor.forest)

            BespokePlusFeaturesList()

            trailing()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(BespokeColor.cardBorder, lineWidth: 1)
        }
    }

    private var legalLinks: some View {
        HStack(spacing: 18) {
            Link("Privacy Policy", destination: Self.privacyPolicyURL)
                .font(BespokeFont.inter(15, weight: .semibold))
                .foregroundStyle(BespokeColor.goldDeep)

            Link("Terms of Use (EULA)", destination: Self.appleStandardEULAURL)
                .font(BespokeFont.inter(15, weight: .semibold))
                .foregroundStyle(BespokeColor.goldDeep)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 4)
    }
}

// MARK: - Auth password (UIKit; SwiftUI SecureField misbehaves with keyboard / fullScreenCover)

#if canImport(UIKit)
private struct AuthSecureUITextField: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String = "Password"

    func makeUIView(context: Context) -> UITextField {
        let tf = UITextField()
        tf.isSecureTextEntry = true
        tf.autocapitalizationType = .none
        tf.autocorrectionType = .no
        // `password` / `newPassword` often triggers AutoFill + “strong password” UI that replaces text and
        // breaks two-way SwiftUI bridges. Typing must work first; users can still paste from the keychain.
        tf.textContentType = nil
        tf.passwordRules = nil
        tf.keyboardType = .asciiCapable
        tf.borderStyle = .none
        tf.backgroundColor = .clear
        let font = UIFont(name: "Inter-Regular", size: 16) ?? .systemFont(ofSize: 16)
        tf.font = font
        tf.textColor = Self.bodyText
        tf.tintColor = Self.forest
        tf.attributedPlaceholder = NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: Self.subtle,
                .font: font,
            ]
        )
        tf.delegate = context.coordinator
        tf.addTarget(context.coordinator, action: #selector(Coordinator.editingChanged(_:)), for: .editingChanged)
        context.coordinator.text = $text
        tf.text = text
        return tf
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        context.coordinator.text = $text
        // Do not touch `textContentType` / `passwordRules` here — reapplying can reset secure fields on iOS 18+.

        // Allow programmatic clears (e.g. after failed login) even while the field is focused.
        if text.isEmpty, !(uiView.text ?? "").isEmpty {
            uiView.text = ""
            return
        }

        if context.coordinator.isUserEditing || uiView.isFirstResponder {
            return
        }
        if uiView.text != text {
            uiView.text = text
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var text = Binding.constant("")

        /// `isFirstResponder` is unreliable for secure fields; delegate callbacks match actual editing sessions.
        var isUserEditing = false

        @objc func editingChanged(_ sender: UITextField) {
            text.wrappedValue = sender.text ?? ""
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            isUserEditing = true
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            isUserEditing = false
            text.wrappedValue = textField.text ?? ""
        }
    }

    private static let bodyText = UIColor(red: 51 / 255, green: 51 / 255, blue: 51 / 255, alpha: 1)
    private static let subtle = UIColor(red: 136 / 255, green: 136 / 255, blue: 136 / 255, alpha: 1)
    private static let forest = UIColor(red: 15 / 255, green: 61 / 255, blue: 46 / 255, alpha: 1)
}
#endif

/// Isolated from `AppSession` so `@Observable` invalidation does not recreate the UIKit password field every render.
private struct AuthPasswordInputRow: View {
    @Binding var password: String
    var label: String = "Password"

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(BespokeFont.inter(15.2, weight: .bold))
                .foregroundStyle(BespokeColor.fieldLabel)
            Group {
                #if canImport(UIKit)
                AuthSecureUITextField(text: $password, placeholder: label)
                    .id("authSecurePassword-\(label)")
                #else
                SecureField(label, text: $password)
                    .font(BespokeFont.inter(16, weight: .regular))
                    .foregroundStyle(BespokeColor.bodyText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                #endif
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
            .background(BespokeColor.inputSurface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(BespokeColor.forest.opacity(0.18), lineWidth: 1)
            )
        }
    }
}

#if canImport(UIKit)
private func dismissAuthKeyboard() {
    UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
}
#endif

// MARK: - Auth modal (`auth-page.scss` + forms)

private struct AuthModalView: View {
    @Environment(AppSession.self) private var session
    @State private var mode: AuthTab = .login
    @State private var loginView: LoginView = .login
    @State private var registerStep: RegisterStep = .form
    @State private var username = ""
    @State private var email = ""
    @State private var password = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var hasAcceptedLegalTerms = false
    @State private var resendMessage: String?
    @State private var successMessage: String?
    @State private var forgotEmailTouched = false
    @State private var resetPasswordTouched = false

    private static let privacyPolicyURL = URL(string: "https://www.bespokedua.com/privacy-policy")!
    private static let termsOfUseURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    private enum AuthTab {
        case login, register
    }

    private enum LoginView {
        case login, forgot, resetSent, setPassword
    }

    private enum RegisterStep {
        case form, verify
    }

    private var showingPasswordRecovery: Bool {
        session.passwordRecoveryPending || loginView == .setPassword
    }

    private var supabaseAuth: Bool {
        SupabaseConfig.isConfigured
    }

    var body: some View {
        ZStack {
            BespokeColor.authBackdrop
                .ignoresSafeArea()
                .background(.ultraThinMaterial.opacity(0.2))
                .onTapGesture {
                    session.dismissAuth()
                }

            VStack(spacing: 0) {
                Spacer(minLength: 0)
                VStack(spacing: 0) {
                if mode == .register, registerStep == .verify {
                    HStack {
                        Button {
                            editRegistration()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 14, weight: .semibold))
                                Text("Edit registration")
                                    .font(BespokeFont.inter(15, weight: .semibold))
                            }
                            .foregroundStyle(BespokeColor.forest)
                        }
                        .buttonStyle(BespokePlainButtonStyle())
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
                    .padding(.bottom, 4)
                } else if !showingPasswordRecovery, loginView != .forgot, loginView != .resetSent {
                    HStack(spacing: 6) {
                        authToggleButton(title: "Login", tab: .login)
                        authToggleButton(title: "Register", tab: .register)
                    }
                    .padding(6)
                    .background(BespokeColor.authToggleBg)
                    .clipShape(RoundedRectangle(cornerRadius: 999, style: .continuous))
                    .padding(.horizontal, 6)
                    .padding(.top, 6)
                }

                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        if mode == .register, registerStep == .verify {
                            emailVerificationStepContent
                        } else if mode == .login, showingPasswordRecovery {
                            setPasswordContent
                        } else if mode == .login, loginView == .forgot {
                            forgotPasswordContent
                        } else if mode == .login, loginView == .resetSent {
                            resetSentContent
                        } else {
                            if mode == .login {
                                Text("Login")
                                    .font(BespokeFont.inter(29.6, weight: .semibold))
                                    .foregroundStyle(BespokeColor.forest)
                            } else {
                                Text("Create an Account")
                                    .font(BespokeFont.inter(29.6, weight: .semibold))
                                    .foregroundStyle(BespokeColor.forest)
                            }

                            if mode == .register {
                                authField(
                                    label: "Username",
                                    content: {
                                        TextField("", text: $username, prompt: Text("Username").foregroundStyle(BespokeColor.subtle))
                                            .textContentType(.username)
                                            .autocorrectionDisabled()
                                    }
                                )
                                Text(UsernameRules.hint)
                                    .font(BespokeFont.inter(12.8, weight: .regular))
                                    .foregroundStyle(BespokeColor.fieldLabel.opacity(0.65))
                            }

                            authField(
                                label: "Email",
                                content: {
                                    TextField("", text: $email, prompt: Text("Email").foregroundStyle(BespokeColor.subtle))
                                        .textContentType(.emailAddress)
                                        .keyboardType(.emailAddress)
                                        .textInputAutocapitalization(.never)
                                        .autocorrectionDisabled()
                                }
                            )

                            AuthPasswordInputRow(password: $password)

                            VStack(alignment: .leading, spacing: 10) {
                                Button {
                                    hasAcceptedLegalTerms.toggle()
                                } label: {
                                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                                        Image(systemName: hasAcceptedLegalTerms ? "checkmark.square.fill" : "square")
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundStyle(hasAcceptedLegalTerms ? BespokeColor.forest : BespokeColor.fieldLabel.opacity(0.8))
                                        Text("I agree to the")
                                            .font(BespokeFont.inter(14, weight: .regular))
                                            .foregroundStyle(BespokeColor.bodyText)
                                    }
                                }
                                .buttonStyle(BespokePlainButtonStyle())

                                HStack(spacing: 4) {
                                    Link("Terms and Conditions", destination: Self.termsOfUseURL)
                                    Text("and")
                                        .foregroundStyle(BespokeColor.bodyText)
                                    Link("Privacy Policy", destination: Self.privacyPolicyURL)
                                }
                                .font(BespokeFont.inter(13.5, weight: .semibold))
                                .foregroundStyle(BespokeColor.forest)
                            }
                        }

                        if let successMessage {
                            authSuccessAlert(successMessage)
                        }

                        if let err = session.authError {
                            authErrorAlert(err)
                        }

                        if mode == .login, loginView == .login, !(mode == .register && registerStep == .verify) {
                            authPrimaryButton(title: "Login", disabled: session.authInFlight || !canSubmitLogin) {
                                Task { await submit() }
                            }

                            if supabaseAuth {
                                Button {
                                    showForgotPassword()
                                } label: {
                                    Text("Forgot password?")
                                        .font(BespokeFont.inter(14.4, weight: .semibold))
                                        .foregroundStyle(Color(red: 29 / 255, green: 100 / 255, blue: 58 / 255))
                                        .underline(true, color: Color(red: 29 / 255, green: 100 / 255, blue: 58 / 255))
                                        .frame(maxWidth: .infinity)
                                }
                                .buttonStyle(BespokePlainButtonStyle())
                                .padding(.top, 4)
                            }
                        } else if mode == .register, registerStep == .form {
                            authPrimaryButton(title: "Register", disabled: session.authInFlight || !canSubmitRegister) {
                                Task { await submit() }
                            }
                        }
                    }
                    .padding(24)
                }
                .scrollDismissesKeyboard(.interactively)

                if let user = session.currentUser {
                    HStack(alignment: .center) {
                        HStack(spacing: 0) {
                            Text("Signed in as ")
                                .font(BespokeFont.inter(15, weight: .regular))
                            Text(user.username)
                                .font(BespokeFont.inter(15, weight: .bold))
                        }
                        .foregroundStyle(BespokeColor.forest)
                        Spacer()
                        Button {
                            session.logout()
                        } label: {
                            Text("Logout")
                                .font(BespokeFont.inter(15, weight: .semibold))
                                .foregroundStyle(BespokeColor.cream)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .background(BespokeColor.forest)
                                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                        }
                        .buttonStyle(BespokePlainButtonStyle())
                    }
                    .padding(16)
                    .frame(maxWidth: .infinity)
                    .background(BespokeColor.forest.opacity(0.05))
                    .overlay(alignment: .top) {
                        Rectangle()
                            .fill(BespokeColor.forest.opacity(0.08))
                            .frame(height: 1)
                    }
                }
                }
                .frame(maxWidth: 540, maxHeight: authCardMaxHeight)
                .background(BespokeColor.authCard)
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(BespokeColor.forest.opacity(0.18), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.18), radius: 35, x: 0, y: 25)
                .padding(16)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            syncRegisterStepFromSession()
            syncLoginViewFromSession()
        }
        .onChange(of: session.pendingVerificationEmail) { _, _ in
            syncRegisterStepFromSession()
        }
        .onChange(of: session.passwordRecoveryPending) { _, _ in
            syncLoginViewFromSession()
        }
    }

    private var authCardMaxHeight: CGFloat {
        if showingPasswordRecovery { return 560 }
        if mode == .login, loginView == .resetSent { return 420 }
        if mode == .login, loginView == .forgot { return 480 }
        if mode == .login, loginView == .login { return 540 }
        if registerStep == .verify { return 560 }
        return 650
    }

    private var pendingVerificationAddress: String {
        session.pendingVerificationEmail ?? email.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    @ViewBuilder
    private var emailVerificationStepContent: some View {
        VStack(spacing: 22) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [
                                BespokeColor.forest.opacity(0.14),
                                BespokeColor.gold.opacity(0.22),
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 72, height: 72)
                Image(systemName: "envelope.badge.fill")
                    .font(.system(size: 32, weight: .medium))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(BespokeColor.forest, BespokeColor.gold)
            }
            .frame(maxWidth: .infinity)

            VStack(spacing: 8) {
                Text("Check your email")
                    .font(BespokeFont.display(26))
                    .foregroundStyle(BespokeColor.forest)
                    .multilineTextAlignment(.center)
                Text("We sent a confirmation link to finish creating your account.")
                    .font(BespokeFont.inter(15, weight: .regular))
                    .foregroundStyle(BespokeColor.muted)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)

            VStack(alignment: .leading, spacing: 6) {
                Text("Sent to")
                    .font(BespokeFont.inter(12, weight: .semibold))
                    .foregroundStyle(BespokeColor.fieldLabel.opacity(0.85))
                    .textCase(.uppercase)
                    .tracking(0.6)
                Text(pendingVerificationAddress)
                    .font(BespokeFont.inter(16, weight: .semibold))
                    .foregroundStyle(BespokeColor.forest)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(16)
            .background(BespokeColor.inputSurface)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(BespokeColor.forest.opacity(0.2), lineWidth: 1)
            )

            VStack(alignment: .leading, spacing: 14) {
                verificationInstructionRow(
                    number: 1,
                    title: "Open your inbox",
                    detail: "Check spam or promotions if you don’t see it within a few minutes."
                )
                verificationInstructionRow(
                    number: 2,
                    title: "Tap the confirmation link",
                    detail: "The email is from Bespoke Dua — one tap verifies your address."
                )
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(BespokeColor.forest.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(BespokeColor.forest.opacity(0.1), lineWidth: 1)
            )

            if let resendMessage {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(BespokeColor.forest)
                    Text(resendMessage)
                        .font(BespokeFont.inter(14, weight: .semibold))
                        .foregroundStyle(BespokeColor.fieldLabel)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(BespokeColor.forest.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }

            VStack(spacing: 10) {
                Button {
                    Task { await resendVerification() }
                } label: {
                    Group {
                        if session.authInFlight {
                            HStack(spacing: 10) {
                                ProgressView()
                                    .tint(BespokeColor.cream)
                                Text("Sending…")
                            }
                        } else {
                            Text("Resend confirmation email")
                        }
                    }
                    .font(BespokeFont.inter(16, weight: .semibold))
                    .foregroundStyle(BespokeColor.cream)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 15)
                    .background(BespokeColor.forest)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(BespokePlainButtonStyle())
                .disabled(session.authInFlight)

                Button {
                    editRegistration()
                } label: {
                    Text("Use a different email")
                        .font(BespokeFont.inter(15, weight: .semibold))
                        .foregroundStyle(BespokeColor.forest)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
                .tint(BespokeColor.forest)
                .disabled(session.authInFlight)
            }
        }
    }

    private func verificationInstructionRow(number: Int, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(number)")
                .font(BespokeFont.inter(14, weight: .bold))
                .foregroundStyle(BespokeColor.cream)
                .frame(width: 28, height: 28)
                .background(BespokeColor.forest)
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(BespokeFont.inter(15, weight: .semibold))
                    .foregroundStyle(BespokeColor.forest)
                Text(detail)
                    .font(BespokeFont.inter(13.5, weight: .regular))
                    .foregroundStyle(BespokeColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    @ViewBuilder
    private var forgotPasswordContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Reset password")
                .font(BespokeFont.inter(29.6, weight: .semibold))
                .foregroundStyle(BespokeColor.forest)

            Text("Enter your email and we’ll send you a link to reset your password.")
                .font(BespokeFont.inter(15.2, weight: .regular))
                .foregroundStyle(Color(red: 38 / 255, green: 74 / 255, blue: 56 / 255).opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)

            authField(
                label: "Email",
                content: {
                    TextField("", text: $email, prompt: Text("Email").foregroundStyle(BespokeColor.subtle))
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onChange(of: email) { _, _ in
                            session.authError = nil
                            successMessage = nil
                        }
                }
            )

            if let msg = forgotEmailErrorMessage {
                authFieldError(msg)
            }

            authPrimaryButton(title: "Send reset link", disabled: session.authInFlight || !canSendResetEmail) {
                Task { await sendResetEmail() }
            }

            authSecondaryButton(title: "Back to login", disabled: session.authInFlight) {
                backToLogin()
            }
        }
    }

    @ViewBuilder
    private var resetSentContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Check your email")
                .font(BespokeFont.inter(29.6, weight: .semibold))
                .foregroundStyle(BespokeColor.forest)

            (
                Text("If an account exists for ")
                + Text(email.trimmingCharacters(in: .whitespacesAndNewlines)).bold()
                + Text(", you’ll receive a password reset link shortly. Check spam or promotions if you don’t see it.")
            )
            .font(BespokeFont.inter(15.2, weight: .regular))
            .foregroundStyle(Color(red: 38 / 255, green: 74 / 255, blue: 56 / 255).opacity(0.85))
            .fixedSize(horizontal: false, vertical: true)

            authSecondaryButton(title: "Back to login", disabled: false) {
                backToLogin()
            }
        }
    }

    @ViewBuilder
    private var setPasswordContent: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Set a new password")
                .font(BespokeFont.inter(29.6, weight: .semibold))
                .foregroundStyle(BespokeColor.forest)

            Text("Choose a new password for your account. You’ll be signed in once it’s saved.")
                .font(BespokeFont.inter(15.2, weight: .regular))
                .foregroundStyle(Color(red: 38 / 255, green: 74 / 255, blue: 56 / 255).opacity(0.85))
                .fixedSize(horizontal: false, vertical: true)

            AuthPasswordInputRow(password: $newPassword, label: "New password")
                .onChange(of: newPassword) { _, _ in
                    session.authError = nil
                    successMessage = nil
                }

            if let msg = newPasswordErrorMessage {
                authFieldError(msg)
            }

            AuthPasswordInputRow(password: $confirmPassword, label: "Confirm password")
                .onChange(of: confirmPassword) { _, _ in
                    session.authError = nil
                    successMessage = nil
                }

            if let msg = confirmPasswordErrorMessage {
                authFieldError(msg)
            }

            authPrimaryButton(title: "Save password", disabled: session.authInFlight || !canSaveNewPassword) {
                Task { await saveNewPassword() }
            }

            authSecondaryButton(title: "Cancel", disabled: session.authInFlight) {
                cancelPasswordReset()
            }
        }
    }

    private func syncRegisterStepFromSession() {
        if session.awaitingEmailVerification {
            mode = .register
            registerStep = .verify
        }
    }

    private func syncLoginViewFromSession() {
        if session.passwordRecoveryPending {
            mode = .login
            loginView = .setPassword
        }
    }

    private func showForgotPassword() {
        successMessage = nil
        session.authError = nil
        loginView = .forgot
    }

    private func backToLogin() {
        successMessage = nil
        session.authError = nil
        loginView = .login
    }

    private func cancelPasswordReset() {
        session.clearPasswordRecovery()
        newPassword = ""
        confirmPassword = ""
        resetPasswordTouched = false
        backToLogin()
    }

    private func sendResetEmail() async {
        forgotEmailTouched = true
        successMessage = nil
        session.authError = nil

        let e = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !e.isEmpty, EmailFormatValidator.isValid(e) else { return }

        #if canImport(UIKit)
        dismissAuthKeyboard()
        #endif

        if await session.requestPasswordReset(email: e) {
            loginView = .resetSent
        }
    }

    private func saveNewPassword() async {
        resetPasswordTouched = true
        successMessage = nil
        session.authError = nil

        guard canSaveNewPassword else { return }

        #if canImport(UIKit)
        dismissAuthKeyboard()
        #endif

        if await session.completePasswordReset(password: newPassword) {
            if let username = session.currentUser?.username {
                successMessage = "Password updated. Welcome back, \(username)!"
            } else {
                successMessage = "Password updated."
            }
            newPassword = ""
            confirmPassword = ""
            resetPasswordTouched = false
            loginView = .login
        }
    }

    private var canSendResetEmail: Bool {
        EmailFormatValidator.isValid(email.trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private var canSaveNewPassword: Bool {
        newPasswordErrorMessage == nil && confirmPasswordErrorMessage == nil &&
            newPassword.count >= 6 && !newPassword.isEmpty && !confirmPassword.isEmpty
    }

    private var forgotEmailErrorMessage: String? {
        guard forgotEmailTouched else { return nil }
        let e = email.trimmingCharacters(in: .whitespacesAndNewlines)
        if e.isEmpty { return "Email is required." }
        if !EmailFormatValidator.isValid(e) { return "Enter a valid email address." }
        return nil
    }

    private var newPasswordErrorMessage: String? {
        guard resetPasswordTouched else { return nil }
        if newPassword.isEmpty { return "Password is required." }
        if newPassword.count < 6 { return "Password must be at least 6 characters." }
        return nil
    }

    private var confirmPasswordErrorMessage: String? {
        guard resetPasswordTouched else { return nil }
        if confirmPassword.isEmpty { return "Please confirm your password." }
        if newPassword != confirmPassword { return "Passwords do not match." }
        return nil
    }

    private var canSubmitLogin: Bool {
        let e = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard EmailFormatValidator.isValid(e), !password.isEmpty, hasAcceptedLegalTerms else { return false }
        return true
    }

    private var canSubmitRegister: Bool {
        let e = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard EmailFormatValidator.isValid(e), !password.isEmpty, hasAcceptedLegalTerms else { return false }
        return !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func authPrimaryButton(title: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button {
            #if canImport(UIKit)
            dismissAuthKeyboard()
            #endif
            action()
        } label: {
            Text(title)
                .font(BespokeFont.inter(17, weight: .bold))
                .foregroundStyle(BespokeColor.cream)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 17)
                .background(BespokeColor.forest)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .bespokeButtonHitArea(cornerRadius: 16)
        }
        .buttonStyle(BespokePlainButtonStyle())
        .disabled(disabled)
        .opacity(disabled ? 0.65 : 1)
    }

    private func authSecondaryButton(title: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(BespokeFont.inter(16, weight: .semibold))
                .foregroundStyle(BespokeColor.forest)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(BespokeColor.forest.opacity(0.22), lineWidth: 1)
                )
                .bespokeButtonHitArea(cornerRadius: 16)
        }
        .buttonStyle(BespokePlainButtonStyle())
        .disabled(disabled)
        .opacity(disabled ? 0.65 : 1)
        .padding(.top, 4)
    }

    private func authFieldError(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Text("!")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Color(red: 181 / 255, green: 47 / 255, blue: 49 / 255))
                .clipShape(Circle())
            Text(message)
                .font(BespokeFont.inter(13.5, weight: .semibold))
                .foregroundStyle(Color(red: 107 / 255, green: 29 / 255, blue: 31 / 255))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func authErrorAlert(_ err: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("!")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(Color(red: 181 / 255, green: 47 / 255, blue: 49 / 255))
                .clipShape(Circle())
            Text(err)
                .font(BespokeFont.inter(14.7, weight: .semibold))
                .foregroundStyle(Color(red: 107 / 255, green: 29 / 255, blue: 31 / 255))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 181 / 255, green: 47 / 255, blue: 49 / 255).opacity(0.1),
                    Color(red: 181 / 255, green: 47 / 255, blue: 49 / 255).opacity(0.04),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color(red: 181 / 255, green: 47 / 255, blue: 49 / 255).opacity(0.28), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func authSuccessAlert(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text("✓")
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 24, height: 24)
                .background(BespokeColor.forest)
                .clipShape(Circle())
            Text(message)
                .font(BespokeFont.inter(14.7, weight: .semibold))
                .foregroundStyle(BespokeColor.forest)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BespokeColor.forest.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(BespokeColor.forest.opacity(0.22), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func editRegistration() {
        session.clearEmailVerificationStage()
        registerStep = .form
        resendMessage = nil
        session.authError = nil
    }

    private func resendVerification() async {
        resendMessage = nil
        session.authError = nil
        if await session.resendVerificationEmail() {
            resendMessage = "Email sent."
        }
    }

    private func authToggleButton(title: String, tab: AuthTab) -> some View {
        Button {
            #if canImport(UIKit)
            dismissAuthKeyboard()
            #endif
            mode = tab
            if tab == .login {
                registerStep = .form
                if !session.passwordRecoveryPending {
                    loginView = .login
                }
            } else {
                syncRegisterStepFromSession()
                loginView = .login
            }
            successMessage = nil
            session.authError = nil
        } label: {
            Text(title)
                .font(BespokeFont.inter(15, weight: .bold))
                .foregroundStyle(mode == tab ? Color.white : BespokeColor.forest)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(mode == tab ? BespokeColor.gold : Color.clear)
                .clipShape(Capsule())
                .bespokeButtonHitArea(Capsule())
        }
        .buttonStyle(BespokePlainButtonStyle())
    }

    private func authField<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(BespokeFont.inter(15.2, weight: .bold))
                .foregroundStyle(BespokeColor.fieldLabel)
            content()
                .font(BespokeFont.inter(16, weight: .regular))
                .foregroundStyle(BespokeColor.bodyText)
                .padding(16)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .background(BespokeColor.inputSurface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(BespokeColor.forest.opacity(0.18), lineWidth: 1)
                )
        }
    }

    private func submit() async {
        let e = email.trimmingCharacters(in: .whitespacesAndNewlines)
        let p = password
        guard hasAcceptedLegalTerms else {
            session.authError = "Please agree to the Terms and Conditions and Privacy Policy."
            return
        }
        guard EmailFormatValidator.isValid(e) else {
            session.authError = EmailFormatValidator.invalidMessage
            return
        }
        successMessage = nil
        switch mode {
        case .login:
            await session.login(email: e, password: p)
            if session.authError != nil {
                password = ""
            }
        case .register:
            let result = await session.register(
                username: username.trimmingCharacters(in: .whitespacesAndNewlines),
                email: e,
                password: p
            )
            switch result {
            case .signedIn:
                registerStep = .form
                resendMessage = nil
            case .awaitingVerification:
                registerStep = .verify
                resendMessage = nil
            case .failed:
                break
            }
        }
    }
}


private struct HomeRecentSearchRow: View {
    let symbolName: String
    let iconBackground: Color
    let iconForeground: Color
    let title: String
    let queryText: String
    let statusText: String
    let showDivider: Bool
    let action: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(iconBackground)
                        .frame(width: 32, height: 32)

                    Image(systemName: symbolName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(iconForeground)
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(BespokeFont.inter(14, weight: .semibold))
                        .foregroundStyle(BespokeColor.forest)

                    Text("“\(queryText)”")
                        .font(BespokeFont.inter(13, weight: .regular))
                        .foregroundStyle(BespokeColor.muted)
                        .lineLimit(1)
                        .truncationMode(.tail)

                    Text(statusText)
                        .font(BespokeFont.inter(11, weight: .regular))
                        .foregroundStyle(BespokeColor.subtle)
                }

                Spacer(minLength: 8)

                Button(action: action) {
                    Text("View")
                        .font(BespokeFont.inter(12, weight: .semibold))
                        .foregroundStyle(BespokeColor.homeGold)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(BespokeColor.homeGold.opacity(0.1))
                        .clipShape(Capsule())
                        .bespokeButtonHitArea(cornerRadius: 16)
                }
                .buttonStyle(BespokePlainButtonStyle())
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)

            if showDivider {
                Rectangle()
                    .fill(BespokeColor.sectionRule.opacity(0.85))
                    .frame(height: 1)
                    .padding(.leading, 58)
            }
        }
    }
}

private struct HomeHeroStarMark: View {
    var body: some View {
        HomeHeroStarShape()
            .fill(BespokeColor.homeGold.opacity(0.14))
            .overlay {
                HomeHeroStarShape()
                    .stroke(BespokeColor.homeGold, lineWidth: 1.15)
            }
            .frame(width: 14.5, height: 17)
            .accessibilityHidden(true)
    }
}

private struct HomeHeroStarShape: Shape {
    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let pinchX = rect.width * 0.14
        let pinchY = rect.height * 0.13

        let top = CGPoint(x: center.x, y: rect.minY)
        let right = CGPoint(x: rect.maxX, y: center.y)
        let bottom = CGPoint(x: center.x, y: rect.maxY)
        let left = CGPoint(x: rect.minX, y: center.y)

        var path = Path()
        path.move(to: top)
        path.addQuadCurve(
            to: right,
            control: CGPoint(x: center.x + pinchX, y: center.y - pinchY)
        )
        path.addQuadCurve(
            to: bottom,
            control: CGPoint(x: center.x + pinchX, y: center.y + pinchY)
        )
        path.addQuadCurve(
            to: left,
            control: CGPoint(x: center.x - pinchX, y: center.y + pinchY)
        )
        path.addQuadCurve(
            to: top,
            control: CGPoint(x: center.x - pinchX, y: center.y - pinchY)
        )
        path.closeSubpath()
        return path
    }
}

private struct HomeNameOfTheDayCard: View {
    let name: AllahNameDetail
    var onReflect: (() -> Void)?

    static var loading: some View {
        HomeNameOfTheDayCardShell {
            VStack(spacing: 14) {
                Text("Name of the Day")
                    .font(BespokeFont.display(18))
                    .foregroundStyle(BespokeColor.forest.opacity(0.85))

                ProgressView()
                    .tint(BespokeColor.forest)

                Text("Loading today's name…")
                    .font(BespokeFont.inter(14, weight: .regular))
                    .foregroundStyle(BespokeColor.muted)
            }
            .multilineTextAlignment(.center)
        }
    }

    static var dhikrFallback: some View {
        HomeNameOfTheDayDhikrFallback()
    }

    var body: some View {
        HomeNameOfTheDayCardShell {
            VStack(spacing: 16) {
                Text("Name of the Day")
                    .font(BespokeFont.display(18))
                    .foregroundStyle(BespokeColor.forest.opacity(0.85))

                Text(name.arabic)
                    .font(BespokeFont.display(38))
                    .foregroundStyle(BespokeColor.forest)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .environment(\.layoutDirection, .rightToLeft)

                Text(name.transliteration)
                    .font(BespokeFont.inter(16, weight: .semibold))
                    .foregroundStyle(BespokeColor.nameGold)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                Text(name.translation)
                    .font(BespokeFont.display(20))
                    .foregroundStyle(BespokeColor.forest)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                if let onReflect {
                    Button(action: onReflect) {
                        Text("Reflect on this name")
                            .font(BespokeFont.inter(13, weight: .semibold))
                            .foregroundStyle(BespokeColor.forest)
                            .padding(.horizontal, 18)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.72))
                            .clipShape(Capsule())
                            .overlay {
                                Capsule()
                                    .stroke(BespokeColor.forest.opacity(0.14), lineWidth: 1)
                            }
                            .bespokeButtonHitArea(cornerRadius: 20)
                    }
                    .buttonStyle(BespokePlainButtonStyle())
                    .padding(.top, 4)
                }
            }
            .multilineTextAlignment(.center)
        }
    }
}

private struct HomeNameOfTheDayDhikrFallback: View {
    @State private var selectedIndex = 0

    private let dhikrItems = CraftingDhikr.carousel
    private let rotationInterval: TimeInterval = 3.5

    var body: some View {
        HomeNameOfTheDayCardShell {
            VStack(spacing: 10) {
                Text("Name of the Day")
                    .font(BespokeFont.display(16))
                    .foregroundStyle(BespokeColor.forest.opacity(0.85))

                dhikrContent(for: dhikrItems[selectedIndex])
                    .id(dhikrItems[selectedIndex].id)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))
                    .frame(maxHeight: 118)

                paginationDots
            }
            .multilineTextAlignment(.center)
        }
        .task {
            await rotateDhikr()
        }
    }

    @ViewBuilder
    private func dhikrContent(for item: CraftingDhikr) -> some View {
        VStack(spacing: 6) {
            Text(item.arabic)
                .font(BespokeFont.display(24))
                .foregroundStyle(BespokeColor.forest)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .lineLimit(3)
                .minimumScaleFactor(0.6)
                .environment(\.layoutDirection, .rightToLeft)

            Text(item.transliteration)
                .font(BespokeFont.inter(13, weight: .semibold))
                .foregroundStyle(BespokeColor.nameGold)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(item.english)
                .font(BespokeFont.inter(13, weight: .regular))
                .foregroundStyle(BespokeColor.forest)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
        }
    }

    private var paginationDots: some View {
        HStack(spacing: 6) {
            ForEach(dhikrItems.indices, id: \.self) { index in
                Circle()
                    .fill(index == selectedIndex ? BespokeColor.forest : BespokeColor.forest.opacity(0.2))
                    .frame(width: index == selectedIndex ? 7 : 5, height: index == selectedIndex ? 7 : 5)
            }
        }
        .padding(.top, 2)
    }

    @MainActor
    private func rotateDhikr() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(rotationInterval))
            withAnimation(.easeInOut(duration: 0.45)) {
                selectedIndex = (selectedIndex + 1) % dhikrItems.count
            }
        }
    }
}

private struct HomeNameOfTheDayCardShell<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack {
            Image("NameOfTheDayFrame")
                .resizable()
                .renderingMode(.original)
                .scaledToFit()
                .frame(maxWidth: .infinity)
                .accessibilityHidden(true)

            content()
                .padding(.horizontal, 44)
                .padding(.vertical, 52)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct ReflectionModalOverlay: View {
    @Binding var isPresented: Bool
    @Binding var explanations: [ExplanationModel]

    private var modalBinding: Binding<Bool> {
        Binding(
            get: { isPresented },
            set: { newValue in
                isPresented = newValue
                if !newValue { explanations = [] }
            }
        )
    }

    var body: some View {
        BespokeCardModalView(isPresented: modalBinding, title: "Reflection") {
            VStack(alignment: .leading, spacing: 20) {
                ForEach(explanations) { exp in
                    VStack(alignment: .leading, spacing: 8) {
                        Text(exp.name)
                            .font(BespokeFont.inter(16, weight: .semibold))
                            .foregroundStyle(BespokeColor.nameGold)
                        Text(exp.explanation)
                            .font(BespokeFont.inter(15, weight: .regular))
                            .foregroundStyle(BespokeColor.bodyText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 4)
                }
            }
        }
        .transition(.opacity)
    }
}

private struct NameReflectionModalOverlay: View {
    @Binding var isPresented: Bool
    let nameOfTheDay: AllahNameDetail

    var body: some View {
        BespokeCardModalView(
            isPresented: $isPresented,
            title: nameOfTheDay.transliteration
        ) {
            VStack(spacing: 18) {
                Text(nameOfTheDay.arabic)
                    .font(BespokeFont.display(34))
                    .foregroundStyle(BespokeColor.forest)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .environment(\.layoutDirection, .rightToLeft)

                Text(nameOfTheDay.translation)
                    .font(BespokeFont.inter(17, weight: .semibold))
                    .foregroundStyle(BespokeColor.nameGold)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)

                Text(nameOfTheDay.meaning.isEmpty ? nameOfTheDay.translation : nameOfTheDay.meaning)
                    .font(BespokeFont.inter(15, weight: .regular))
                    .foregroundStyle(BespokeColor.bodyText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(4)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity)
            }
        }
        .transition(.opacity)
    }
}

private extension View {
    func homeListChrome(cornerRadius: CGFloat) -> some View {
        background(Color.white.opacity(0.82))
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(BespokeColor.cardBorder.opacity(0.65), lineWidth: 1)
            }
    }

    @ViewBuilder
    func disablingTabBarMinimize() -> some View {
        if #available(iOS 26.0, *) {
            tabBarMinimizeBehavior(.never)
        } else {
            self
        }
    }
}

private enum HomeScrollIdentity {
    static let root = "home-dashboard-scroll"
}

private struct HomeMainNavigationChrome: ViewModifier {
    let showsMainBar: Bool
    let title: String

    func body(content: Content) -> some View {
        if showsMainBar {
            content
                .bespokeMainNavigationToolbar(title: title)
        } else {
            content
                .toolbar(.hidden, for: .navigationBar)
        }
    }
}

#Preview {
    ContentView()
        .environment(AppSession())
        .environment(SubscriptionManager())
}
