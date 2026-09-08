import SwiftUI
#if canImport(UIKit)
import UIKit
import StoreKit
#endif

@Observable
@MainActor
final class BespokeSideMenuCoordinator {
    var isPresented = false
    var accountSettingsPresented = false
    var accountSettingsTab: ProfileView.SettingsTab = .profile

    func open() {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            isPresented = true
        }
    }

    func close() {
        withAnimation(.spring(response: 0.34, dampingFraction: 0.86)) {
            isPresented = false
        }
    }

    func openAccountSettings(tab: ProfileView.SettingsTab = .profile) {
        accountSettingsTab = tab
        close()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) { [self] in
            accountSettingsPresented = true
        }
    }

    func openManageSubscription() {
        openAccountSettings(tab: .subscription)
    }

    func openSupportEmail() {
        close()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            BespokeAppMetadata.openSupportEmail()
        }
    }

    func openFeatureRequestEmail() {
        close()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            BespokeAppMetadata.openFeatureRequestEmail()
        }
    }
}

private struct OpenSideMenuKey: EnvironmentKey {
    static let defaultValue: () -> Void = {}
}

extension EnvironmentValues {
    var openSideMenu: () -> Void {
        get { self[OpenSideMenuKey.self] }
        set { self[OpenSideMenuKey.self] = newValue }
    }
}

struct BespokeMenuToolbarButton: View {
    @Environment(\.openSideMenu) private var openSideMenu

    var body: some View {
        Button(action: openSideMenu) {
            Group {
                #if canImport(UIKit)
                Image(uiImage: BespokeNavBarButtonArtwork.image(for: .menu))
                #else
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(.white)
                #endif
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(BespokePlainButtonStyle())
        .accessibilityLabel("Menu")
    }
}

struct BespokeAppLogoView: View {
    var size: CGFloat = 64

    var body: some View {
        Group {
            #if canImport(UIKit)
            if let icon = BespokeAppMetadata.appIcon {
                Image(uiImage: icon)
                    .resizable()
                    .scaledToFit()
            } else {
                Image("SplashWordmark")
                    .resizable()
                    .scaledToFit()
            }
            #else
            Image("SplashWordmark")
                .resizable()
                .scaledToFit()
            #endif
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22, style: .continuous))
        .shadow(color: .black.opacity(0.12), radius: 8, x: 0, y: 4)
    }
}

private enum BespokeSideMenuMetrics {
    static let panelWidthRatio: CGFloat = 0.82
    static let edgeActivationWidth: CGFloat = 28
}

private struct BespokeSideMenuOverlayModifier: ViewModifier {
    var coordinator: BespokeSideMenuCoordinator
    var allowsEdgeSwipe: Bool

    @Environment(\.openURL) private var openURL
    @Environment(AppSession.self) private var session

    @State private var dragTranslation: CGFloat = 0
    @State private var openingDrag: CGFloat = 0
    @State private var showLogoutConfirmation = false

    func body(content: Content) -> some View {
        content
            .simultaneousGesture(openEdgeSwipeGesture)
            .overlay {
                GeometryReader { geo in
                    let panelWidth = geo.size.width * BespokeSideMenuMetrics.panelWidthRatio
                    let panelOffset = currentPanelOffset(panelWidth: panelWidth)
                    let revealProgress = min(1, max(0, (panelWidth + panelOffset) / panelWidth))
                    let showMenu = coordinator.isPresented || openingDrag > 0

                    if showMenu {
                        ZStack(alignment: .leading) {
                            Color.black.opacity(0.38 * revealProgress)
                                .ignoresSafeArea()
                                .onTapGesture {
                                    guard !showLogoutConfirmation else { return }
                                    coordinator.close()
                                }

                            BespokeSideMenuPanel(
                                panelWidth: panelWidth,
                                onAccountSettings: { coordinator.openAccountSettings() },
                                onManageSubscription: { coordinator.openManageSubscription() },
                                onRateUs: { requestAppReview() },
                                onFeatureRequest: { coordinator.openFeatureRequestEmail() },
                                onSupportEmail: { coordinator.openSupportEmail() },
                                onAbout: {
                                    coordinator.close()
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                                        openURL(BespokeAppMetadata.websiteURL)
                                    }
                                },
                                onOpenURL: { openURL($0) },
                                onClose: { coordinator.close() },
                                onRequestLogout: { showLogoutConfirmation = true }
                            )
                            .frame(width: panelWidth)
                            .offset(x: panelOffset)
                            .allowsHitTesting(!showLogoutConfirmation)

                            if showLogoutConfirmation {
                                BespokeLogoutModal(
                                    message: "You'll need to sign in again to access saved duas and your profile.",
                                    onCancel: { showLogoutConfirmation = false },
                                    onConfirm: {
                                        showLogoutConfirmation = false
                                        coordinator.close()
                                        session.logout()
                                    }
                                )
                                .frame(width: geo.size.width, height: geo.size.height)
                                .transition(.opacity.combined(with: .scale(scale: 0.94)))
                            }
                        }
                        .transition(.opacity)
                        .gesture(closeSwipeGesture(panelWidth: panelWidth))
                    }
                }
                .ignoresSafeArea()
            }
            .animation(.spring(response: 0.34, dampingFraction: 0.86), value: coordinator.isPresented)
            .animation(.interactiveSpring(response: 0.34, dampingFraction: 0.86), value: openingDrag)
            .animation(.interactiveSpring(response: 0.34, dampingFraction: 0.86), value: dragTranslation)
            .animation(.easeInOut(duration: 0.28), value: showLogoutConfirmation)
            .onChange(of: coordinator.isPresented) { _, isPresented in
                if !isPresented {
                    showLogoutConfirmation = false
                }
            }
    }

