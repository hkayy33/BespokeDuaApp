import Foundation
import UserNotifications

#if canImport(UIKit)
import UIKit
#endif

struct NameQuizDeepLink: Hashable, Sendable {
    let nameNumber: Int
    let prompt: String
}

enum DailyNameNotificationCopy {
    static func title(for name: AllahNameDetail) -> String {
        let transliteration = trimmed(name.transliteration)
        return transliteration.isEmpty ? "Daily 99 name" : transliteration
    }

    static func subtitle(for name: AllahNameDetail) -> String {
        let translation = trimmed(name.translation)
        return translation.isEmpty ? "Daily 99 name" : translation
    }

    static func body(for name: AllahNameDetail) -> String {
        let meaning = trimmed(name.meaning)
        if !meaning.isEmpty { return meaning }
        let translation = trimmed(name.translation)
        if !translation.isEmpty { return translation }
        return "One of the 99 names of Allah."
    }

    private static func trimmed(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

@MainActor
@Observable
final class NameQuizRouter {
    static let shared = NameQuizRouter()

    private nonisolated static let pendingNameNumberKey = "nameQuizPendingNameNumber"
    private nonisolated static let pendingPromptKey = "nameQuizPendingPrompt"

    var pending: NameQuizDeepLink?

    private init() {
        pending = Self.storedLink()
    }

    func open(_ link: NameQuizDeepLink) {
        pending = link
        Self.store(link)
        NotificationCenter.default.post(name: .nameQuizOpened, object: link)
    }

    func consume() -> NameQuizDeepLink? {
        let link = pending ?? Self.storedLink()
        pending = nil
        Self.clearStored()
        return link
    }

    nonisolated static func store(_ link: NameQuizDeepLink) {
        let defaults = UserDefaults.standard
        defaults.set(link.nameNumber, forKey: pendingNameNumberKey)
        defaults.set(link.prompt, forKey: pendingPromptKey)
    }

    private static func storedLink() -> NameQuizDeepLink? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: pendingNameNumberKey) != nil else { return nil }
        let number = defaults.integer(forKey: pendingNameNumberKey)
        guard number > 0 else { return nil }
        return NameQuizDeepLink(
            nameNumber: number,
            prompt: defaults.string(forKey: pendingPromptKey) ?? ""
        )
    }

    private static func clearStored() {
        let defaults = UserDefaults.standard
        defaults.removeObject(forKey: pendingNameNumberKey)
        defaults.removeObject(forKey: pendingPromptKey)
    }
}

extension Notification.Name {
    static let nameQuizOpened = Notification.Name("bespokeDua.nameQuizOpened")
}

