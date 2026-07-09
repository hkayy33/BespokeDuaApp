import SwiftUI

private struct PresentSaveDuaModalKey: EnvironmentKey {
    static var defaultValue: ((DuaReceiver) -> Void)? { nil }
}

extension EnvironmentValues {
    var presentSaveDuaModal: ((DuaReceiver) -> Void)? {
        get { self[PresentSaveDuaModalKey.self] }
        set { self[PresentSaveDuaModalKey.self] = newValue }
    }
}

struct SunnahDuasView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(AppSession.self) private var session
    @Environment(SubscriptionManager.self) private var subscriptionManager
    @Environment(\.mainTabBarClearance) private var mainTabBarClearance
    @Environment(\.presentSaveDuaModal) private var presentSaveDuaModal
    @Environment(\.presentUpgradeModalForDailyLimit) private var presentUpgradeModalForDailyLimit

    var restoreSnapshot: HomeRecentActivity.SunnahSnapshot?
    var onActivityChanged: (() -> Void)?

    @State private var requestText = ""
    @State private var response: SunnahDuaRecommendResponse?
    @State private var recommendInFlight = false
    @State private var recommendError: String?
    @State private var emptyRequestWarning = false
    @State private var savedItemKeys: Set<String> = []
    @State private var didApplyRestore = false
    @State private var dailyQuotaRefresh = 0
    @FocusState private var fieldFocused: Bool

    private let client = BespokeAPIClient()

    init(
        restoreSnapshot: HomeRecentActivity.SunnahSnapshot? = nil,
        onActivityChanged: (() -> Void)? = nil
    ) {
        self.restoreSnapshot = restoreSnapshot
        self.onActivityChanged = onActivityChanged
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                inputSection

                if let recommendError {
                    errorBanner(recommendError)
                        .padding(.horizontal, BespokeLayout.libraryHorizontalPadding)
                        .padding(.top, 8)
                }

                resultsSection
            }
            .bespokeLibraryContentFrame()
            .padding(.bottom, 24 + mainTabBarClearance)
        }
        .scrollIndicators(.hidden, axes: .vertical)
        .scrollDismissesKeyboard(.interactively)
        .background(BespokeColor.pageBackground)
        .toolbar(.hidden, for: .navigationBar)
        .navigationBarBackButtonHidden(true)
        .safeAreaInset(edge: .top, spacing: 0) {
            BespokeFlowBackHeader(title: "Sunnah Duas", onBack: goBack)
        }
        .bespokeEdgeBackNavigation(hidesNavigationBar: true)
        .onAppear {
            applyRestoreIfNeeded()
            session.scheduleSavedDuasRefresh()
            syncSavedVisualsFromSession()
        }
        .onDisappear {
            persistSunnahSession()
        }
        .onChange(of: session.savedDuas) { _, _ in
            syncSavedVisualsFromSession()
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                dailyQuotaRefresh += 1
            }
        }
    }

    /// Free tier has used today’s allowance; primary CTA becomes Upgrade instead of Find.
    private var shouldShowUpgradeInsteadOfFind: Bool {
        guard session.isLoggedIn, let uid = session.currentUser?.userId else { return false }
        guard !subscriptionManager.isSubscribed else { return false }
        return !DailyGenerationQuota.hasRemainingFreeGenerations(userId: uid)
    }

    private func goBack() {
        persistSunnahSession()
        dismiss()
    }

    private func applyRestoreIfNeeded() {
        guard !didApplyRestore, let restoreSnapshot else { return }
        didApplyRestore = true
        requestText = restoreSnapshot.requestText
        if !restoreSnapshot.categories.isEmpty {
            response = HomeRecentActivity.sunnahResponse(from: restoreSnapshot)
        }
        if restoreSnapshot.isGenerating && response == nil && !recommendInFlight {
            let trimmed = restoreSnapshot.requestText.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return }
            recommendError = nil
            Task {
                await runRecommend(trimmed: trimmed)
            }
        }
    }

    private func persistSunnahSession() {
        guard let uid = session.currentUser?.userId else { return }
        let trimmed = requestText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        if recommendInFlight {
            HomeRecentActivity.saveSunnah(
                userId: uid,
                requestText: trimmed,
                response: response,
                isGenerating: true
            )
        } else if response != nil {
            HomeRecentActivity.saveSunnah(
                userId: uid,
                requestText: trimmed,
                response: response,
                isGenerating: false
            )
        }
        onActivityChanged?()
    }

    private var inputSection: some View {
        VStack(spacing: 20) {
            Text("Share how you feel")
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
                ZStack(alignment: .topLeading) {
                    if requestText.isEmpty {
                        Text("I feel..")
                            .font(BespokeFont.inter(16, weight: .regular))
                            .foregroundStyle(BespokeColor.subtle)
                            .padding(.top, 12)
                            .padding(.leading, 10)
                            .allowsHitTesting(false)
                    }
                    TextEditor(text: $requestText)
                        .font(BespokeFont.inter(16, weight: .regular))
                        .foregroundStyle(BespokeColor.bodyText)
                        .scrollContentBackground(.hidden)
                        .frame(minHeight: 120)
                        .focused($fieldFocused)
                }
                .padding(12)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(
                            emptyRequestWarning ? BespokeColor.error : (fieldFocused ? BespokeColor.gold : BespokeColor.inputBorder),
                            lineWidth: emptyRequestWarning || fieldFocused ? 2 : 1
                        )
                )

                Text("Example: “I feel anxious about my exams…”")
                    .font(BespokeFont.inter(13, weight: .regular))
                    .foregroundStyle(BespokeColor.muted)

                if emptyRequestWarning {
                    Text("Please describe how you feel or what you need.")
                        .font(BespokeFont.inter(13, weight: .regular))
                        .foregroundStyle(BespokeColor.error)
                }
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
                if shouldShowUpgradeInsteadOfFind && !recommendInFlight {
                    Button {
                        presentUpgradeModalForDailyLimit?()
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
                    Button(action: submitRecommend) {
                        Group {
                            if recommendInFlight {
                                HStack(spacing: 10) {
                                    ProgressView()
                                        .tint(.white)
                                    Text("Finding duas…")
                                        .font(BespokeFont.inter(17, weight: .semibold))
                                }
                            } else {
                                Text("Find duas")
                                    .font(BespokeFont.inter(17, weight: .semibold))
                            }
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(LinearGradient.bespokeGold)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .bespokeButtonHitArea(cornerRadius: 16)
                        .shadow(color: recommendInFlight ? .clear : .black.opacity(0.14), radius: 12, x: 0, y: 6)
                    }
                    .buttonStyle(BespokePlainButtonStyle())
                    .disabled(recommendInFlight)
                    .opacity(recommendInFlight ? 0.72 : 1)
                }
            }
        }
        .padding(.horizontal, BespokeLayout.libraryHorizontalPadding)
    }

    @ViewBuilder
    private var resultsSection: some View {
        if recommendInFlight && response == nil {
            VStack(alignment: .leading, spacing: 16) {
                Text("Preparing your duas")
                    .font(BespokeFont.inter(20, weight: .semibold))
                    .foregroundStyle(BespokeColor.forest)

                DuaCraftingDhikrCarousel(statusText: "Finding authentic duas for you…")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, BespokeLayout.libraryHorizontalPadding)
            .padding(.top, 32)
        } else if let response {
            VStack(alignment: .leading, spacing: 32) {
                VStack(alignment: .leading, spacing: 0) {
                    Rectangle()
                        .fill(BespokeColor.sectionRule)
                        .frame(maxWidth: .infinity)
                        .frame(height: 1)

                    Text("Recommended for you")
                        .font(BespokeFont.inter(20, weight: .semibold))
                        .foregroundStyle(BespokeColor.forest)
                        .padding(.top, 24)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                ForEach(response.categories) { category in
                    categorySection(category)
                }

                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        self.response = nil
                        recommendError = nil
                    }
                    if let uid = session.currentUser?.userId {
                        HomeRecentActivity.clearSunnah(userId: uid)
                    }
                    onActivityChanged?()
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
            }
            .padding(.horizontal, BespokeLayout.libraryHorizontalPadding)
            .padding(.top, 28)
        } else {
            emptyResultsHint
                .padding(.top, 32)
        }
    }

    private var emptyResultsHint: some View {
        ContentUnavailableView {
            Label("Authentic duas from the sunnah", systemImage: "book.closed.fill")
        } description: {
            Text("Describe what’s on your heart — anxiety, travel, gratitude, guidance — and we’ll suggest relevant categories with duas from authentic sources.")
                .font(BespokeFont.inter(15, weight: .regular))
                .foregroundStyle(BespokeColor.muted)
                .multilineTextAlignment(.center)
        }
        .symbolRenderingMode(.hierarchical)
        .foregroundStyle(BespokeColor.muted)
        .padding(.horizontal, BespokeLayout.libraryHorizontalPadding)
        .padding(.vertical, 28)
    }

    private func categorySection(_ category: SunnahDuaCategoryResult) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(category.name)
                .font(BespokeFont.display(22))
                .foregroundStyle(BespokeColor.forest)

            LazyVStack(spacing: 14) {
                ForEach(category.duas) { item in
                    SunnahDuaCard(
                        item: item,
                        isSavedVisual: savedItemKeys.contains(
                            SunnahDuaDisplay.savedItemKey(categoryId: category.id, duaId: item.id)
                        ),
                        onSave: { handleSaveTap(item: item, category: category) }
                    )
                }
            }
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(BespokeColor.error)
            Text(message)
                .font(BespokeFont.inter(14, weight: .regular))
                .foregroundStyle(BespokeColor.error)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(BespokeColor.error.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func submitRecommend() {
        fieldFocused = false
        guard session.isLoggedIn else {
            session.presentAuth()
            return
        }
        if shouldShowUpgradeInsteadOfFind {
            presentUpgradeModalForDailyLimit?()
            return
        }
        let trimmed = requestText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            emptyRequestWarning = true
            return
        }
        emptyRequestWarning = false
        recommendError = nil
        withAnimation(.easeInOut(duration: 0.2)) {
            response = nil
        }
        Task {
            await runRecommend(trimmed: trimmed)
        }
    }

    private func runRecommend(trimmed: String) async {
        recommendInFlight = true
        if let uid = session.currentUser?.userId {
            HomeRecentActivity.saveSunnah(
                userId: uid,
                requestText: trimmed,
                response: nil,
                isGenerating: true
            )
            onActivityChanged?()
        }
        defer { recommendInFlight = false }
        do {
            let result = try await client.recommendSunnahDuas(
                SunnahDuaRecommendRequest(
                    text: trimmed,
                    userId: session.currentUser?.userId
                )
            )
            withAnimation(.easeInOut(duration: 0.25)) {
                response = result
            }
            if let uid = session.currentUser?.userId {
                HomeRecentActivity.saveSunnah(
                    userId: uid,
                    requestText: trimmed,
                    response: result,
                    isGenerating: false
                )
                onActivityChanged?()
            }
            if !subscriptionManager.isSubscribed, let id = session.currentUser?.userId {
                DailyGenerationQuota.recordGeneration(userId: id)
                dailyQuotaRefresh += 1
            }
        } catch {
            recommendError = error.localizedDescription
            if let uid = session.currentUser?.userId {
                HomeRecentActivity.saveSunnah(
                    userId: uid,
                    requestText: trimmed,
                    response: response,
                    isGenerating: false
                )
                onActivityChanged?()
            }
        }
    }

    private func handleSaveTap(item: SunnahDuaItem, category: SunnahDuaCategoryResult) {
        guard session.currentUser?.userId != nil else {
            session.presentAuth()
            return
        }
        let key = SunnahDuaDisplay.savedItemKey(categoryId: category.id, duaId: item.id)
        if savedItemKeys.contains(key) {
            Task { await unsave(item: item, categoryId: category.id) }
            return
        }
        let receiver = SunnahDuaDisplay.duaReceiver(from: item, category: category)
        presentSaveDuaModal?(receiver)
    }

    private func unsave(item: SunnahDuaItem, categoryId: String) async {
        guard let uid = session.currentUser?.userId else { return }
        let key = SunnahDuaDisplay.savedItemKey(categoryId: categoryId, duaId: item.id)
        guard let serverId = savedServerId(for: item, categoryId: categoryId) else {
            savedItemKeys.remove(key)
            return
        }
        do {
            try await session.api().deleteSavedSunnahDua(id: serverId)
            savedItemKeys.remove(key)
            session.removeSavedDua(id: serverId)
            SavedDuaReflectionsCache.remove(userId: uid, duaId: serverId)
        } catch {
            recommendError = error.localizedDescription
        }
    }

    private func syncSavedVisualsFromSession() {
        guard let uid = session.currentUser?.userId else {
            savedItemKeys = []
            return
        }
        var keys = Set<String>()
        for row in session.savedDuas where SavedDuaDisplay.kind(from: row) == .sunnah {
            if let match = sunnahItemKey(from: row) {
                keys.insert(match)
                let receiver = SavedDuaDisplay.duaReceiver(from: row, userId: uid)
                SavedDuaReflectionsCache.store(userId: uid, duaId: row.duaId, explanations: receiver.explanations)
            }
        }
        savedItemKeys = keys
    }

    private func savedServerId(for item: SunnahDuaItem, categoryId: String) -> String? {
        session.savedDuas.first { row in
            sunnahItemKey(from: row) == SunnahDuaDisplay.savedItemKey(categoryId: categoryId, duaId: item.id)
        }?.duaId
    }

    private func sunnahItemKey(from row: SavedDuaDTO) -> String? {
        guard let payload = SunnahDuaDisplay.savedPayload(from: row) else { return nil }
        return SunnahDuaDisplay.savedItemKey(categoryId: payload.category, duaId: payload.id)
    }
}

struct SunnahDuaCard: View {
    let item: SunnahDuaItem
    var isSavedVisual: Bool
    var showsActions: Bool = true
    var reservesActionBarSpace: Bool = false
    var onSave: () -> Void

    private static let actionBarHeight: CGFloat = 28
    private static let actionBarTopPadding: CGFloat = 12

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(item.title)
                .font(BespokeFont.inter(13, weight: .semibold))
                .foregroundStyle(BespokeColor.muted)
                .fixedSize(horizontal: false, vertical: true)

            if !item.arabic.isEmpty {
                Text(item.arabic)
                    .font(BespokeFont.inter(24, weight: .regular))
                    .foregroundStyle(BespokeColor.forest)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                    .environment(\.layoutDirection, .rightToLeft)
                    .padding(.top, 12)
            }

            if !item.translation.isEmpty {
                Text(item.translation)
                    .font(BespokeFont.inter(16, weight: .regular))
                    .foregroundStyle(BespokeColor.bodyText)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 14)
            }

            if !item.transliteration.isEmpty {
                Text(item.transliteration)
                    .font(BespokeFont.inter(14, weight: .regular))
                    .italic()
                    .foregroundStyle(BespokeColor.muted)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
            }

            if !item.source.isEmpty {
                Text(item.source)
                    .font(BespokeFont.inter(12, weight: .medium))
                    .foregroundStyle(BespokeColor.nameGold)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 12)
            }

            if showsActions {
                HStack(spacing: 8) {
                    Spacer(minLength: 0)
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
                }
                .padding(.top, Self.actionBarTopPadding)
            } else if reservesActionBarSpace {
                Color.clear
                    .frame(height: Self.actionBarHeight)
                    .padding(.top, Self.actionBarTopPadding)
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
}

private struct BespokeLoaderDots: View {
    var body: some View {
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
