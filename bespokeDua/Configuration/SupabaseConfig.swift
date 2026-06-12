import Foundation

/// Supabase project settings (public anon key — same as the web client).
enum SupabaseConfig {
    static let projectURL = URL(string: "https://miwszixxfkbrnyaeivly.supabase.co")!

    /// Production email confirmation (web bridge → `myapp://`).
    static let productionEmailRedirectURL = URL(string: "https://www.bespokedua.com/auth/callback")!

    /// Local `ng serve` — matches `bespoke-dua-client` `environment.ts` `authRedirectUrl`.
    static let developmentEmailRedirectURL = URL(string: "http://localhost:4200/auth/callback")!

    /// Web email confirmation lands on this URL, then opens the native app via custom scheme.
    ///
    /// - **DEBUG**: `http://localhost:4200/auth/callback` (run `ng serve` on the Mac).
    /// - **Release**: `https://www.bespokedua.com/auth/callback`
    /// - Override: `BESPOKE_AUTH_REDIRECT_URL`; force prod in Debug: `BESPOKE_AUTH_USE_PRODUCTION=1`
    /// - Physical device: `BESPOKE_AUTH_REDIRECT_URL=http://<Mac-LAN-IP>:4200/auth/callback`
    static var emailRedirectURL: URL {
        #if DEBUG
        let env = ProcessInfo.processInfo.environment

        if let raw = env["BESPOKE_AUTH_REDIRECT_URL"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty,
           let url = URL(string: raw) {
            return url
        }

        let useProduction = env["BESPOKE_AUTH_USE_PRODUCTION"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if useProduction == "1" || useProduction?.lowercased() == "true" {
            return productionEmailRedirectURL
        }

        return developmentEmailRedirectURL
        #else
        return productionEmailRedirectURL
        #endif
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
