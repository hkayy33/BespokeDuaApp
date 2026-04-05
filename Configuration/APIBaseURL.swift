import Foundation

enum APIBaseURL {
    /// Matches `bespoke-dua-client` production (`environment.prod.ts`).
    static let production = URL(string: "https://bespoke-app.fly.dev/api")!

    #if DEBUG
    /// Point at a local .NET API when testing (e.g. `http://127.0.0.1:5248/api`).
    static var current: URL { production }
    #else
    static var current: URL { production }
    #endif
}