    private func currentPanelOffset(panelWidth: CGFloat) -> CGFloat {
        if coordinator.isPresented {
            return min(0, dragTranslation)
        }
        return -panelWidth + openingDrag
    }

    private var openEdgeSwipeGesture: some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .global)
            .onChanged { value in
                guard allowsEdgeSwipe, !coordinator.isPresented else { return }
                guard value.startLocation.x <= BespokeSideMenuMetrics.edgeActivationWidth else { return }
                guard value.translation.width > 0 else { return }
                openingDrag = min(panelWidthForGesture, value.translation.width)
            }
            .onEnded { value in
                guard allowsEdgeSwipe, !coordinator.isPresented else { return }
                guard value.startLocation.x <= BespokeSideMenuMetrics.edgeActivationWidth else {
                    openingDrag = 0
                    return
                }

                let shouldOpen = openingDrag > panelWidthForGesture * 0.28
                    || value.predictedEndTranslation.width > panelWidthForGesture * 0.4
                openingDrag = 0
                if shouldOpen {
                    coordinator.open()
                }
            }
    }

    private func closeSwipeGesture(panelWidth: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 10, coordinateSpace: .global)
            .onChanged { value in
                guard coordinator.isPresented, !showLogoutConfirmation else { return }
                guard value.translation.width < 0 else {
                    dragTranslation = 0
                    return
                }
                dragTranslation = max(value.translation.width, -panelWidth)
            }
            .onEnded { value in
                guard coordinator.isPresented, !showLogoutConfirmation else { return }
                let shouldClose = value.translation.width < -panelWidth * 0.22
                    || value.predictedEndTranslation.width < -panelWidth * 0.35
                dragTranslation = 0
                if shouldClose {
                    coordinator.close()
                }
            }
    }

    private var panelWidthForGesture: CGFloat {
        #if canImport(UIKit)
        UIScreen.main.bounds.width * BespokeSideMenuMetrics.panelWidthRatio
        #else
        320
        #endif
    }

    #if canImport(UIKit)
    private func requestAppReview() {
        coordinator.close()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
            guard
                let scene = UIApplication.shared.connectedScenes
                    .compactMap({ $0 as? UIWindowScene })
                    .first(where: { $0.activationState == .foregroundActive })
            else { return }
            AppStore.requestReview(in: scene)
        }
    }
    #else
    private func requestAppReview() {
        coordinator.close()
    }
    #endif
}

private struct BespokeSideMenuPanel: View {
    @Environment(AppSession.self) private var session
    @Environment(SubscriptionManager.self) private var subscriptionManager

    let panelWidth: CGFloat
    let onAccountSettings: () -> Void
    let onManageSubscription: () -> Void
    let onRateUs: () -> Void
    let onFeatureRequest: () -> Void
    let onSupportEmail: () -> Void
    let onAbout: () -> Void
    let onOpenURL: (URL) -> Void
    let onClose: () -> Void
    let onRequestLogout: () -> Void

    @State private var feedbackExpanded = false
    @State private var showShareSheet = false

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                if session.isLoggedIn {
                    signedInHeader
                } else {
                    signedOutHeader
                }

