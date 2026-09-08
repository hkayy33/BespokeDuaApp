import Auth
import Foundation
import Supabase

@MainActor
final class SupabaseAuthService {
    static let shared = SupabaseAuthService()

    private let client: SupabaseClient
    private static let pendingUsernameKey = "bespoke-pending-username"
    private static let pendingPasswordResetKey = "bespoke-pending-password-reset"

    private init() {
        client = SupabaseClient(
            supabaseURL: SupabaseConfig.projectURL,
            supabaseKey: SupabaseConfig.anonKey,
            options: SupabaseClientOptions(
                auth: .init(
                    redirectToURL: SupabaseConfig.emailRedirectURL,
                    flowType: .pkce
                )
            )
        )
    }

    var isConfigured: Bool { SupabaseConfig.isConfigured }

    func storePendingUsername(_ username: String) {
        UserDefaults.standard.set(username, forKey: Self.pendingUsernameKey)
    }

    func pendingUsername() -> String? {
        UserDefaults.standard.string(forKey: Self.pendingUsernameKey)
    }

    func clearPendingUsername() {
        UserDefaults.standard.removeObject(forKey: Self.pendingUsernameKey)
    }

    func signUp(email: String, password: String) async throws -> SignUpOutcome {
        let response = try await client.auth.signUp(
            email: email,
            password: password,
            redirectTo: SupabaseConfig.emailRedirectURL
        )

        if let session = response.session, session.user.emailConfirmedAt != nil {
            return .signedIn(session: session)
        }

        return .awaitingVerification
    }

    func signIn(email: String, password: String) async throws -> Session {
        let session = try await client.auth.signIn(email: email, password: password)
        guard session.user.emailConfirmedAt != nil else {
            try? await client.auth.signOut()
            throw SupabaseAuthServiceError.emailNotConfirmed
        }
        return session
    }

    func resendVerification(email: String) async throws {
        try await client.auth.resend(
            email: email,
            type: .signup,
            emailRedirectTo: SupabaseConfig.emailRedirectURL
        )
    }

    func signOut() async {
        try? await client.auth.signOut()
    }

    func accessToken() async -> String? {
        try? await client.auth.session.accessToken
    }

    func currentSession() async -> Session? {
        try? await client.auth.session
    }

    /// Handles `myapp://auth/callback?...` and `https://www.bespokedua.com/auth/callback?...`.
    func session(from url: URL) async throws -> Session {
        try await client.auth.session(from: url)
    }

    var authStateChanges: AsyncStream<(event: AuthChangeEvent, session: Session?)> {
        client.auth.authStateChanges
    }

    func requestPasswordReset(email: String) async throws {
        setPendingPasswordReset(true)
        try await client.auth.resetPasswordForEmail(
            email,
            redirectTo: SupabaseConfig.emailRedirectURL
        )
    }

    func hasPendingPasswordReset() -> Bool {
        UserDefaults.standard.bool(forKey: Self.pendingPasswordResetKey)
    }

    func clearPendingPasswordReset() {
        UserDefaults.standard.removeObject(forKey: Self.pendingPasswordResetKey)
    }

    private func setPendingPasswordReset(_ pending: Bool) {
        if pending {
            UserDefaults.standard.set(true, forKey: Self.pendingPasswordResetKey)
        } else {
            clearPendingPasswordReset()
        }
    }

    func updatePassword(_ password: String) async throws {
        _ = try await client.auth.update(user: UserAttributes(password: password))
    }

    static func isPasswordRecoveryURL(_ url: URL) -> Bool {
        if urlContainsRecoveryType(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems) {
            return true
        }

        // `myapp://auth/callback?code=…&type=recovery` — query lives on nested components for some parsers.
        if let query = url.query, urlContainsRecoveryType(URLComponents(string: "?\(query)")?.queryItems) {
            return true
        }

        guard let fragment = url.fragment?.trimmingCharacters(in: CharacterSet(charactersIn: "#")),
              !fragment.isEmpty else {
            return false
        }

        let fragmentItems = URLComponents(string: "?\(fragment)")?.queryItems
        return urlContainsRecoveryType(fragmentItems)
    }

    private static func urlContainsRecoveryType(_ items: [URLQueryItem]?) -> Bool {
        items?.contains { $0.name == "type" && $0.value == "recovery" } == true
    }

    static func isAuthCallbackURL(_ url: URL) -> Bool {
        let path = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let scheme = url.scheme?.lowercased() else { return false }

        if scheme == "https" || scheme == "http" {
            guard let host = url.host?.lowercased(),
                  SupabaseConfig.authCallbackHosts.contains(host) else {
                return false
            }
            return path == "auth/callback"
        }

        guard SupabaseConfig.supportedURLSchemes.contains(scheme) else {
            return false
        }

        if path == "auth/callback" { return true }

        // `myapp://auth/callback` is parsed with host `auth` and path `callback`.
        return url.host?.lowercased() == "auth" && path == "callback"
    }
}

enum SignUpOutcome: Sendable {
    case signedIn(session: Session)
    case awaitingVerification
}

enum SupabaseAuthServiceError: LocalizedError, Sendable {
    case emailNotConfirmed
    case notConfigured

    var errorDescription: String? {
        switch self {
        case .emailNotConfirmed:
            return "Please verify your email before signing in. Check your inbox for the confirmation link."
        case .notConfigured:
            return "Sign-in is not configured."
        }
    }
}
