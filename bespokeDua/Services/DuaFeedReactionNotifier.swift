import Foundation
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif

enum DuaFeedReactionRouter {
    private static let pendingOpenKey = "duaFeedReaction.pendingOpenMyPosts"

    static var pendingOpenMyPosts: Bool {
        get { UserDefaults.standard.bool(forKey: pendingOpenKey) }
        set { UserDefaults.standard.set(newValue, forKey: pendingOpenKey) }
    }

    static func open() {
        if Thread.isMainThread {
            performOpen()
        } else {
            DispatchQueue.main.async {
                performOpen()
            }
        }
    }

    /// Call when the scene becomes active. A background notification tap must not
    /// touch navigation until UIKit's window is active, or it throws
    /// "Call must be made on main thread".
    static func deliverIfSceneIsActive() {
        if Thread.isMainThread {
            postIfReady()
        } else {
            DispatchQueue.main.async {
                postIfReady()
            }
        }
    }

    private static func performOpen() {
        pendingOpenMyPosts = true
        postIfReady()
    }

    private static func postIfReady() {
        guard pendingOpenMyPosts else { return }
        #if canImport(UIKit)
        guard UIApplication.shared.applicationState == .active else { return }
        #endif
        NotificationCenter.default.post(name: .duaFeedReactionOpened, object: nil)
    }

    static func consumeOpenMyPosts() -> Bool {
        guard pendingOpenMyPosts else { return false }
        pendingOpenMyPosts = false
        return true
    }
}

extension Notification.Name {
    static let duaFeedReactionOpened = Notification.Name("bespokeDua.duaFeedReactionOpened")
}

/// Local reminder when someone makes dua on one of the current user's feed posts.
enum DuaFeedReactionNotifier {
    nonisolated static let kind = "duaFeedReaction"

    private static let countsKeyPrefix = "duaFeed.ownPostDuaCounts."
    private static var lastDeliveredAt: Date?

    static func noteOwnPostCounts(userId: Int, posts: [DuaFeedPost]) async {
        let key = countsKeyPrefix + "\(userId)"
        let stored = storedCounts(forKey: key)
        var next = stored
        var gainedAReaction = false

        for post in posts {
            let previous = stored[post.serverPostId]
            if let previous, post.duaCount > previous {
                gainedAReaction = true
            }
            next[post.serverPostId] = post.duaCount
        }

        let activeIDs = Set(posts.map(\.serverPostId))
        next = next.filter { activeIDs.contains($0.key) }
        saveCounts(next, forKey: key)

        guard gainedAReaction else { return }
        await deliverRememberedNotification()
    }

    static func markDelivered() {
        lastDeliveredAt = Date()
    }

    static func requestAuthorizationIfNeeded() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    static func deliverRememberedNotification() async {
        let now = Date()
        if let lastDeliveredAt, now.timeIntervalSince(lastDeliveredAt) < 20 {
            return
        }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
        }
        let refreshed = await UNUserNotificationCenter.current().notificationSettings()
        guard isAuthorized(refreshed.authorizationStatus) else { return }

        let content = UNMutableNotificationContent()
        content.title = "🤍 You were remembered in someone's dua"
        content.body = "May Allah accept it. Ameen."
        content.sound = .default
        content.userInfo = ["kind": kind]

        let request = UNNotificationRequest(
            identifier: "duaFeedReaction.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )
        do {
            try await UNUserNotificationCenter.current().add(request)
            lastDeliveredAt = now
        } catch {
            return
        }
    }

    private static func isAuthorized(_ status: UNAuthorizationStatus) -> Bool {
        switch status {
        case .authorized, .provisional, .ephemeral:
            true
        default:
            false
        }
    }

    private static func storedCounts(forKey key: String) -> [String: Int] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: Int].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private static func saveCounts(_ counts: [String: Int], forKey key: String) {
        guard let data = try? JSONEncoder().encode(counts) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