                VStack(spacing: session.isLoggedIn ? 0 : 6) {
                    menuRow(title: "Account settings", symbol: "person.crop.circle") {
                        onAccountSettings()
                    }

                    menuDivider

                    feedbackSection

                    menuDivider

                    menuRow(title: "Share our app", symbol: "square.and.arrow.up") {
                        showShareSheet = true
                    }

                    menuDivider

                    menuRow(title: "About BespokeDua", symbol: "info.circle") {
                        onAbout()
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, session.isLoggedIn ? 8 : 32)
                .sheet(isPresented: $showShareSheet) {
                    BespokeShareSheet(items: [BespokeAppMetadata.shareText, BespokeAppMetadata.appStoreURL])
                }

                Spacer(minLength: 0)

                VStack(spacing: session.isLoggedIn ? 14 : 20) {
                    if session.isLoggedIn {
                        BespokeAccountActionsCard(onLogout: onRequestLogout)
                    }

                    HStack(spacing: 22) {
                        socialButton(brand: .instagram, label: "Instagram") {
                            onOpenURL(BespokeAppMetadata.instagramURL)
                        }

                        socialButton(brand: .tiktok, label: "TikTok") {
                            onOpenURL(BespokeAppMetadata.tiktokURL)
                        }

                        socialButton(brand: .email, label: "Email") {
                            onSupportEmail()
                        }
                    }

                    Text(BespokeAppMetadata.versionString)
                        .font(BespokeFont.inter(11, weight: .regular))
                        .foregroundStyle(BespokeColor.subtle)
                }
                .padding(.horizontal, 20)
                .padding(.top, session.isLoggedIn ? 0 : 32)
                .padding(.bottom, 28)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background {
                LinearGradient(
                    colors: [
                        BespokeColor.homeBackground,
                        BespokeColor.pageBackground
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .shadow(color: .black.opacity(0.14), radius: 18, x: 4, y: 0)
        }
        .task {
            guard session.isLoggedIn else { return }
            subscriptionManager.updateDatabaseSubscriptionStatus(plan: session.currentUser?.plan)
            await subscriptionManager.loadProduct()
            await subscriptionManager.refreshEntitlements()
        }
    }

    @ViewBuilder
    private var signedInHeader: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.crop.circle.fill")
                .font(.system(size: 64))
                .foregroundStyle(BespokeColor.forest)
                .accessibilityHidden(true)

            if let user = session.currentUser {
                Text(user.username)
                    .font(BespokeFont.display(22))
                    .foregroundStyle(BespokeColor.forest)
                    .multilineTextAlignment(.center)

                let isSubscribed = subscriptionManager.isSubscribed
                let planTitle = BespokeSubscriptionDisplay.planTitle(
                    plan: user.plan,
                    isSubscribed: isSubscribed
                )

                if isSubscribed {
                    HStack(spacing: 6) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(LinearGradient.bespokeGold)

                        Text(planTitle)
                            .font(BespokeFont.inter(16, weight: .semibold))
                    }
                    .foregroundStyle(LinearGradient.bespokeGold)
                } else {
                    Text(planTitle)
                        .font(BespokeFont.inter(16, weight: .semibold))
                        .foregroundStyle(BespokeColor.forest)
                }
            }

            if subscriptionManager.isSubscribed {
                Button(action: onManageSubscription) {
                    HStack(spacing: 10) {
                        Image(systemName: "creditcard")
                            .font(.system(size: 16, weight: .medium))
                        Text("Manage subscription")
                            .font(BespokeFont.inter(15, weight: .semibold))
                    }
                    .foregroundStyle(BespokeColor.forest)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(BespokeColor.homeCardGreen)
                    .clipShape(Capsule())
                }
                .buttonStyle(BespokePlainButtonStyle())
                .padding(.top, 6)
            } else {
                BespokePlusUpgradeCard(
                    onUpgrade: onManageSubscription,
                    thenPriceLine: subscriptionManager.eligibleIntroOffer?.thenPriceLine
                        ?? subscriptionManager.plusMonthlyDisplayPrice
                )
                    .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.top, 84)
        .padding(.bottom, 16)
    }

