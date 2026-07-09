import Foundation

enum DuaFeedPostingQuota {
    static let dailyLimit = 3

    private static var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    private static func utcDayKey(for date: Date = .now) -> String {
        let components = utcCalendar.dateComponents([.year, .month, .day], from: date)
        let year = components.year ?? 0
        let month = components.month ?? 0
        let day = components.day ?? 0
        return String(format: "%04d-%02d-%02d", year, month, day)
    }

    private static func storageKey(userId: Int) -> String {
        "duaFeed.posts.\(userId).\(utcDayKey())"
    }

    static func postsUsedToday(userId: Int) -> Int {
        UserDefaults.standard.integer(forKey: storageKey(userId: userId))
    }

    static func postsCreatedTodayCount(_ posts: [DuaFeedPost]) -> Int {
        let todayKey = utcDayKey()
        return posts.filter { utcDayKey(for: $0.createdAt) == todayKey }.count
    }

    static func postsRemainingToday(userId: Int) -> Int {
        max(0, dailyLimit - postsUsedToday(userId: userId))
    }

    static func canPostToday(userId: Int) -> Bool {
        postsRemainingToday(userId: userId) > 0
    }

    static func recordPost(userId: Int) {
        let key = storageKey(userId: userId)
        let count = UserDefaults.standard.integer(forKey: key)
        UserDefaults.standard.set(min(dailyLimit, count + 1), forKey: key)
    }

    /// Applies the server's UTC-day post count so UI matches what the API enforces.
    static func applyServerUsage(userId: Int, usedToday: Int) {
        let key = storageKey(userId: userId)
        UserDefaults.standard.set(min(dailyLimit, max(0, usedToday)), forKey: key)
    }

    static func markDailyLimitReached(userId: Int) {
        UserDefaults.standard.set(dailyLimit, forKey: storageKey(userId: userId))
    }

    static func postsSummary(userId: Int) -> String {
        let remaining = postsRemainingToday(userId: userId)
        let used = postsUsedToday(userId: userId)
        if remaining == 0 {
            return "All \(dailyLimit) posts used today"
        }
        if used == 0 {
            return "Up to \(dailyLimit) posts per day"
        }
        return "\(remaining) of \(dailyLimit) posts left today"
    }
}
