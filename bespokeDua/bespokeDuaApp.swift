//
//  bespokeDuaApp.swift
//  bespokeDua
//
//  Created by Hassan Kambala on 25/03/2026.
//

import SwiftUI

@main
struct bespokeDuaApp: App {
    @State private var session = AppSession()
    @State private var subscriptionManager = SubscriptionManager()
    @State private var showMainContent = false

    init() {
        BespokeFonts.register()
    }

    var body: some Scene {
        WindowGroup {
            Group {
                if showMainContent {
                    ContentView()
                        .environment(session)
                        .environment(subscriptionManager)
                        .preferredColorScheme(.light)
                        .transition(.opacity)
                } else {
                    SplashLoadingView()
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.4), value: showMainContent)
            .task {
                // Short delay so the splash isn’t a flash; keep well under 1s for perceived startup speed.
                try? await Task.sleep(for: .milliseconds(400))
                showMainContent = true
            }
        }
    }
}
