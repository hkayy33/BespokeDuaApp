import Auth
import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
final class AppSession {
    private let client: BespokeAPIClient
    private let supabase = SupabaseAuthService.shared
    private static let storageKey = "bespoke-dua-user"
    private static let authModeKey = "bespoke-auth-mode"
    private static let pendingEmailKey = "bespoke-pending-verification-email"

    private(set) var currentUser: AuthUser?
    private(set) var savedDuas: [SavedDuaDTO] = []
    private(set) var savedDuasLoading = false
    private(set) var savedDuasError: String?
    private(set) var duaCollections: [DuaCollectionSummaryDTO] = []
    private(set) var duaCollectionsLoading = false
    private(set) var duaCollectionsError: String?
    private(set) var duaFeedPosts: [DuaFeedPost] = []
    private(set) var duaFeedUserActivePosts: [DuaFeedPost] = []
    private(set) var duaFeedCurrentPage = 1
    private(set) var duaFeedHasMore = false
    private(set) var duaFeedLoadError: String?
    private(set) var duaFeedIsLoading = false
    private(set) var duaFeedIsSilentRefreshing = false
    private(set) var namesFeelingLabels: [FeelingLabel] = []
    private(set) var namesFeelingLabelsLoading = false
    private(set) var namesFeelingLabelsError: String?
    private(set) var isReconnecting = false
    var authInFlight = false
    var authError: String?
    var showAuthSheet = false
    private(set) var pendingVerificationEmail: String?
    private(set) var passwordRecoveryPending = false

    private var authMode: AuthMode?
    private var authStateListenerTask: Task<Void, Never>?
    private var savedDuasRefreshTask: Task<Void, Never>?
    private var duaCollectionsRefreshTask: Task<Void, Never>?
    private var duaFeedRefreshTask: Task<Void, Never>?
    private var duaFeedAutoRefreshTask: Task<Void, Never>?

    private static let savedDuasMaxAttempts = 3
    private static let savedDuasRetryDelay: Duration = .milliseconds(350)
    private static let duaCollectionsMaxAttempts = 3
    private static let duaCollectionsRetryDelay: Duration = .milliseconds(350)
    private static let duaFeedAutoRefreshInterval: Duration = .seconds(45)

    private enum AuthMode: String {
        case legacy
        case supabase
    }

    init(client: BespokeAPIClient? = nil) {
        self.client = client ?? BespokeAPIClient()
        self.currentUser = Self.loadUser()
        self.authMode = Self.loadAuthMode()
        self.pendingVerificationEmail = UserDefaults.standard.string(forKey: Self.pendingEmailKey)
        startAuthStateListenerIfNeeded()
        if currentUser != nil {
            scheduleSavedDuasRefresh()
            scheduleDuaCollectionsRefresh()
        }
        scheduleDuaFeedRefresh(silent: true)
    }

    var isLoggedIn: Bool { currentUser != nil }

    var awaitingEmailVerification: Bool { pendingVerificationEmail != nil }

    func presentAuth() {
        authError = nil
        showAuthSheet = true
    }

    func dismissAuth() {
        showAuthSheet = false
        authError = nil
    }

    func clearEmailVerificationStage() {
        pendingVerificationEmail = nil
        UserDefaults.standard.removeObject(forKey: Self.pendingEmailKey)
    }

    func login(email: String, password: String) async {
        authInFlight = true
        authError = nil
        defer { authInFlight = false }

        if supabase.isConfigured {
            do {
                _ = try await supabase.signIn(email: email, password: password)
                authMode = .supabase
                setAuthMode(.supabase)
                if await completeSupabaseSignIn() {
                    showAuthSheet = false
                }
                return
            } catch let error as SupabaseAuthServiceError {
                authError = error.errorDescription
                return
            } catch {
                if !shouldTryLegacyLogin(error) {
                    authError = mapSupabaseError(error)
                    return
                }
            }
        }

        await legacyLogin(email: email, password: password)
    }

