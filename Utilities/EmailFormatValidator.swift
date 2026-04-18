import Foundation

/// Conventional internet email shape: `local@domain.tld` with length limits aligned with common SMTP practice (not full RFC 5322).
///
/// **Supported examples:** personal (`name@gmail.com`), corporate (`you@company.com`, `team@sub.dept.company.co.uk`),
/// education (`student@university.edu`), government (`case@agency.gov`), plus-addressing (`you+tag@firm.com`).
/// ASCII only (international domains should be entered as punycode, e.g. `xn--…`, which most clients handle when pasting).
enum EmailFormatValidator {
    /// Local part + `@` + one or more domain labels + `.` + TLD (2+ letters). Hyphens and subdomains are allowed.
    private static let pattern = #"^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$"#

    private static let regex: NSRegularExpression = {
        do {
            return try NSRegularExpression(pattern: pattern, options: [])
        } catch {
            fatalError("Invalid email regex: \(error)")
        }
    }()

    static let invalidMessage = "Enter a valid email address (e.g. name@company.com or you@university.edu)."

    static func isValid(_ raw: String) -> Bool {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return false }
        // SMTP envelope limits; keeps pathological input out.
        guard s.utf8.count <= 254 else { return false }
        let range = NSRange(location: 0, length: (s as NSString).length)
        guard let match = regex.firstMatch(in: s, options: [], range: range),
              match.range.length == (s as NSString).length
        else { return false }
        let local = s.split(separator: "@", omittingEmptySubsequences: false)
        guard local.count == 2 else { return false }
        return local[0].count <= 64 && local[1].count <= 253
    }
}
