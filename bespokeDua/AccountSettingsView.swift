import SwiftUI

struct AccountSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var initialTab: ProfileView.SettingsTab = .profile

    var body: some View {
        NavigationStack {
            ProfileView(surface: .accountSettings, initialSettingsTab: initialTab)
                .bespokeMainNavigationToolbar(title: "Account settings", onClose: { dismiss() })
                .bespokeStyledNavigationBar()
        }
    }
}