    func register(username: String, email: String, password: String) async -> RegisterResult {
        authInFlight = true
        authError = nil
        defer { authInFlight = false }

        if supabase.isConfigured {
            supabase.storePendingUsername(username)
            do {
                let outcome = try await supabase.signUp(email: email, password: password)
                switch outcome {
                case .signedIn:
                    authMode = .supabase
                    setAuthMode(.supabase)
                    if let user = await syncAppProfile() {
                        clearEmailVerificationStage()
                        showAuthSheet = false
                        return .signedIn(user)
                    }
                    return .failed
                case .awaitingVerification:
                    enterEmailVerificationStage(email: email)
                    return .awaitingVerification(email: email)
                }
            } catch {
                authError = mapSupabaseError(error)
                return .failed
            }
        }

        return await legacyRegister(username: username, email: email, password: password)
    }

    func requestPasswordReset(email: String) async -> Bool {
        guard supabase.isConfigured else {
            authError = "Password reset is not available for this account."
            return false
        }

        authInFlight = true
        authError = nil
        defer { authInFlight = false }

        do {
            try await supabase.requestPasswordReset(email: email)
            return true
        } catch {
            authError = mapSupabaseError(error)
            return false
        }
    }

    func completePasswordReset(password: String) async -> Bool {
        guard supabase.isConfigured else { return false }

        authInFlight = true
        authError = nil
        defer { authInFlight = false }

        do {
            _ = try await supabase.updatePassword(password)
            passwordRecoveryPending = false
            supabase.clearPendingPasswordReset()
            authMode = .supabase
            setAuthMode(.supabase)
            if await completeSupabaseSignIn() {
                showAuthSheet = false
                return true
            }
            return false
        } catch {
            authError = mapSupabaseError(error)
            return false
        }
    }

    func clearPasswordRecovery() {
        passwordRecoveryPending = false
        supabase.clearPendingPasswordReset()
        if supabase.isConfigured {
            Task { await supabase.signOut() }
        }
    }

    func resendVerificationEmail() async -> Bool {
        guard let email = pendingVerificationEmail, supabase.isConfigured else { return false }
        authInFlight = true
        authError = nil
        defer { authInFlight = false }
        do {
            try await supabase.resendVerification(email: email)
            return true
        } catch {
            authError = mapSupabaseError(error)
            return false
        }
    }

    /// Handles email-verification and password-recovery deep links (`myapp://auth/callback`).
    func handleAuthURL(_ url: URL) async {
        guard supabase.isConfigured, SupabaseAuthService.isAuthCallbackURL(url) else { return }

        // PKCE recovery links often omit `type=recovery` in the URL; the web client tracks recovery
        // via a `/recovery` suffix on the stored PKCE verifier. We mirror that with a local flag
        // set when `requestPasswordReset` runs on this device.
        let isRecovery = SupabaseAuthService.isPasswordRecoveryURL(url) || supabase.hasPendingPasswordReset()

        authInFlight = true
        authError = nil
        defer { authInFlight = false }

        if isRecovery {
            passwordRecoveryPending = true
        }

        do {
            _ = try await supabase.session(from: url)

            if isRecovery {
                presentAuth()
                return
            }

            guard passwordRecoveryPending == false else {
                presentAuth()
                return
            }

            guard let session = await supabase.currentSession(),
                  session.user.emailConfirmedAt != nil else {
                return
            }

            authMode = .supabase
            setAuthMode(.supabase)
            presentAuth()
            if await completeSupabaseSignIn() {
                showAuthSheet = false
            }
        } catch {
            if isRecovery {
                passwordRecoveryPending = false
                supabase.clearPendingPasswordReset()
            }
            authError = mapSupabaseError(error)
            presentAuth()
        }
    }

    func logout() {
        currentUser = nil
        authMode = nil
        passwordRecoveryPending = false
        clearSavedDuasState()
        clearDuaCollectionsState()
        clearDuaFeedState()
        UserDefaults.standard.removeObject(forKey: Self.storageKey)
        UserDefaults.standard.removeObject(forKey: Self.authModeKey)
        if supabase.isConfigured {
            Task { await supabase.signOut() }
        }
    }

    func scheduleSavedDuasRefresh() {
        savedDuasRefreshTask?.cancel()
        savedDuasRefreshTask = Task { @MainActor [weak self] in
            await self?.refreshSavedDuas()
        }
    }

    func insertSavedDua(_ row: SavedDuaDTO) {
        savedDuas.removeAll { $0.duaId == row.duaId }
        savedDuas.insert(row, at: 0)
        savedDuasError = nil
    }

    func removeSavedDua(id: String) {
        savedDuas.removeAll { $0.duaId == id }
    }

    func deleteSavedDuaRow(_ row: SavedDuaDTO) async throws {
        if SavedDuaDisplay.kind(from: row) == .sunnah {
            try await client.deleteSavedSunnahDua(id: row.duaId)
        } else {
            try await client.deleteSavedDua(id: row.duaId)
        }
        removeSavedDua(id: row.duaId)
    }

    func updateSavedDuaRow(_ row: SavedDuaDTO, duaPayload: String) async throws -> SavedDuaDTO {
        let updated = try await client.updateSavedDua(id: row.duaId, dua: duaPayload)
        insertSavedDua(updated)
        return updated
    }

    func scheduleDuaCollectionsRefresh() {
        duaCollectionsRefreshTask?.cancel()
        duaCollectionsRefreshTask = Task { @MainActor [weak self] in
            await self?.refreshDuaCollections()
        }
    }

    func insertDuaCollection(_ summary: DuaCollectionSummaryDTO) {
        if let index = duaCollections.firstIndex(where: { $0.collectionId == summary.collectionId }) {
            duaCollections[index] = summary
        } else {
            duaCollections.insert(summary, at: 0)
        }
        duaCollectionsError = nil
    }

    func upsertDuaCollection(from detail: DuaCollectionDetailDTO) {
        let summary = DuaCollectionSummaryDTO(
            collectionId: detail.collectionId,
            name: detail.name,
            description: detail.description,
            duaCount: detail.savedDuas.count,
            createdAt: detail.createdAt,
            updatedAt: detail.updatedAt
        )
        insertDuaCollection(summary)
        if let uid = currentUser?.userId,
           let kind = DuaCollectionDisplay.inferredKind(from: detail.savedDuas) {
            CollectionKindCache.store(userId: uid, collectionId: detail.collectionId, kind: kind)
        }
    }

    func removeDuaCollection(id: String) {
        if let uid = currentUser?.userId {
            CollectionKindCache.remove(userId: uid, collectionId: id)
        }
        duaCollections.removeAll { $0.collectionId == id }
    }

    func deleteAccount() async throws {
        guard currentUser != nil else { return }
        let token = await authorizationBearer()
        try await client.deleteAccount(bearerToken: token)
        logout()
    }

    var canChangePasswordInApp: Bool {
        authMode == .supabase || (authMode == nil && supabase.isConfigured)
    }

    func updateUsername(_ username: String) async -> Bool {
        guard let user = currentUser else { return false }

        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        guard UsernameRules.isValid(trimmed) else {
            authError = UsernameRules.invalidMessage
            return false
        }
        guard trimmed != user.username else { return true }

        authInFlight = true
        authError = nil
        defer { authInFlight = false }

        do {
            guard let token = await authorizationBearer() else {
                authError = "Could not verify your session. Please sign in again."
                return false
            }
            let updated = try await client.updateUsername(bearerToken: token, username: trimmed)
            setUser(updated)
            return true
        } catch {
            authError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return false
        }
    }

    func changePassword(currentPassword: String, newPassword: String) async -> Bool {
        guard let user = currentUser else { return false }
        guard canChangePasswordInApp else {
            authError = "Use the password reset link sent to your email to change your password."
            return false
        }

        let trimmedNew = newPassword.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedNew.count >= 6 else {
            authError = "Password must be at least 6 characters."
            return false
        }

        authInFlight = true
        authError = nil
        defer { authInFlight = false }

        do {
            _ = try await supabase.signIn(email: user.email, password: currentPassword)
            try await supabase.updatePassword(trimmedNew)
            return true
        } catch {
            authError = mapSupabaseError(error)
            return false
        }
    }

