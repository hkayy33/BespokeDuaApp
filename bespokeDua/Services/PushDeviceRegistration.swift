import Foundation
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif

@MainActor
enum PushDeviceRegistration {
    private static let tokenKey = "bespoke.apnsDeviceToken"

    static func storeDeviceToken(_ deviceToken: Data) {
        let hex = deviceToken.map { String(format: "%02x", $0) }.joined()
        UserDefaults.standard.set(hex, forKey: tokenKey)
    }

    static func registerIfAuthorized(session: AppSession) async {
        #if canImport(UIKit)
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            UIApplication.shared.registerForRemoteNotifications()
        default:
            return
        }
        await uploadStoredToken(session: session)
        #endif
    }

    static func uploadStoredToken(session: AppSession) async {
        guard let userId = session.currentUser?.userId else { return }
        guard let token = UserDefaults.standard.string(forKey: tokenKey), !token.isEmpty else { return }

        #if DEBUG
        let sandbox = true
        #else
        let sandbox = false
        #endif

        try? await session.api().registerPushDevice(userId: userId, deviceToken: token, sandbox: sandbox)
    }
}

#if canImport(UIKit)
final class BespokePushAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        PushDeviceRegistration.storeDeviceToken(deviceToken)
        NotificationCenter.default.post(name: .apnsDeviceTokenUpdated, object: nil)
    }
}

extension Notification.Name {
    static let apnsDeviceTokenUpdated = Notification.Name("bespokeDua.apnsDeviceTokenUpdated")
}
#endif