@MainActor
@Observable
final class NameQuizNotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NameQuizNotificationService()

    static let defaultHour = 9
    static let defaultMinute = 0

    private static let enabledKey = "nameQuizNotificationsEnabled"
    private static let hourKey = "nameQuizReminderHour"
    private static let minuteKey = "nameQuizReminderMinute"
    /// One-time announcement for this update. Do not reuse this id for a later feature.
    private static let whatsNewKey = "whatsNewSeen.dailyNameQuiz"
    private static let identifierPrefix = "nameQuiz."
    private nonisolated static let kind = "nameQuiz"
    private static let scheduledDayCount = 28

    private(set) var prefersReminders: Bool
    private(set) var reminderHour: Int
    private(set) var reminderMinute: Int
    private(set) var authorizationStatus: UNAuthorizationStatus = .notDetermined
    private(set) var isUpdating = false
    private(set) var hasSeenWhatsNew: Bool
    var statusMessage: String?

    var shouldPresentWhatsNew: Bool {
        !hasSeenWhatsNew
    }

    var isAuthorized: Bool {
        switch authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            true
        default:
            false
        }
    }

    var remindersAreOn: Bool {
        prefersReminders && isAuthorized
    }

    private let defaults: UserDefaults
    private let center: UNUserNotificationCenter

    private override init() {
        defaults = .standard
        center = .current()
        if defaults.object(forKey: Self.enabledKey) == nil {
            prefersReminders = true
            defaults.set(true, forKey: Self.enabledKey)
        } else {
            prefersReminders = defaults.bool(forKey: Self.enabledKey)
        }
        let storedHour = defaults.object(forKey: Self.hourKey) as? Int
        let storedMinute = defaults.object(forKey: Self.minuteKey) as? Int
        reminderHour = storedHour ?? Self.defaultHour
        reminderMinute = storedMinute ?? Self.defaultMinute
        hasSeenWhatsNew = defaults.bool(forKey: Self.whatsNewKey)
        super.init()
        center.delegate = self
    }

    /// Call only after the one-time What's New modal has been dismissed.
    func completeWhatsNewAndRequestPermission() async {
        if !hasSeenWhatsNew {
            hasSeenWhatsNew = true
            defaults.set(true, forKey: Self.whatsNewKey)
        }

        await refreshAuthorizationStatusOnly()
        guard prefersReminders, !isAuthorized else {
            if prefersReminders && isAuthorized {
                await rescheduleUpcomingQuizzes(showUpdating: false)
            }
            if isAuthorized {
                registerForRemoteNotifications()
            }
            return
        }

        isUpdating = true
        defer { isUpdating = false }

        let granted = await requestAuthorizationIfNeeded()
        await refreshAuthorizationStatusOnly()
        if granted {
            await rescheduleUpcomingQuizzes(showUpdating: false)
            registerForRemoteNotifications()
        } else if authorizationStatus == .denied {
            statusMessage = "Notifications are off for Bespoke Dua. Turn them on in Settings to get the daily 99 name."
        }
    }

    func refreshAuthorizationStatus() async {
        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus
        if prefersReminders && isAuthorized {
            await rescheduleUpcomingQuizzes(showUpdating: false)
        }
        if isAuthorized {
            registerForRemoteNotifications()
        }
    }

    func setRemindersEnabled(_ enabled: Bool) async {
        statusMessage = nil
        if !enabled {
            prefersReminders = false
            defaults.set(false, forKey: Self.enabledKey)
            await cancelScheduledQuizzes()
            return
        }

        isUpdating = true
        defer { isUpdating = false }

        let granted = await requestAuthorizationIfNeeded()
        await refreshAuthorizationStatusOnly()
        guard granted else {
            prefersReminders = false
            defaults.set(false, forKey: Self.enabledKey)
            statusMessage = authorizationStatus == .denied
                ? "Notifications are off for Bespoke Dua. Turn them on in Settings to get the daily 99 name."
                : "Notification permission is needed for the daily 99 name."
            return
        }

        prefersReminders = true
        defaults.set(true, forKey: Self.enabledKey)
        await rescheduleUpcomingQuizzes(showUpdating: false)
        if statusMessage == nil {
            BespokeHaptics.success()
        }
    }

    func updateReminderTime(hour: Int, minute: Int) async {
        reminderHour = min(23, max(0, hour))
        reminderMinute = min(59, max(0, minute))
        defaults.set(reminderHour, forKey: Self.hourKey)
        defaults.set(reminderMinute, forKey: Self.minuteKey)
        guard prefersReminders, isAuthorized else { return }
        await rescheduleUpcomingQuizzes(showUpdating: true)
    }

    func openSystemSettings() {
        #if canImport(UIKit)
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
        #endif
    }

    func rescheduleUpcomingQuizzes(showUpdating: Bool = false) async {
        guard prefersReminders else { return }
        await refreshAuthorizationStatusOnly()
        guard isAuthorized else { return }

        if showUpdating {
            isUpdating = true
        }
        defer {
            if showUpdating {
                isUpdating = false
            }
        }

        do {
            let names = try await HomeNameOfTheDayService.allNames()
            guard !names.isEmpty else {
                statusMessage = "Couldn't load the 99 names just now. Try again in a moment."
                return
            }

            await cancelScheduledQuizzes()

            let calendar = Calendar.current
            let now = Date()
            var scheduled = 0

            for offset in 0..<Self.scheduledDayCount {
                guard let day = calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now)) else {
                    continue
                }
                var components = calendar.dateComponents([.year, .month, .day], from: day)
                components.hour = reminderHour
                components.minute = reminderMinute
                guard let fireDate = calendar.date(from: components), fireDate > now else { continue }

                let name = names[HomeNameOfTheDayService.quizIndex(for: day, count: names.count)]
                let content = UNMutableNotificationContent()
                content.title = "Today's name"
                content.subtitle = DailyNameNotificationCopy.title(for: name)
                content.body = notificationBody(for: name)
                content.sound = .default
                content.threadIdentifier = Self.kind
                content.userInfo = [
                    "kind": Self.kind,
                    "nameNumber": name.number,
                    "prompt": content.body
                ]

                let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
                let dayKey = HomeNameOfTheDayService.localDayKey(for: day)
                let request = UNNotificationRequest(
                    identifier: Self.identifierPrefix + dayKey,
                    content: content,
                    trigger: trigger
                )
                try await center.add(request)
                scheduled += 1
            }

            statusMessage = scheduled == 0
                ? "Today's reminder time has passed. The next name is scheduled for tomorrow."
                : nil
        } catch {
            statusMessage = "Couldn't set up the daily 99 name just now. Check your connection and try again."
        }
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        if Self.isNameQuiz(notification) || Self.isDuaFeedReaction(notification) {
            if Self.isDuaFeedReaction(notification) {
                DuaFeedReactionNotifier.markDelivered()
            }
            return [.banner, .list, .sound]
        }
        return []
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        // Must call completionHandler on the main thread. When the app is in the
        // background, UIKit snapshots the window as this callback finishes.
        let finish = {
            Self.handleNotificationTap(response)
            completionHandler()
        }
        if Thread.isMainThread {
            finish()
        } else {
            DispatchQueue.main.async(execute: finish)
        }
    }

    private nonisolated static func handleNotificationTap(_ response: UNNotificationResponse) {
        if isDuaFeedReaction(response.notification) {
            DuaFeedReactionRouter.open()
            return
        }
        if isAppUpdate(response.notification) {
            MainActor.assumeIsolated {
                AppUpdateReminderService.openAppStore()
            }
            return
        }
        guard let link = deepLink(from: response.notification) else { return }
        NameQuizRouter.store(link)
        MainActor.assumeIsolated {
            NameQuizRouter.shared.open(link)
        }
    }

    private func notificationBody(for name: AllahNameDetail) -> String {
        let translation = DailyNameNotificationCopy.subtitle(for: name)
        let meaning = DailyNameNotificationCopy.body(for: name)
        if translation.isEmpty || meaning == translation {
            return meaning
        }
        return "\(translation). \(meaning)"
    }

    private func requestAuthorizationIfNeeded() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        default:
            return false
        }
    }

    private func registerForRemoteNotifications() {
        #if canImport(UIKit)
        UIApplication.shared.registerForRemoteNotifications()
        #endif
    }

    private func refreshAuthorizationStatusOnly() async {
        let settings = await center.notificationSettings()
        authorizationStatus = settings.authorizationStatus
    }

    private func cancelScheduledQuizzes() async {
        let pending = await center.pendingNotificationRequests()
        let identifiers = pending
            .map(\.identifier)
            .filter { $0.hasPrefix(Self.identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    private nonisolated static func integer(_ value: Any?) -> Int? {
        switch value {
        case let number as Int:
            return number
        case let number as Int64:
            return Int(number)
        case let number as NSNumber:
            return number.intValue
        case let text as String:
            return Int(text)
        default:
            return nil
        }
    }

    private nonisolated static func isNameQuiz(_ notification: UNNotification) -> Bool {
        notification.request.content.userInfo["kind"] as? String == kind
    }

    private nonisolated static func isAppUpdate(_ notification: UNNotification) -> Bool {
        notification.request.content.userInfo["kind"] as? String == AppUpdateReminderService.kind
    }

    private nonisolated static func isDuaFeedReaction(_ notification: UNNotification) -> Bool {
        let info = notification.request.content.userInfo
        if let kind = info["kind"] as? String, kind == DuaFeedReactionNotifier.kind {
            return true
        }
        return notification.request.content.title.contains("remembered in someone's dua")
    }

    private nonisolated static func deepLink(from notification: UNNotification) -> NameQuizDeepLink? {
        let info = notification.request.content.userInfo
        guard info["kind"] as? String == kind else { return nil }
        guard let number = integer(info["nameNumber"]) else { return nil }
        let prompt = (info["prompt"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = notification.request.content.body
        return NameQuizDeepLink(
            nameNumber: number,
            prompt: (prompt?.isEmpty == false ? prompt! : fallback)
        )
    }
}
