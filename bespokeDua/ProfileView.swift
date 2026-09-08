import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct ProfileView: View {
    enum Surface {
        case mainTab
        case accountSettings
    }

    enum SettingsTab: Hashable {
        case profile
        case subscription
    }

    var surface: Surface = .mainTab
    var initialSettingsTab: SettingsTab = .profile

    @Environment(AppSession.self) private var session
    @Environment(SubscriptionManager.self) private var subscriptionManager
    @Environment(\.openURL) private var openURL
    @Environment(\.mainTabBarClearance) private var mainTabBarClearance

    @State private var selectedTab: ProfileTab
    @State private var showUpgradeModal = false

    @State private var username = ""
    @State private var usernameTouched = false
    @State private var usernameSuccess: String?
    @State private var usernameActionError: String?

    @State private var currentPassword = ""
    @State private var newPassword = ""
    @State private var confirmPassword = ""
    @State private var passwordTouched = false
    @State private var passwordSuccess: String?
    @State private var passwordActionError: String?
    @State private var resetEmailSent = false

    @State private var showDeleteConfirmation = false
    @State private var deleteInFlight = false
    @State private var deleteError: String?

    @State private var showLogoutConfirmation = false

    init(surface: Surface = .mainTab, initialSettingsTab: SettingsTab = .profile) {
        self.surface = surface
        self.initialSettingsTab = initialSettingsTab
        _selectedTab = State(
            initialValue: initialSettingsTab == .subscription ? .subscription : .profile
        )
    }

    private enum ProfileTab: Hashable {
        case profile, subscription, settings
    }

    private static let manageSubscriptionsURL = URL(string: "https://apps.apple.com/account/subscriptions")!
    private static let privacyPolicyURL = URL(string: "https://www.bespokedua.com/privacy-policy")!
    private static let termsOfUseURL = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if session.isLoggedIn {
                    profileHeader
                    profileTabPicker

                    switch selectedTab {
                    case .profile:
                        usernameSection
                        passwordSection
                        if surface == .accountSettings {
                            NameQuizSettingsCard()
                            dangerSection
                        }
                    case .subscription:
                        subscriptionSection
                    case .settings:
                        NameQuizSettingsCard()
                        dangerSection
                    }

                    if surface == .accountSettings {
                        legalLinksFooter
                    }
                } else {
                    signedOutContent
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 24 + mainTabBarClearance)
        }
        .scrollIndicators(.hidden, axes: .vertical)
        .scrollDismissesKeyboard(.interactively)
        .background(BespokeColor.pageBackground)
        .onAppear(perform: syncFromSession)
        .onChange(of: session.currentUser?.username) { _, _ in
            syncFromSession()
        }
        .overlay {
            if showDeleteConfirmation {
                BespokeConfirmModal(
                    title: "Delete account?",
                    message: "Permanently delete your account and all data.",
                    confirmTitle: "Delete",
                    inFlight: deleteInFlight,
                    errorMessage: deleteError,
                    onCancel: {
                        deleteError = nil
                        showDeleteConfirmation = false
                    },
                    onConfirm: { Task { await confirmDeleteAccount() } }
                )
                .transition(.opacity)
            }
        }
        .overlay {
            if showLogoutConfirmation {
                BespokeLogoutModal(
                    message: "You’ll need to sign in again to access your saved duas and account settings.",
                    onCancel: { showLogoutConfirmation = false },
                    onConfirm: {
                        showLogoutConfirmation = false
                        session.logout()
                    }
                )
                .transition(.opacity.combined(with: .scale(scale: 0.94)))
            }
        }
        .animation(.easeInOut(duration: 0.28), value: showDeleteConfirmation)
        .animation(.easeInOut(duration: 0.28), value: showLogoutConfirmation)
        .overlay {
            if showUpgradeModal {
                UpgradeInfoModalView(
                    isPresented: $showUpgradeModal,
                    emphasizeDailyLimit: false
                )
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.28), value: showUpgradeModal)
        .task(id: selectedTab) {
            guard session.isLoggedIn, selectedTab == .subscription else { return }
            subscriptionManager.updateDatabaseSubscriptionStatus(plan: session.currentUser?.plan)
            await subscriptionManager.loadProduct()
            await subscriptionManager.refreshEntitlements()
        }
    }

    // MARK: - Signed in

    private var profileHeader: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 72))
                .foregroundStyle(BespokeColor.forest)
                .accessibilityHidden(true)

            if let user = session.currentUser {
                Text(user.username)
                    .font(BespokeFont.display(22))
                    .foregroundStyle(BespokeColor.bodyText)
                    .multilineTextAlignment(.center)

                Text(user.email)
                    .font(BespokeFont.inter(14, weight: .regular))
                    .foregroundStyle(BespokeColor.muted)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var profileTabPicker: some View {
        HStack(spacing: 4) {
            profileTabButton(title: "Profile", tab: .profile)
            profileTabButton(title: "Subscription", tab: .subscription)
            if surface == .mainTab {
                profileTabButton(title: "Settings", tab: .settings)
            }
        }
        .padding(4)
        .background(BespokeColor.authToggleBg)
        .clipShape(RoundedRectangle(cornerRadius: 999, style: .continuous))
    }

    private func profileTabButton(title: String, tab: ProfileTab) -> some View {
        Button {
            selectedTab = tab
        } label: {
            Text(title)
                .font(BespokeFont.inter(13, weight: .bold))
                .foregroundStyle(selectedTab == tab ? Color.white : BespokeColor.forest)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(selectedTab == tab ? BespokeColor.gold : Color.clear)
                .clipShape(Capsule())
                .bespokeButtonHitArea(Capsule())
        }
        .buttonStyle(BespokePlainButtonStyle())
    }

    private var subscriptionSection: some View {
        VStack(spacing: 16) {
            profileCard(
                title: "Current plan",
                borderHighlight: subscriptionManager.isSubscribed ? .gold : .forest
            ) {
                if let user = session.currentUser {
                    let subscribed = subscriptionManager.isSubscribed

                    if subscribed {
                        HStack(spacing: 8) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 16, weight: .semibold))
                            Text("Bespoke Plus")
                                .font(BespokeFont.inter(18, weight: .semibold))
                        }
                        .foregroundStyle(LinearGradient.bespokeGold)

                        plusFeaturesList
                    } else {
                        Text(planHeadline(plan: user.plan, isSubscribed: false))
                            .font(BespokeFont.inter(18, weight: .semibold))
                            .foregroundStyle(BespokeColor.forest)

                        Text(planSubtitle(isSubscribed: false, userId: user.userId))
                            .font(BespokeFont.inter(14, weight: .regular))
                            .foregroundStyle(BespokeColor.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if subscribed {
                        if let statusLine = subscriptionManager.appleSubscriptionStatusLine {
                            Text(statusLine)
                                .font(BespokeFont.inter(14, weight: .semibold))
                                .foregroundStyle(BespokeColor.bodyText)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Button {
                            openURL(Self.manageSubscriptionsURL)
                        } label: {
                            Label("Manage in App Store", systemImage: "creditcard")
                                .font(BespokeFont.inter(16, weight: .semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                        }
                        .buttonStyle(.bordered)
                        .tint(BespokeColor.forest)
                        .padding(.top, 4)
                    }
                }
            }

            if session.currentUser != nil, !subscriptionManager.isSubscribed {
                bespokePlusUpgradeCard
            }
        }
    }

    private var bespokePlusUpgradeCard: some View {
        profileCard(title: "Bespoke Plus") {
            plusFeaturesList

            if subscriptionManager.loadInFlight, subscriptionManager.product == nil {
                HStack(spacing: 10) {
                    ProgressView()
                        .tint(BespokeColor.forest)
                    Text("Loading subscription…")
                        .font(BespokeFont.inter(14, weight: .medium))
                        .foregroundStyle(BespokeColor.muted)
                }
                .padding(.top, 4)
            } else {
                Text(subscriptionManager.eligibleIntroOffer?.headline ?? BespokePlusOfferCopy.freeMonthHeadline)
                    .font(BespokeFont.inter(18, weight: .semibold))
                    .foregroundStyle(BespokeColor.forest)
                    .padding(.top, 2)
                if let thenPrice = subscriptionManager.eligibleIntroOffer?.thenPriceLine
                    ?? subscriptionManager.plusMonthlyDisplayPrice {
                    Text("then \(thenPrice)")
                        .font(BespokeFont.inter(14, weight: .medium))
                        .foregroundStyle(BespokeColor.muted)
                }
            }

            Button {
                showUpgradeModal = true
            } label: {
                Label(BespokePlusOfferCopy.startFreeMonth, systemImage: "sparkles")
                    .font(BespokeFont.inter(16, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(LinearGradient.bespokeGold)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .shadow(color: BespokeColor.goldDeep.opacity(0.22), radius: 8, x: 0, y: 4)
            }
            .buttonStyle(BespokePlainButtonStyle())
            .padding(.top, 4)
        }
    }

    private var plusFeaturesList: some View {
        BespokePlusFeaturesList()
    }

    private var legalLinksFooter: some View {
        HStack(spacing: 18) {
            Link("Terms and Conditions", destination: Self.termsOfUseURL)
            Link("Privacy Policy", destination: Self.privacyPolicyURL)
        }
        .font(BespokeFont.inter(15, weight: .semibold))
        .foregroundStyle(BespokeColor.goldDeep)
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
    }

    private func planHeadline(plan: String, isSubscribed: Bool) -> String {
        BespokeSubscriptionDisplay.planTitle(plan: plan, isSubscribed: isSubscribed)
    }

    private func planSubtitle(isSubscribed: Bool, userId: Int) -> String {
        if isSubscribed {
            return "Unlimited bespoke duas."
        }
        let remaining = DailyGenerationQuota.duasRemainingToday(userId: userId)
        let cap = DailyGenerationQuota.freeDailyLimit
        return "\(remaining)/\(cap) duas left today · 1 month free for unlimited"
    }

    private var usernameSection: some View {
        profileCard(title: "Username") {
            profileField {
                TextField("", text: $username, prompt: Text("Username").foregroundStyle(BespokeColor.subtle))
                    .textContentType(.username)
                    .autocorrectionDisabled()
                    .onChange(of: username) { oldValue, newValue in
                        guard oldValue != newValue else { return }
                        // Ignore programmatic sync from session (empty → loaded username).
                        if oldValue.isEmpty, newValue == session.currentUser?.username {
                            return
                        }
                        usernameTouched = true
                        usernameSuccess = nil
                        usernameActionError = nil
                    }
            }

            Text(UsernameRules.hint)
                .font(BespokeFont.inter(12.8, weight: .regular))
                .foregroundStyle(BespokeColor.fieldLabel.opacity(0.65))

            if let usernameErrorMessage {
                profileErrorText(usernameErrorMessage)
            }

            if let usernameSuccess {
                profileSuccessText(usernameSuccess)
            }

            profilePrimaryButton(
                title: "Save username",
                disabled: session.authInFlight || !canSaveUsername
            ) {
                Task { await saveUsername() }
            }
        }
    }

    private var passwordSection: some View {
        profileCard(title: "Password") {
            if session.canChangePasswordInApp {
                profileSecureField(label: "Current password", text: $currentPassword)
                profileSecureField(label: "New password", text: $newPassword)
                profileSecureField(label: "Confirm new password", text: $confirmPassword)

                if let passwordErrorMessage {
                    profileErrorText(passwordErrorMessage)
                }

                if let passwordSuccess {
                    profileSuccessText(passwordSuccess)
                }

                profilePrimaryButton(
                    title: "Update password",
                    disabled: session.authInFlight || !canSavePassword
                ) {
                    Task { await savePassword() }
                }
            } else {
                Text("We'll email you a link to choose a new password.")
                    .font(BespokeFont.inter(14, weight: .regular))
                    .foregroundStyle(BespokeColor.muted)
                    .fixedSize(horizontal: false, vertical: true)

                if resetEmailSent {
                    profileSuccessText("Password reset link sent. Check your inbox.")
                }

                profilePrimaryButton(
                    title: resetEmailSent ? "Link sent" : "Email reset link",
                    disabled: session.authInFlight || resetEmailSent
                ) {
                    Task { await sendResetEmail() }
                }
            }
        }
    }

    private var dangerSection: some View {
        profileCard(title: "Settings") {
            Button(role: .destructive) {
                deleteError = nil
                showDeleteConfirmation = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "trash")
                        .font(.system(size: 16, weight: .medium))
                    Text("Delete account")
                        .font(BespokeFont.inter(16, weight: .semibold))
                }
                .foregroundStyle(BespokeColor.error)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(BespokePlainButtonStyle())

            Rectangle()
                .fill(BespokeColor.sectionRule)
                .frame(height: 1)
                .padding(.vertical, 4)

            Button {
                showLogoutConfirmation = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 16, weight: .medium))
                    Text("Log out")
                        .font(BespokeFont.inter(16, weight: .semibold))
                }
                .foregroundStyle(BespokeColor.forest)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(BespokePlainButtonStyle())
        }
    }

    // MARK: - Signed out

    private var signedOutContent: some View {
        VStack(spacing: 20) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 72))
                .foregroundStyle(BespokeColor.forest)
                .accessibilityHidden(true)

            Text("Your profile")
                .font(BespokeFont.display(22))
                .foregroundStyle(BespokeColor.bodyText)

            Text("Sign in to manage your username, password, and account settings.")
                .font(BespokeFont.inter(15, weight: .regular))
                .foregroundStyle(BespokeColor.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            NameQuizSettingsCard()

            Button {
                session.presentAuth()
            } label: {
                Text("Sign in")
                    .font(BespokeFont.inter(17, weight: .semibold))
                    .foregroundStyle(BespokeColor.cream)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(BespokeColor.forest)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .bespokeButtonHitArea(cornerRadius: 16)
            }
            .buttonStyle(BespokePlainButtonStyle())
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    // MARK: - Actions

    private func syncFromSession() {
        username = session.currentUser?.username ?? ""
        usernameTouched = false
        usernameSuccess = nil
    }

    private func saveUsername() async {
        usernameTouched = true
        usernameSuccess = nil
        usernameActionError = nil
        guard canSaveUsername else { return }

        #if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif

        if await session.updateUsername(username) {
            usernameSuccess = "Username updated."
            usernameTouched = false
        } else {
            usernameActionError = session.authError
        }
    }

    private func savePassword() async {
        passwordTouched = true
        passwordSuccess = nil
        passwordActionError = nil
        guard canSavePassword else { return }

        #if canImport(UIKit)
        UIApplication.shared.sendAction(#selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil)
        #endif

        if await session.changePassword(currentPassword: currentPassword, newPassword: newPassword) {
            passwordSuccess = "Password updated."
            currentPassword = ""
            newPassword = ""
            confirmPassword = ""
            passwordTouched = false
        } else {
            passwordActionError = session.authError
        }
    }

    private func sendResetEmail() async {
        passwordActionError = nil
        if await session.sendPasswordResetToCurrentUser() {
            resetEmailSent = true
        } else {
            passwordActionError = session.authError
        }
    }

    private func confirmDeleteAccount() async {
        deleteInFlight = true
        deleteError = nil
        defer { deleteInFlight = false }

        do {
            try await session.deleteAccount()
            showDeleteConfirmation = false
        } catch {
            deleteError = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    // MARK: - Validation

    private var trimmedUsername: String {
        username.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var usernameErrorMessage: String? {
        if let usernameActionError { return usernameActionError }
        guard usernameTouched else { return nil }
        if trimmedUsername.isEmpty { return "Username is required." }
        if !UsernameRules.isValid(trimmedUsername) {
            return UsernameRules.invalidMessage
        }
        return nil
    }

    private var canSaveUsername: Bool {
        usernameErrorMessage == nil &&
            !trimmedUsername.isEmpty &&
            trimmedUsername != session.currentUser?.username
    }

    private var passwordErrorMessage: String? {
        if let passwordActionError { return passwordActionError }
        guard passwordTouched else { return nil }
        if currentPassword.isEmpty { return "Current password is required." }
        if newPassword.isEmpty { return "New password is required." }
        if newPassword.count < 6 { return "Password must be at least 6 characters." }
        if confirmPassword.isEmpty { return "Please confirm your new password." }
        if newPassword != confirmPassword { return "Passwords do not match." }
        return nil
    }

    private var canSavePassword: Bool {
        passwordErrorMessage == nil &&
            !currentPassword.isEmpty &&
            newPassword.count >= 6 &&
            !confirmPassword.isEmpty
    }

    // MARK: - Shared UI

    private enum ProfileCardBorderHighlight {
        case forest
        case gold
    }

    private func profileCard<Content: View>(
        title: String,
        borderHighlight: ProfileCardBorderHighlight? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(BespokeFont.inter(18, weight: .semibold))
                .foregroundStyle(BespokeColor.forest)

            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(20)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(profileCardBorder(for: borderHighlight), lineWidth: borderHighlight == nil ? 1 : 2)
        }
        .shadow(color: .black.opacity(0.04), radius: 10, x: 0, y: 4)
    }

    private func profileCardBorder(for highlight: ProfileCardBorderHighlight?) -> AnyShapeStyle {
        switch highlight {
        case .forest:
            AnyShapeStyle(BespokeColor.forest)
        case .gold:
            AnyShapeStyle(LinearGradient.bespokeGold)
        case nil:
            AnyShapeStyle(BespokeColor.cardBorder)
        }
    }

    private func profileCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        profileCard(title: title, borderHighlight: nil, content: content)
    }

    private func profileField<Content: View>(label: String? = nil, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            if let label {
                Text(label)
                    .font(BespokeFont.inter(15.2, weight: .bold))
                    .foregroundStyle(BespokeColor.fieldLabel)
            }
            content()
                .font(BespokeFont.inter(16, weight: .regular))
                .foregroundStyle(BespokeColor.bodyText)
                .padding(16)
                .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
                .background(BespokeColor.inputSurface)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(BespokeColor.forest.opacity(0.18), lineWidth: 1)
                )
        }
    }

    private func profileSecureField(label: String, text: Binding<String>) -> some View {
        profileField(label: label) {
            SecureField(label, text: text)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .onChange(of: text.wrappedValue) { _, _ in
                    passwordTouched = true
                    passwordSuccess = nil
                    passwordActionError = nil
                }
        }
    }

    private func profilePrimaryButton(title: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(BespokeFont.inter(16, weight: .semibold))
                .foregroundStyle(BespokeColor.cream)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(disabled ? BespokeColor.forest.opacity(0.45) : BespokeColor.forest)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .bespokeButtonHitArea(cornerRadius: 16)
        }
        .buttonStyle(BespokePlainButtonStyle())
        .disabled(disabled)
    }

    private func profileErrorText(_ message: String) -> some View {
        Text(message)
            .font(BespokeFont.inter(14, weight: .regular))
            .foregroundStyle(BespokeColor.error)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func profileSuccessText(_ message: String) -> some View {
        Text(message)
            .font(BespokeFont.inter(14, weight: .semibold))
            .foregroundStyle(BespokeColor.forest)
            .fixedSize(horizontal: false, vertical: true)
    }
}
