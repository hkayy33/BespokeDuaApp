import SwiftUI

enum MainTab: Hashable {
    case home
    case duaFeed
    case sunnah
    case names
    case saved
    case profile

    var navigationTitle: String {
        switch self {
        case .home: "Home"
        case .duaFeed: "Dua Feed"
        case .sunnah: "Sunnah Duas"
        case .names: "99 Names"
        case .saved: "Saved"
        case .profile: "Profile"
        }
    }
}

struct MainTabBarHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}

struct HidesMainTabBarKey: PreferenceKey {
    static var defaultValue = false
    static func reduce(value: inout Bool, nextValue: () -> Bool) {
        value = value || nextValue()
    }
}

private struct MainTabBarClearanceKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0
}

struct SelectMainTabAction {
    var select: (MainTab) -> Void

    func callAsFunction(_ tab: MainTab) {
        select(tab)
    }
}

struct MainTabBarVisibilityAction {
    private let setHidden: (Bool) -> Void

    init(setHidden: @escaping (Bool) -> Void) {
        self.setHidden = setHidden
    }

    func callAsFunction(_ hidden: Bool) {
        setHidden(hidden)
    }
}

enum MainTabBarLayout {
    /// Approximate height of the floating / minimized system tab bar chrome.
    static let systemChromeHeight: CGFloat = 49

    static var bottomSafeInset: CGFloat {
        #if canImport(UIKit)
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
        return window?.safeAreaInsets.bottom ?? 0
        #else
        return 0
        #endif
    }

    static func bottomCoverHeight(customTabBarHeight: CGFloat) -> CGFloat {
        max(customTabBarHeight, systemChromeHeight) + bottomSafeInset
    }
}

private struct SelectMainTabKey: EnvironmentKey {
    static let defaultValue = SelectMainTabAction { _ in }
}

private struct MainTabBarVisibilityKey: EnvironmentKey {
    static let defaultValue = MainTabBarVisibilityAction { _ in }
}

private struct MainTabBarHiddenKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Bottom inset so scroll content clears the custom tab bar (0 while the keyboard is open).
    var mainTabBarClearance: CGFloat {
        get { self[MainTabBarClearanceKey.self] }
        set { self[MainTabBarClearanceKey.self] = newValue }
    }

    var selectMainTab: SelectMainTabAction {
        get { self[SelectMainTabKey.self] }
        set { self[SelectMainTabKey.self] = newValue }
    }

    var mainTabBarVisibility: MainTabBarVisibilityAction {
        get { self[MainTabBarVisibilityKey.self] }
        set { self[MainTabBarVisibilityKey.self] = newValue }
    }

    var mainTabBarHidden: Bool {
        get { self[MainTabBarHiddenKey.self] }
        set { self[MainTabBarHiddenKey.self] = newValue }
    }
}

#if canImport(UIKit)
import UIKit

/// Hides the system `UITabBar` so only the custom `MainTabBar` overlay is shown.
struct SystemTabBarHider: UIViewRepresentable {
    var isHidden: Bool

    func makeUIView(context: Context) -> TrackerView {
        let view = TrackerView()
        view.isUserInteractionEnabled = false
        view.backgroundColor = .clear
        return view
    }

    func updateUIView(_ uiView: TrackerView, context: Context) {
        uiView.setSuppressed(isHidden)
    }

    final class TrackerView: UIView {
        private var suppressed = true

        override func didMoveToWindow() {
            super.didMoveToWindow()
            applySuppression()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            applySuppression()
        }

        func setSuppressed(_ suppressed: Bool) {
            self.suppressed = suppressed
            applySuppression()
        }

        private func applySuppression() {
            guard suppressed, let tabBar = Self.findTabBar(from: self) else { return }
            tabBar.isHidden = true
            tabBar.alpha = 0
            tabBar.isUserInteractionEnabled = false
            tabBar.subviews.forEach { subview in
                subview.isHidden = true
                subview.alpha = 0
            }
        }

        private static func findTabBar(from view: UIView) -> UITabBar? {
            var responder: UIResponder? = view
            while let current = responder {
                if let controller = current as? UITabBarController {
                    return controller.tabBar
                }
                responder = current.next
            }

            guard let root = view.window?.rootViewController else { return nil }
            return findTabBarController(in: root)?.tabBar
        }

        private static func findTabBarController(in controller: UIViewController) -> UITabBarController? {
            if let tabBarController = controller as? UITabBarController {
                return tabBarController
            }
            for child in controller.children {
                if let found = findTabBarController(in: child) {
                    return found
                }
            }
            if let presented = controller.presentedViewController,
               let found = findTabBarController(in: presented) {
                return found
            }
            return nil
        }
    }
}
#endif

struct MainTabBar: View {
    @Binding var selection: MainTab
    var homeNavigationDepth: Int = 0
    var savedNavigationDepth: Int = 0
    var onPopHomeStack: (() -> Void)? = nil
    var onPopSavedStack: (() -> Void)? = nil

    private struct Item: Identifiable {
        let tab: MainTab
        let title: String
        let icon: String
        let selectedIcon: String
        var id: MainTab { tab }
    }

    private static let items: [Item] = [
        Item(tab: .home, title: "Home", icon: "house", selectedIcon: "house.fill"),
        Item(tab: .duaFeed, title: "Dua Feed", icon: "bubble.left.and.bubble.right", selectedIcon: "bubble.left.and.bubble.right.fill"),
        Item(tab: .saved, title: "Saved", icon: "bookmark", selectedIcon: "bookmark.fill"),
    ]

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(BespokeColor.sectionRule)
                .frame(height: 1)

            HStack(spacing: 0) {
                ForEach(Self.items) { item in
                    tabButton(item)
                }
            }
            .padding(.top, 10)
            .padding(.bottom, 2)
        }
        .background {
            Color.white
                .ignoresSafeArea(edges: .bottom)
        }
        .ignoresSafeArea(edges: .bottom)
        .background {
            GeometryReader { geo in
                Color.clear.preference(key: MainTabBarHeightKey.self, value: geo.size.height)
            }
        }
    }

    private func tabButton(_ item: Item) -> some View {
        let isSelected = isTabVisuallySelected(item.tab)

        return Button {
            if item.tab == .home {
                if homeNavigationDepth > 0 {
                    onPopHomeStack?()
                }
                selection = .home
            } else if item.tab == .saved, savedNavigationDepth > 0 {
                onPopSavedStack?()
            } else {
                selection = item.tab
            }
        } label: {
            VStack(spacing: 5) {
                Image(systemName: isSelected ? item.selectedIcon : item.icon)
                    .font(.system(size: 21, weight: .regular))
                    .symbolRenderingMode(.monochrome)

                Text(item.title)
                    .font(BespokeFont.inter(10, weight: .medium))
            }
            .foregroundStyle(isSelected ? BespokeColor.forest : BespokeColor.tabBarInactive)
            .frame(maxWidth: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(BespokePlainButtonStyle())
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func isTabVisuallySelected(_ tab: MainTab) -> Bool {
        guard selection == tab else { return false }
        if tab == .home, homeNavigationDepth > 0 { return false }
        if tab == .saved, savedNavigationDepth > 0 { return false }
        return true
    }
}
