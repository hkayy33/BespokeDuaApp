import Foundation

/// Supabase project settings (public anon key — same as the web client).
enum SupabaseConfig {
    static let projectURL = URL(string: "https://miwszixxfkbrnyaeivly.supabase.co")!

    /// Production email confirmation. Opens the app by universal link, then `myapp://`.
    static let productionEmailRedirectURL = URL(string: "https://www.bespokedua.com/auth/callback")!

    /// Local `ng serve` — matches `bespoke-dua-client` `environment.ts` `authRedirectUrl`.
    static let developmentEmailRedirectURL = URL(string: "http://localhost:4200/auth/callback")!

    /// Hosts that can open the app via a universal link after email confirmation.
    static let authCallbackHosts: Set<String> = ["www.bespokedua.com", "bespokedua.com"]

    /// Web email confirmation lands on this URL. The site then opens the app
    /// (universal link, or `myapp://` if the browser stays open).
    ///
    /// Always the production URL, including debug builds on a phone. `localhost`
    /// cannot be opened from the device that receives the email.
    ///
    /// - Override: `BESPOKE_AUTH_REDIRECT_URL`
    /// - Local web only: `BESPOKE_AUTH_USE_LOCAL=1` (simulator / Mac, not a phone)
    static var emailRedirectURL: URL {
        let env = ProcessInfo.processInfo.environment

        if let raw = env["BESPOKE_AUTH_REDIRECT_URL"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty,
           let url = URL(string: raw) {
            return url
        }

        #if DEBUG
        let useLocal = env["BESPOKE_AUTH_USE_LOCAL"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if useLocal == "1" || useLocal?.lowercased() == "true" {
            return developmentEmailRedirectURL
        }
        #endif

        return productionEmailRedirectURL
    }

    /// Matches `auth-redirect.config.ts` and Info.plist URL scheme (`myapp`).
    static let supportedURLSchemes: Set<String> = ["myapp"]

    static var anonKey: String {
        if let raw = ProcessInfo.processInfo.environment["SUPABASE_ANON_KEY"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty {
            return raw
        }
        return defaultAnonKey
    }

    static var isConfigured: Bool {
        !anonKey.isEmpty
    }

    private static let defaultAnonKey =
        "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im1pd3N6aXh4Zmticm55YWVpdmx5Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzUwNzY1MDgsImV4cCI6MjA5MDY1MjUwOH0.Fp2GnwQVIk7UcTWrsN4oqEs6MUIGobJJTPHWLJUFcDk"
}
