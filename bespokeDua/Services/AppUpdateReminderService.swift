import Foundation
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif

/// Schedules a local reminder only when this install is older than the live App Store version.
enum AppUpdateReminderService {
    nonisolated static let kind = "appUpdate"
    private static let identifier = "appUpdate.reminder"
    private static let latestVersionKey = "appUpdate.latestVersion"
    private static let itunesAppID = "6761731591"
    /// Don't interrupt the session that discovered the update.
    private static let reminderDelay: TimeInterval = 20 * 60 * 60

    static func refresh() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard isAuthorized(settings.authorizationStatus) else {
            await cancel()
            return
        }

        guard let latest = await latestAppStoreVersion() else { return }

        if !isInstalledVersionOlder(than: latest) {
            UserDefaults.standard.removeObject(forKey: latestVersionKey)
            await cancel()
            return
        }

        let pending = await UNUserNotificationCenter.current().pendingNotificationRequests()
        let alreadyScheduled = pending.contains { $0.identifier == identifier }
        let alreadyNoted = UserDefaults.standard.string(forKey: latestVersionKey) == latest
        if alreadyScheduled && alreadyNoted { return }

        await cancel()

        let content = UNMutableNotificationContent()
        content.title = "Update BespokeDua"
        content.body = "A newer version is on the App Store. Update to get the latest duas and fixes."
        content.sound = .default
        content.userInfo = [
            "kind": kind,
            "latestVersion": latest
        ]

        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: reminderDelay, repeats: false)
        let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
        try? await UNUserNotificationCenter.current().add(request)
        UserDefaults.standard.set(latest, forKey: latestVersionKey)
    }

    static func openAppStore() {
        #if canImport(UIKit)
        UIApplication.shared.open(BespokeAppMetadata.appStoreURL)
        #endif
    }

    private static func isAuthorized(_ status: UNAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return true
        default:
            return false
        }
    }

    private static func cancel() async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }

    private static func isInstalledVersionOlder(than latest: String) -> Bool {
        compare(BespokeAppMetadata.shortVersionString, latest) == .orderedAscending
    }

    private static func compare(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let left = versionParts(lhs)
        let right = versionParts(rhs)
        let count = max(left.count, right.count)
        for index in 0..<count {
            let l = index < left.count ? left[index] : 0
            let r = index < right.count ? right[index] : 0
            if l < r { return .orderedAscending }
            if l > r { return .orderedDescending }
        }
        return .orderedSame
    }

    private static func versionParts(_ version: String) -> [Int] {
        version
            .split(separator: ".")
            .map { Int($0.filter(\.isNumber)) ?? 0 }
    }

    private static func latestAppStoreVersion() async -> String? {
        guard let url = URL(string: "https://itunes.apple.com/lookup?id=\(itunesAppID)&country=gb") else {
            return nil
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 12
        guard
            let (data, response) = try? await URLSession.shared.data(for: request),
            let http = response as? HTTPURLResponse,
            (200..<300).contains(http.statusCode),
            let payload = try? JSONDecoder().decode(LookupResponse.self, from: data)
        else { return nil }
        let version = payload.results.first?.version.trimmingCharacters(in: .whitespacesAndNewlines)
        return version?.isEmpty == false ? version : nil
    }

    private struct LookupResponse: Decodable {
        let results: [LookupResult]
    }

    private struct LookupResult: Decodable {
        let version: String
    }
}
