import Foundation

enum HomeNameOfTheDayService {
    private static var cachedNames: [AllahNameDetail]?

    /// Device-local calendar day key (`yyyy-MM-dd`), used to detect day rollovers.
    static func localDayKey(for date: Date = .now) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        guard let y = c.year, let m = c.month, let d = c.day else { return "unknown" }
        return String(format: "%04d-%02d-%02d", y, m, d)
    }

    /// Seconds until the next local midnight.
    static func secondsUntilNextLocalMidnight(from date: Date = .now) -> TimeInterval {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: date)
        guard let startOfTomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday) else {
            return 24 * 60 * 60
        }
        return max(1, startOfTomorrow.timeIntervalSince(date))
    }

    static func todaysName() async throws -> AllahNameDetail {
        let names = try await fetchAllNames()
        guard !names.isEmpty else {
            throw URLError(.zeroByteResource)
        }
        return names[dailyIndex(for: .now, count: names.count)]
    }

    private static func fetchAllNames() async throws -> [AllahNameDetail] {
        if let cachedNames, !cachedNames.isEmpty {
            return cachedNames
        }

        let client = BespokeAPIClient()
        let labels = try await client.feelingLabels()
        guard !labels.isEmpty else { return [] }

        var merged: [AllahNameDetail] = []
        try await withThrowingTaskGroup(of: [AllahNameDetail].self) { group in
            for label in labels {
                group.addTask {
                    try await client.names(feelingLabelId: label.feelingLabelId)
                }
            }
            for try await batch in group {
                merged.append(contentsOf: batch)
            }
        }

        let sorted = merged.sorted { $0.number < $1.number }
        cachedNames = sorted
        return sorted
    }

    /// Stable pseudo-random index for a given calendar day.
    private static func dailyIndex(for date: Date, count: Int) -> Int {
        let calendar = Calendar.current
        let day = calendar.ordinality(of: .day, in: .year, for: date) ?? 1
        let year = calendar.component(.year, from: date)
        var hasher = Hasher()
        hasher.combine(year)
        hasher.combine(day)
        return abs(hasher.finalize()) % count
    }
}
