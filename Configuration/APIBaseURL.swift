import Foundation

/// Base URL for API calls. Paths in `BespokeAPIClient` are relative to this (e.g. `Dua/generate` → `…/api/Dua/generate`).
///
/// - **DEBUG** builds default to `development` (local API on :8080).
/// - **Release** builds always use `production` (Fly.io).
enum APIBaseURL {
    /// Matches `bespoke-dua-client` production (`environment.prod.ts`).
    /// Trailing `/` is required: without it, `URL(string: "Auth/login", relativeTo: base)` resolves to `…/Auth/login` instead of `…/api/Auth/login`.
    static let production = URL(string: "https://bespoke-app.fly.dev/api/")!

    /// DEBUG: local .NET API (matches `Now listening on: http://0.0.0.0:8080`).
    /// Simulator → loopback; device → your Mac’s LAN IP (on a real phone `127.0.0.1` is the phone, not the Mac).
    /// Update `deviceLocalAPILANHost` if your Mac gets a different address (`ipconfig getifaddr en0`).
    private static let deviceLocalAPILANHost = "192.168.1.40"

    static let development: URL = {
        #if targetEnvironment(simulator)
        return URL(string: "http://127.0.0.1:8080/api/")!
        #else
        return URL(string: "http://\(deviceLocalAPILANHost):8080/api/")!
        #endif
    }()

    /// Normalizes the API root so relative paths append under `/api/` (RFC 3986 merge rules).
    static func withTrailingSlash(_ url: URL) -> URL {
        let s = url.absoluteString
        if s.hasSuffix("/") { return url }
        return URL(string: s + "/") ?? url
    }

    #if DEBUG
    /// Default: local .NET API (`development`). Release builds use Fly.io (`production`) automatically.
    /// Override anytime: Scheme → Run → Arguments → Environment Variables → `BESPOKE_API_BASE_URL`
    /// (e.g. `https://bespoke-app.fly.dev/api` to hit production while debugging).
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
