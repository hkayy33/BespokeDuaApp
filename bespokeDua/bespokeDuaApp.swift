//
//  bespokeDuaApp.swift
//  bespokeDua
//
//  Created by Hassan Kambala on 25/03/2026.
//

import SwiftUI
import UserNotifications
#if canImport(UIKit)
import UIKit
#endif

@main
struct bespokeDuaApp: App {
    #if canImport(UIKit)
    @UIApplicationDelegateAdaptor(BespokePushAppDelegate.self) private var pushAppDelegate
    #endif
    @State private var session = AppSession()
    @State private var subscriptionManager = SubscriptionManager()
    @State private var nameQuiz = NameQuizNotificationService.shared
    @State private var showMainContent = false

    init() {
        BespokeFonts.register()
        UNUserNotificationCenter.current().delegate = NameQuizNotificationService.shared
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if showMainContent {
                    ContentView()
                        .environment(session)
                        .environment(subscriptionManager)
                        .environment(nameQuiz)
                        .preferredColorScheme(.light)
                        .transition(.opacity)
                } else {
                    SplashLoadingView()
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.4), value: showMainContent)
            .task {
                async let warmup: Void = session.warmUpAppContent()
                try? await Task.sleep(for: .milliseconds(200))
                await warmup
                showMainContent = true
                session.startDuaFeedAutoRefresh()
            }
            .onOpenURL { url in
                Task { await session.handleAuthURL(url) }
            }
            .onContinueUserActivity(NSUserActivityTypeBrowsingWeb) { activity in
                guard let url = activity.webpageURL else { return }
                Task { await session.handleAuthURL(url) }
            }
            .onReceive(NotificationCenter.default.publisher(for: .apnsDeviceTokenUpdated)) { _ in
                Task { await PushDeviceRegistration.uploadStoredToken(session: session) }
            }
            .task {
                await PushDeviceRegistration.registerIfAuthorized(session: session)
            }
        }
    }
}