    private var signedOutHeader: some View {
        VStack(spacing: 18) {
            BespokeAppLogoView(size: 72)

            Text(BespokeAppMetadata.marketingName)
                .font(BespokeFont.display(24))
                .foregroundStyle(BespokeColor.forest)

            Button {
                onClose()
                session.presentAuth()
            } label: {
                Text("Sign in")
                    .font(BespokeFont.inter(15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(LinearGradient.bespokeGold)
                    .clipShape(Capsule())
                    .bespokeButtonHitArea(cornerRadius: 14)
                    .shadow(color: .black.opacity(0.14), radius: 12, x: 0, y: 6)
            }
            .buttonStyle(BespokePlainButtonStyle())
            .padding(.top, 8)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 20)
        .padding(.top, 72)
        .padding(.bottom, 16)
    }

    private var feedbackSection: some View {
        VStack(spacing: 0) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    feedbackExpanded.toggle()
                }
            } label: {
                HStack(spacing: 13) {
                    Image(systemName: "bubble.left.and.text.bubble.right")
                        .font(.system(size: menuRowIconSize, weight: .medium))
                        .foregroundStyle(BespokeColor.forest)
                        .frame(width: menuRowIconColumnWidth)

                    Text("Feedback")
                        .font(BespokeFont.inter(menuRowFontSize, weight: .medium))
                        .foregroundStyle(BespokeColor.bodyText)

                    Spacer(minLength: 0)

                    Image(systemName: feedbackExpanded ? "chevron.down" : "chevron.right")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(BespokeColor.subtle)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, menuRowVerticalPadding)
                .contentShape(Rectangle())
            }
            .buttonStyle(BespokePlainButtonStyle())

            if feedbackExpanded {
                secondaryMenuDivider

                VStack(spacing: 0) {
                    secondaryMenuRow(title: "Rate us", symbol: "star") {
                        onRateUs()
                    }

                    secondaryMenuDivider

                    secondaryMenuRow(title: "Feature request", symbol: "lightbulb") {
                        onFeatureRequest()
                    }
                }
            }
        }
    }

    private var menuDivider: some View {
        Rectangle()
            .fill(BespokeColor.sectionRule)
            .frame(height: 1)
            .padding(.leading, 51)
    }

    private var secondaryMenuDivider: some View {
        Rectangle()
            .fill(BespokeColor.sectionRule)
            .frame(height: 1)
            .padding(.leading, 72)
    }

    private func secondaryMenuRow(title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: symbol)
                    .font(.system(size: menuRowIconSize, weight: .medium))
                    .foregroundStyle(BespokeColor.forest)
                    .frame(width: menuRowIconColumnWidth)

                Text(title)
                    .font(BespokeFont.inter(menuRowFontSize, weight: .medium))
                    .foregroundStyle(BespokeColor.muted)

                Spacer(minLength: 0)
            }
            .padding(.leading, 36)
            .padding(.trailing, 16)
            .padding(.vertical, menuRowVerticalPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(BespokePlainButtonStyle())
    }

    private var menuRowVerticalPadding: CGFloat {
        session.isLoggedIn ? 14 : 18
    }

    private var menuRowIconSize: CGFloat { 17 }
    private var menuRowFontSize: CGFloat { 15.5 }
    private var menuRowIconColumnWidth: CGFloat { 23 }

    private func menuRow(title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 13) {
                Image(systemName: symbol)
                    .font(.system(size: menuRowIconSize, weight: .medium))
                    .foregroundStyle(BespokeColor.forest)
                    .frame(width: menuRowIconColumnWidth)

                Text(title)
                    .font(BespokeFont.inter(menuRowFontSize, weight: .medium))
                    .foregroundStyle(BespokeColor.bodyText)

                Spacer(minLength: 0)

                Image(systemName: "chevron.right")
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(BespokeColor.subtle)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, menuRowVerticalPadding)
            .contentShape(Rectangle())
        }
        .buttonStyle(BespokePlainButtonStyle())
    }

    private func socialButton(brand: BespokeSocialBrand, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            brand.icon
                .frame(width: 22, height: 22)
                .frame(width: 44, height: 44)
                .background(Color.white)
                .clipShape(Circle())
                .overlay {
                    Circle()
                        .stroke(BespokeColor.cardBorder, lineWidth: 1)
                }
        }
        .buttonStyle(BespokePlainButtonStyle())
        .accessibilityLabel(label)
    }
}

extension View {
    func bespokeSideMenuOverlay(coordinator: BespokeSideMenuCoordinator, allowsEdgeSwipe: Bool = false) -> some View {
        modifier(BespokeSideMenuOverlayModifier(coordinator: coordinator, allowsEdgeSwipe: allowsEdgeSwipe))
    }

    func bespokeSideMenuPreviewHarness() -> some View {
        let coordinator = BespokeSideMenuCoordinator()
        return environment(coordinator)
            .environment(\.openSideMenu, { coordinator.open() })
    }
}

#if canImport(UIKit)
struct BespokeShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif
