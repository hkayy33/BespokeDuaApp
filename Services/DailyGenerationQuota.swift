import Foundation

/// Tracks how many dua generations a signed-in user has made on the current calendar day (device-local).
enum DailyGenerationQuota {
    /// Temporarily `0` to force the upgrade UI; use `7` (or your real cap) for production.
    static let freeDailyLimit = 7

    private static func dayKey(for date: Date = .now) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        guard let y = c.year, let m = c.month, let d = c.day else { return "unknown" }
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    private static func storageKey(userId: Int) -> String {
        "bespoke.duaGenerations.day.\(userId).\(dayKey())"
    }

    static func generationsUsedToday(userId: Int) -> Int {
        UserDefaults.standard.integer(forKey: storageKey(userId: userId))
    }

    /// How many free generations remain today (0 … `freeDailyLimit`).
    static func duasRemainingToday(userId: Int) -> Int {
        max(0, freeDailyLimit - generationsUsedToday(userId: userId))
    }

    static func recordGeneration(userId: Int) {
        let key = storageKey(userId: userId)
        let n = UserDefaults.standard.integer(forKey: key)
        UserDefaults.standard.set(n + 1, forKey: key)
    }

    static func hasRemainingFreeGenerations(userId: Int) -> Bool {
        generationsUsedToday(userId: userId) < freeDailyLimit
    }
}
