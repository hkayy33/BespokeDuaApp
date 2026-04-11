import Foundation

/// Base URL for API calls. Paths in `BespokeAPIClient` are relative to this (e.g. `Dua/generate` → `…/api/Dua/generate`).
///
/// - **DEBUG** builds default to `development` (localhost :8080).
/// - **Release** builds always use `production` (Fly.io).
enum APIBaseURL {
    /// Matches `bespoke-dua-client` production (`environment.prod.ts`).
    /// Trailing `/` is required: without it, `URL(string: "Auth/login", relativeTo: base)` resolves to `…/Auth/login` instead of `…/api/Auth/login`.
    static let production = URL(string: "https://bespoke-app.fly.dev/api/")!

    /// DEBUG: local .NET API (matches `Now listening on: http://0.0.0.0:8080` in Development).
    /// Angular dev still uses `/api` + `proxy.conf.json` — point that target at this port if you use `ng serve`.
    /// Simulator: `127.0.0.1` reaches your Mac; device: set `BESPOKE_API_BASE_URL` to `http://<Mac-LAN-IP>:8080/api` (with or without trailing `/`; we normalize).
    static let development = URL(string: "http://127.0.0.1:8080/api/")!

    /// Normalizes the API root so relative paths append under `/api/` (RFC 3986 merge rules).
    static func withTrailingSlash(_ url: URL) -> URL {
        let s = url.absoluteString
        if s.hasSuffix("/") { return url }
        return URL(string: s + "/") ?? url
    }

    #if DEBUG
    /// Default: local .NET API (`development`). Release builds use Fly.io (`production`) automatically.
    /// Override anytime: Scheme → Run → Arguments → Environment Variables → `BESPOKE_API_BASE_URL`
    /// (e.g. point at Fly while debugging: `https://bespoke-app.fly.dev/api`, or on a physical device: `http://<Mac-LAN-IP>:8080/api`).
    static var current: URL {
        if let raw = ProcessInfo.processInfo.environment["BESPOKE_API_BASE_URL"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty,
           let url = URL(string: raw) {
            return withTrailingSlash(url)
        }
        return withTrailingSlash(development)
    }
    #else
    /// App Store / release: Fly.io production API.
    static var current: URL { withTrailingSlash(production) }
    #endif
}
