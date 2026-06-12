import Auth
import Foundation
import Observation

@Observable
@MainActor
final class AppSession {
    private let client: BespokeAPIClient
    private let supabase = SupabaseAuthService.shared
    private static let storageKey = "bespoke-dua-user"
    private static let authModeKey = "bespoke-auth-mode"
    private static let pendingEmailKey = "bespoke-pending-verification-email"

    private(set) var currentUser: AuthUser?
    var authInFlight = false
    var authError: String?
    var showAuthSheet = false
    private(set) var pendingVerificationEmail: String?
    private(set) var passwordRecoveryPending = false

    private var authMode: AuthMode?
    private var authStateListenerTask: Task<Void, Never>?

    private enum AuthMode: String {
        case legacy
        case supabase
    }

    init(client: BespokeAPIClient = BespokeAPIClient()) {
        self.client = client
        self.currentUser = Self.loadUser()
        self.authMode = Self.loadAuthMode()
        self.pendingVerificationEmail = UserDefaults.standard.string(forKey: Self.pendingEmailKey)
        startAuthStateListenerIfNeeded()
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
        UserDefaults.standard.removeObject(forKey: Self.storageKey)
        UserDefaults.standard.removeObject(forKey: Self.authModeKey)
        if supabase.isConfigured {
            Task { await supabase.signOut() }
        }
    }

    func deleteAccount() async throws {
        guard currentUser != nil else { return }
        let token = await authorizationBearer()
        try await client.deleteAccount(bearerToken: token)
        logout()
    }

    func syncSubscribedPlan(originalTransactionId: String?, confirmTransfer: Bool = false) async throws {
        guard let user = currentUser else { return }
        let token = await authorizationBearer()
        let updatedUser = try await client.subscribePlan(
            authorizedUserId: user.userId,
            bearerToken: token,
            originalTransactionId: originalTransactionId,
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
}