    func sendPasswordResetToCurrentUser() async -> Bool {
        guard let email = currentUser?.email else { return false }
        return await requestPasswordReset(email: email)
    }

    func syncSubscribedPlan(originalTransactionId: String?, confirmTransfer: Bool = false) async throws {
        guard let user = currentUser else { return }
        let token = await authorizationBearer()
        let updatedUser = try await client.subscribePlan(
            authorizedUserId: user.userId,
            bearerToken: token,
            originalTransactionId: originalTransactionId,
            productId: SubscriptionProducts.plusMonthlyID,
            confirmTransfer: confirmTransfer
        )
        setUser(updatedUser)
    }

    private func legacyLogin(email: String, password: String) async {
        do {
            let user = try await client.login(LoginRequest(email: email, password: password))
            authMode = .legacy
            setAuthMode(.legacy)
            setUser(user)
            showAuthSheet = false
        } catch {
            authError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func legacyRegister(username: String, email: String, password: String) async -> RegisterResult {
        do {
            let user = try await client.register(RegisterRequest(username: username, email: email, password: password))
            authMode = .legacy
            setAuthMode(.legacy)
            setUser(user)
            showAuthSheet = false
            return .signedIn(user)
        } catch {
            authError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return .failed
        }
    }

    private func startAuthStateListenerIfNeeded() {
        guard supabase.isConfigured else { return }

        authStateListenerTask?.cancel()
        authStateListenerTask = Task { @MainActor [weak self] in
            guard let self else { return }
            for await (event, _) in supabase.authStateChanges {
                guard !Task.isCancelled else { return }
                handleAuthStateChange(event)
            }
        }
    }

    private func handleAuthStateChange(_ event: AuthChangeEvent) {
        if authMode == .legacy { return }

        switch event {
        case .passwordRecovery:
            passwordRecoveryPending = true
            presentAuth()
        case .signedIn:
            if passwordRecoveryPending {
                presentAuth()
            }
        case .signedOut:
            passwordRecoveryPending = false
            supabase.clearPendingPasswordReset()
        default:
            break
        }
    }

    private func completeSupabaseSignIn() async -> Bool {
        if passwordRecoveryPending { return false }
        if await syncAppProfile() != nil {
            clearEmailVerificationStage()
            return true
        }
        return false
    }

    private func syncAppProfile() async -> AuthUser? {
        let username = supabase.pendingUsername()
        let token = await supabase.accessToken()
        do {
            let user = try await client.syncProfile(username: username, bearerToken: token)
            supabase.clearPendingUsername()
            setUser(user)
            return user
        } catch {
            authError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            return nil
        }
    }

    private func enterEmailVerificationStage(email: String) {
        pendingVerificationEmail = email
        UserDefaults.standard.set(email, forKey: Self.pendingEmailKey)
    }

    private func authorizationBearer() async -> String? {
        if authMode == .supabase || (authMode == nil && supabase.isConfigured) {
            if let token = await supabase.accessToken() {
                return token
            }
        }
        if let user = currentUser {
            return String(user.userId)
        }
        return nil
    }

    private func shouldTryLegacyLogin(_ error: Error) -> Bool {
        let message = (error as? LocalizedError)?.errorDescription?.lowercased() ?? error.localizedDescription.lowercased()
        if message.contains("email not confirmed") { return false }
        if message.contains("invalid login credentials") { return true }
        return message.contains("invalid") && message.contains("password")
    }

    private func mapSupabaseError(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }

    private func setUser(_ user: AuthUser) {
        currentUser = user
        if let data = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
        scheduleSavedDuasRefresh()
        scheduleDuaCollectionsRefresh()
        scheduleDuaFeedRefresh(silent: true)
        Task { await warmUpAppContent() }
    }

    private func setAuthMode(_ mode: AuthMode) {
        UserDefaults.standard.set(mode.rawValue, forKey: Self.authModeKey)
    }

    private static func loadUser() -> AuthUser? {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(AuthUser.self, from: data)
    }

    private static func loadAuthMode() -> AuthMode? {
        guard let raw = UserDefaults.standard.string(forKey: authModeKey) else { return nil }
        return AuthMode(rawValue: raw)
    }

    func api() -> BespokeAPIClient { client }

    private func clearSavedDuasState() {
        savedDuasRefreshTask?.cancel()
        savedDuasRefreshTask = nil
        savedDuas = []
        savedDuasLoading = false
        savedDuasError = nil
    }

    private func clearDuaCollectionsState() {
        duaCollectionsRefreshTask?.cancel()
        duaCollectionsRefreshTask = nil
        duaCollections = []
        duaCollectionsLoading = false
        duaCollectionsError = nil
    }

    func refreshSavedDuas() async {
        guard let uid = currentUser?.userId else {
            clearSavedDuasState()
            return
        }

        savedDuasLoading = true
        defer { savedDuasLoading = false }

        var lastError: Error?
        for attempt in 0 ..< Self.savedDuasMaxAttempts {
            guard !Task.isCancelled else { return }

            do {
                async let bespokeRows = client.savedDuas(forUserId: uid)
                async let sunnahRows = client.savedSunnahDuas(forUserId: uid)
                let merged = try await bespokeRows + sunnahRows.map { $0.asSavedDuaDTO() }
                savedDuas = merged.sorted { $0.createdAt > $1.createdAt }
                savedDuasError = nil
                return
            } catch {
                if shouldIgnoreSavedDuasLoadError(error) { return }
                lastError = error
                if attempt < Self.savedDuasMaxAttempts - 1 {
                    try? await Task.sleep(for: Self.savedDuasRetryDelay)
                }
            }
        }

        savedDuas = []
        savedDuasError = Self.friendlySavedDuasErrorMessage(for: lastError)
    }

    private func shouldIgnoreSavedDuasLoadError(_ error: Error) -> Bool {
        shouldIgnoreCancelledLoadError(error)
    }

    private func shouldIgnoreCancelledLoadError(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        if let bespokeError = error as? BespokeAPIError,
           case .transport(let underlying) = bespokeError,
           shouldIgnoreCancelledLoadError(underlying) {
            return true
        }
        return false
    }

    private static func friendlySavedDuasErrorMessage(for error: Error?) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return "We couldn't reach your saved duas. Check your connection and try again."
            case .timedOut:
                return "That took a little too long. Tap Try again when you're ready."
            default:
                break
            }
        }

        if let localized = error as? LocalizedError,
           let description = localized.errorDescription,
           !description.isEmpty {
            return description
        }

        return "We couldn't load your saved duas right now. Please try again in a moment."
    }

    func refreshDuaCollections() async {
        guard let uid = currentUser?.userId else {
            clearDuaCollectionsState()
            return
        }

        duaCollectionsLoading = true
        duaCollectionsError = nil
        defer { duaCollectionsLoading = false }

        var lastError: Error?
        for attempt in 0 ..< Self.duaCollectionsMaxAttempts {
            guard !Task.isCancelled else { return }

            do {
                duaCollections = try await client.duaCollections(forUserId: uid)
                duaCollectionsError = nil
                await inferMissingCollectionKinds(userId: uid)
                return
            } catch {
                if shouldIgnoreSavedDuasLoadError(error) { return }
                lastError = error
                if attempt < Self.duaCollectionsMaxAttempts - 1 {
                    try? await Task.sleep(for: Self.duaCollectionsRetryDelay)
                }
            }
        }

        duaCollections = []
        duaCollectionsError = Self.friendlyDuaCollectionsErrorMessage(for: lastError)
    }

    private static func friendlyDuaCollectionsErrorMessage(for error: Error?) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost:
                return "We couldn't reach your collections. Check your connection and try again."
            case .timedOut:
                return "That took a little too long. Tap Try again when you're ready."
            default:
                break
            }
        }

        if let localized = error as? LocalizedError,
           let description = localized.errorDescription,
           !description.isEmpty {
            return description
        }

        return "We couldn't load your collections right now. Please try again in a moment."
    }

    private func inferMissingCollectionKinds(userId: Int) async {
        for collection in duaCollections {
            guard CollectionKindCache.kind(userId: userId, collectionId: collection.collectionId) == nil else {
                continue
            }
            guard collection.duaCount > 0 else { continue }

            guard !Task.isCancelled else { return }

            do {
                let detail = try await client.duaCollection(id: collection.collectionId)
                if let kind = DuaCollectionDisplay.inferredKind(from: detail.savedDuas) {
                    CollectionKindCache.store(userId: userId, collectionId: collection.collectionId, kind: kind)
                }
            } catch {
                continue
            }
        }
    }

    func warmUpAppContent() async {
        await withTaskGroup(of: Void.self) { group in
            group.addTask { await self.refreshDuaFeed(showLoading: false) }
            group.addTask { await self.refreshFeelingLabels() }
            group.addTask { _ = try? await HomeNameOfTheDayService.todaysName() }
            if self.currentUser != nil {
                group.addTask { await self.refreshSavedDuas() }
                group.addTask { await self.refreshDuaCollections() }
            }
        }
    }

    func scheduleDuaFeedRefresh(silent: Bool = true) {
        duaFeedRefreshTask?.cancel()
        duaFeedRefreshTask = Task { @MainActor [weak self] in
            await self?.refreshDuaFeed(showLoading: !silent)
        }
    }

    func startDuaFeedAutoRefresh() {
        duaFeedAutoRefreshTask?.cancel()
        duaFeedAutoRefreshTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.duaFeedAutoRefreshInterval)
                guard !Task.isCancelled else { break }
                await self?.refreshDuaFeed(showLoading: false)
            }
        }
    }

    func stopDuaFeedAutoRefresh() {
        duaFeedAutoRefreshTask?.cancel()
        duaFeedAutoRefreshTask = nil
    }

    func refreshDuaFeed(showLoading: Bool, refreshSavedDuas: Bool = true) async {
        if showLoading {
            guard !duaFeedIsLoading, !duaFeedIsSilentRefreshing else { return }
            duaFeedIsLoading = true
            defer { duaFeedIsLoading = false }
            duaFeedLoadError = nil
        } else {
            guard !duaFeedIsSilentRefreshing, !duaFeedIsLoading else { return }
            duaFeedIsSilentRefreshing = true
            defer { duaFeedIsSilentRefreshing = false }
        }

        if refreshSavedDuas {
            scheduleSavedDuasRefresh()
        }
        await refreshDuaFeedUserActivePosts()

        do {
            let response = try await client.duaFeed(
                userId: currentUser?.userId,
                page: 1,
                pageSize: 20
            )
            duaFeedPosts = response.items.compactMap { $0.asFeedPost() }
            duaFeedCurrentPage = response.page
            duaFeedHasMore = response.hasMore
            syncDuaFeedOwnPostFlags()
            duaFeedLoadError = nil
        } catch {
            guard !shouldIgnoreCancelledLoadError(error) else { return }
            if showLoading || duaFeedPosts.isEmpty {
                duaFeedLoadError = (error as? BespokeAPIError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    func loadMoreDuaFeed() async {
        guard duaFeedHasMore, !duaFeedIsLoading, !duaFeedIsSilentRefreshing else { return }

        duaFeedIsLoading = true
        defer { duaFeedIsLoading = false }

        do {
            let response = try await client.duaFeed(
                userId: currentUser?.userId,
                page: duaFeedCurrentPage + 1,
                pageSize: 20
            )
            duaFeedPosts.append(contentsOf: response.items.compactMap { $0.asFeedPost() })
            duaFeedCurrentPage = response.page
            duaFeedHasMore = response.hasMore
            syncDuaFeedOwnPostFlags()
            duaFeedLoadError = nil
        } catch {
            guard !shouldIgnoreCancelledLoadError(error) else { return }
            duaFeedLoadError = (error as? BespokeAPIError)?.errorDescription ?? error.localizedDescription
        }
    }

    func refreshFeelingLabels() async {
        namesFeelingLabelsLoading = true
        defer { namesFeelingLabelsLoading = false }

        do {
            namesFeelingLabels = try await client.feelingLabels()
            namesFeelingLabelsError = nil
        } catch {
            namesFeelingLabelsError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func insertDuaFeedPost(_ post: DuaFeedPost) {
        duaFeedPosts.removeAll { $0.id == post.id }
        duaFeedPosts.insert(post, at: 0)
        if !duaFeedUserActivePosts.contains(where: { $0.id == post.id }) {
            duaFeedUserActivePosts.insert(post, at: 0)
        }
        syncDuaFeedOwnPostFlags()
    }

    func removeDuaFeedPost(id: UUID) {
        duaFeedUserActivePosts.removeAll { $0.id == id }
        duaFeedPosts.removeAll { $0.id == id }
    }

    func updateDuaFeedPost(id: UUID, with updated: DuaFeedPost) {
        guard let index = duaFeedPosts.firstIndex(where: { $0.id == id }) else { return }
        duaFeedPosts[index] = updated
    }

    func duaFeedPostBinding(for post: DuaFeedPost) -> Binding<DuaFeedPost> {
        Binding(
            get: { [self] in
                duaFeedPosts.first { $0.id == post.id } ?? post
            },
            set: { [self] updated in
                updateDuaFeedPost(id: post.id, with: updated)
            }
        )
    }

    func toggleDuaFeedMakeDua(postId: UUID, userId: Int) async throws -> MakeDuaResponse {
        guard let index = duaFeedPosts.firstIndex(where: { $0.id == postId }),
              !duaFeedPosts[index].isOwnPost else {
            throw BespokeAPIError.transport(URLError(.unknown))
        }

        let response = try await client.toggleMakeDua(
            postId: duaFeedPosts[index].serverPostId,
            userId: userId
        )
        withAnimation(.easeInOut(duration: 0.2)) {
            duaFeedPosts[index].duaCount = response.duaCount
            duaFeedPosts[index].hasMadeDua = response.hasUserMadeDua
        }
        return response
    }

    func reconnectAppContent() async {
        isReconnecting = true
        defer { isReconnecting = false }

        if currentUser != nil {
            async let feed: Void = refreshDuaFeed(showLoading: false, refreshSavedDuas: false)
            async let saved: Void = refreshSavedDuas()
            _ = await (feed, saved)
        } else {
            await refreshDuaFeed(showLoading: false, refreshSavedDuas: false)
        }
    }

    func reconnectFeelingLabels() async {
        isReconnecting = true
        defer { isReconnecting = false }
        await refreshFeelingLabels()
    }

    func recordDuaFeedError(_ error: Error) {
        guard !shouldIgnoreCancelledLoadError(error) else { return }
        duaFeedLoadError = (error as? BespokeAPIError)?.errorDescription ?? error.localizedDescription
    }

    func clearDuaFeedState() {
        duaFeedRefreshTask?.cancel()
        duaFeedRefreshTask = nil
        stopDuaFeedAutoRefresh()
        duaFeedPosts = []
        duaFeedUserActivePosts = []
        duaFeedCurrentPage = 1
        duaFeedHasMore = false
        duaFeedLoadError = nil
        duaFeedIsLoading = false
        duaFeedIsSilentRefreshing = false
        namesFeelingLabels = []
        namesFeelingLabelsLoading = false
        namesFeelingLabelsError = nil
        isReconnecting = false
    }

    private func refreshDuaFeedUserActivePosts() async {
        guard let userId = currentUser?.userId else {
            duaFeedUserActivePosts = []
            return
        }

        duaFeedUserActivePosts = await client.userActiveFeedPosts(userId: userId)
        syncDuaFeedOwnPostFlags()
    }

    private func syncDuaFeedOwnPostFlags() {
        let activeServerIDs = Set(duaFeedUserActivePosts.map(\.serverPostId))
        for index in duaFeedPosts.indices {
            if duaFeedPosts[index].isOwnPost { continue }
            if activeServerIDs.contains(duaFeedPosts[index].serverPostId) {
                duaFeedPosts[index].isOwnPost = true
            }
        }
    }
}
