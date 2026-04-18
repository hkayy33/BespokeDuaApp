import Foundation

/// Base URL for API calls. Paths in `BespokeAPIClient` are relative to this (e.g. `Dua/generate` → `…/api/Dua/generate`).
///
/// - **DEBUG** and **Release** builds default to `production` (Fly.io).
/// - Local API: set `BESPOKE_API_BASE_URL` (e.g. `http://127.0.0.1:8080/api`).
enum APIBaseURL {
    /// Matches `bespoke-dua-client` production (`environment.prod.ts`).
    /// Trailing `/` is required: without it, `URL(string: "Auth/login", relativeTo: base)` resolves to `…/Auth/login` instead of `…/api/Auth/login`.
    static let production = URL(string: "https://bespoke-app.fly.dev/api/")!

    /// Normalizes the API root so relative paths append under `/api/` (RFC 3986 merge rules).
    static func withTrailingSlash(_ url: URL) -> URL {
        let s = url.absoluteString
        if s.hasSuffix("/") { return url }
        return URL(string: s + "/") ?? url
    }

    #if DEBUG
    /// Default: Fly.io (`production`). Override for local .NET API: Scheme → Run → Arguments → Environment Variables → `BESPOKE_API_BASE_URL`
    /// (e.g. `http://127.0.0.1:8080/api` or `http://<LAN-IP>:8080/api` on device).
    static var current: URL {
        if let raw = ProcessInfo.processInfo.environment["BESPOKE_API_BASE_URL"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty,
           let url = URL(string: raw) {
            return withTrailingSlash(url)
        }
        return withTrailingSlash(production)
    }
    #else
    /// App Store / release: Fly.io production API.
    static var current: URL { withTrailingSlash(production) }
    #endif
}
