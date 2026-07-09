import Foundation

/// Base URL for API calls. Paths in `BespokeAPIClient` are relative to this (e.g. `Dua/generate` → `…/api/Dua/generate`).
///
/// - **DEBUG**: local .NET API (`http://127.0.0.1:8080/api`), same as `bespoke-dua-client` + `proxy.conf.json`.
/// - **Release**: Fly.io production.
/// - Override anytime with `BESPOKE_API_BASE_URL`; set `BESPOKE_API_USE_PRODUCTION=1` in Debug to hit Fly.io.
enum APIBaseURL: Sendable {
    /// Matches `bespoke-dua-client` production (`environment.prod.ts`).
    /// Trailing `/` is required: without it, `URL(string: "Auth/login", relativeTo: base)` resolves to `…/Auth/login` instead of `…/api/Auth/login`.
    static let production = URL(string: "https://bespoke-app.fly.dev/api/")!

    /// Matches local `ng serve` proxy target (`.NET` default port 8080).
    static let development = URL(string: "http://127.0.0.1:8080/api/")!

    /// Normalizes the API root so relative paths append under `/api/` (RFC 3986 merge rules).
    static func withTrailingSlash(_ url: URL) -> URL {
        let s = url.absoluteString
        if s.hasSuffix("/") { return url }
        return URL(string: s + "/") ?? url
    }

    #if DEBUG
    /// Default: local API. On a physical device use `BESPOKE_API_BASE_URL=http://<Mac-LAN-IP>:8080/api`.
    static var current: URL {
        let env = ProcessInfo.processInfo.environment

        if let raw = env["BESPOKE_API_BASE_URL"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !raw.isEmpty,
           let url = URL(string: raw) {
            return withTrailingSlash(url)
        }

        let useProduction = env["BESPOKE_API_USE_PRODUCTION"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if useProduction == "1" || useProduction?.lowercased() == "true" {
            return withTrailingSlash(production)
        }

        return withTrailingSlash(development)
    }
    #else
    /// App Store / release: Fly.io production API.
    static var current: URL { withTrailingSlash(production) }
    #endif
}
