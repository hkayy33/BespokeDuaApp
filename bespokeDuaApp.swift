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

    init() {
        BespokeFonts.register()
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(session)
                .preferredColorScheme(.light)
        }
    }
}
