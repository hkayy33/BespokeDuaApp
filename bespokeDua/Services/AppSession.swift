import Foundation
import Observation

@Observable
@MainActor
final class AppSession {
    private let client: BespokeAPIClient
    private static let storageKey = "bespoke-dua-user"

    private(set) var currentUser: AuthUser?
    var authInFlight = false
    var authError: String?
    var showAuthSheet = false

    init(client: BespokeAPIClient = BespokeAPIClient()) {
        self.client = client
        self.currentUser = Self.loadUser()
    }

    var isLoggedIn: Bool { currentUser != nil }

    func presentAuth() {
        authError = nil
        showAuthSheet = true
    }

    func dismissAuth() {
        showAuthSheet = false
        authError = nil
    }

    func login(email: String, password: String) async {
        authInFlight = true
        authError = nil
        defer { authInFlight = false }
        do {
            let user = try await client.login(LoginRequest(email: email, password: password))
            setUser(user)
            showAuthSheet = false
        } catch {
            authError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func register(username: String, email: String, password: String) async {
        authInFlight = true
        authError = nil
        defer { authInFlight = false }
        do {
            let user = try await client.register(RegisterRequest(username: username, email: email, password: password))
            setUser(user)
            showAuthSheet = false
        } catch {
            authError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    func logout() {
        currentUser = nil
        UserDefaults.standard.removeObject(forKey: Self.storageKey)
    }

    func deleteAccount() async throws {
        guard let user = currentUser else { return }
        try await client.deleteAccount(authorizedUserId: user.userId)
        logout()
    }

    private func setUser(_ user: AuthUser) {
        currentUser = user
        if let data = try? JSONEncoder().encode(user) {
            UserDefaults.standard.set(data, forKey: Self.storageKey)
        }
    }

    private static func loadUser() -> AuthUser? {
        guard let data = UserDefaults.standard.data(forKey: storageKey) else { return nil }
        return try? JSONDecoder().decode(AuthUser.self, from: data)
    }

    func api() -> BespokeAPIClient { client }
}
