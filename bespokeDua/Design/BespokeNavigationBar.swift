import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

enum BespokeLayout {
    static let navBarBottomCornerRadius: CGFloat = 24
    static let navBarTitleSize: CGFloat = 17
    static let navBarProfileIconSize: CGFloat = 24
    /// Keeps scrollable library content readable on iPad without stretching edge-to-edge.
    static let libraryContentMaxWidth: CGFloat = 720
    static let libraryHorizontalPadding: CGFloat = 20
}

extension View {
    /// Centers library content and caps width on regular (iPad) screens.
    func bespokeLibraryContentFrame() -> some View {
        frame(maxWidth: BespokeLayout.libraryContentMaxWidth)
            .frame(maxWidth: .infinity)
    }
}

extension View {
    func bespokeStyledNavigationBar(showsMainBar: Bool = true) -> some View {
        toolbarBackground(BespokeColor.forest, for: .navigationBar)
            .toolbarBackground(showsMainBar ? .visible : .hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            #if canImport(UIKit)
            .background {
                BespokeRoundedNavigationBarBackground(showsMainBar: showsMainBar)
            }
            #endif
    }

    func bespokeMainNavigationToolbar(title: String, onClose: (() -> Void)? = nil) -> some View {
        modifier(BespokeMainNavigationToolbar(title: title, onClose: onClose))
    }
}

struct BespokeFlowBackHeader: View {
    let title: String
    let onBack: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(BespokeColor.forest)
                    .padding(8)
                    .contentShape(Rectangle())
            }
            .buttonStyle(BespokePlainButtonStyle())

            Text(title)
                .font(BespokeFont.inter(17, weight: .semibold))
                .foregroundStyle(BespokeColor.forest)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(BespokeColor.pageBackground)
    }
}

extension View {
    /// Swipe from the left screen edge to go back (custom action or navigation dismiss).
    func bespokeEdgeBackNavigation(
        hidesNavigationBar: Bool = false,
        onBack: (() -> Void)? = nil
    ) -> some View {
        modifier(BespokeEdgeBackNavigationModifier(
            hidesNavigationBar: hidesNavigationBar,
            customOnBack: onBack
        ))
    }
}

/// Wraps a pushed flow with back header, edge-swipe back, and animated dismiss.
struct BespokeFlowScreen<Content: View>: View {
    let title: String
    let onExit: () -> Void
    @ViewBuilder var content: () -> Content

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        content()
            .toolbar(.hidden, for: .navigationBar)
            .navigationBarBackButtonHidden(true)
            .safeAreaInset(edge: .top, spacing: 0) {
                BespokeFlowBackHeader(title: title, onBack: goBack)
            }
            .bespokeEdgeBackNavigation(hidesNavigationBar: true)
            .onDisappear(perform: onExit)
    }

    private func goBack() {
        dismiss()
    }
}

private enum BespokeSwipeBackMetrics {
    static let edgeActivationWidth: CGFloat = 28
}

private struct BespokeEdgeBackNavigationModifier: ViewModifier {
    let hidesNavigationBar: Bool
    let customOnBack: (() -> Void)?

    func body(content: Content) -> some View {
        content
            #if canImport(UIKit)
            .background {
                BespokeInteractivePopGestureEnabler(hidesNavigationBar: hidesNavigationBar)
            }
            #endif
            .modifier(BespokeCustomEdgeSwipeBackModifier(customOnBack: customOnBack))
    }
}

/// Edge swipe for screens that use a custom back action (e.g. tab switch) instead of navigation pop.
private struct BespokeCustomEdgeSwipeBackModifier: ViewModifier {
    let customOnBack: (() -> Void)?

    func body(content: Content) -> some View {
        if let customOnBack {
            content.gesture(customBackSwipeGesture(onBack: customOnBack))
        } else {
            content
        }
    }

    private func customBackSwipeGesture(onBack: @escaping () -> Void) -> some Gesture {
        DragGesture(minimumDistance: 20, coordinateSpace: .global)
            .onEnded { value in
                guard value.startLocation.x <= BespokeSwipeBackMetrics.edgeActivationWidth else { return }
                guard value.translation.width > 72 else { return }
                guard abs(value.translation.width) > abs(value.translation.height) else { return }
                onBack()
            }
    }
}

private struct BespokeMainNavigationToolbar: ViewModifier {
    let title: String
    var onClose: (() -> Void)? = nil
    @Environment(\.openSideMenu) private var openSideMenu

    func body(content: Content) -> some View {
        content
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(title)
                        .font(BespokeFont.inter(BespokeLayout.navBarTitleSize, weight: .semibold))
                        .foregroundStyle(.white)
                        .fixedSize()
                        .accessibilityAddTraits(.isHeader)
                }
                .hideSharedBackgroundIfAvailable()
            }
            #if canImport(UIKit)
            .background {
                BespokeNavBarLeadingButtonHost(
                    icon: onClose == nil ? .menu : .close,
                    onTap: onClose ?? openSideMenu
                )
            }
            #endif
    }
}

private extension ToolbarContent {
    @ToolbarContentBuilder
    func hideSharedBackgroundIfAvailable() -> some ToolbarContent {
        if #available(iOS 26.0, *) {
            sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
    }
}

#if canImport(UIKit)
/// Pins a plain white nav-bar button onto the UIKit navigation bar (SwiftUI toolbar leading items do not render with our custom bar).
struct BespokeNavBarLeadingButtonHost: UIViewControllerRepresentable {
    enum Icon {
        case menu
        case close
    }

    let icon: Icon
    let onTap: () -> Void
    /// When the navigation bar is hidden, pin the button onto the root view (e.g. Dua Feed custom header).
    var overlaysWhenBarHidden: Bool = false
    var isVisible: Bool = true

    func makeCoordinator() -> Coordinator {
        Coordinator(onTap: onTap, icon: icon, overlaysWhenBarHidden: overlaysWhenBarHidden, isVisible: isVisible)
    }

    func makeUIViewController(context: Context) -> HostViewController {
        let controller = HostViewController()
        controller.coordinator = context.coordinator
        return controller
    }

    func updateUIViewController(_ uiViewController: HostViewController, context: Context) {
        context.coordinator.onTap = onTap
        context.coordinator.icon = icon
        context.coordinator.overlaysWhenBarHidden = overlaysWhenBarHidden
        context.coordinator.isVisible = isVisible
        uiViewController.coordinator = context.coordinator
        uiViewController.syncButton()
        guard isVisible else { return }
        // Re-sync after navigation pops finish (e.g. re-tapping Saved tab).
        DispatchQueue.main.async {
            uiViewController.syncButton()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
            uiViewController.syncButton()
        }
    }

    static func dismantleUIViewController(_ uiViewController: HostViewController, coordinator: Coordinator) {
        uiViewController.removeInstalledButton()
    }

    final class HostViewController: UIViewController {
        weak var coordinator: Coordinator?
        private weak var installedButton: UIButton?

        override func viewDidLoad() {
            super.viewDidLoad()
            view.isUserInteractionEnabled = false
            view.backgroundColor = .clear
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            syncButton()
        }

        func syncButton() {
            guard let coordinator, let navigationController else {
                removeInstalledButton()
                return
            }

            guard coordinator.isVisible else {
                removeInstalledButton()
                return
            }

            let isRoot = navigationController.viewControllers.count <= 1
            guard isRoot else {
                removeInstalledButton()
                return
            }

            let barHidden = navigationController.navigationBar.isHidden
            guard !barHidden || coordinator.overlaysWhenBarHidden else {
                installedButton?.removeFromSuperview()
                installedButton = nil
                return
            }

            let container: UIView = barHidden ? navigationController.view : navigationController.navigationBar
            let button: UIButton
            if let existing = installedButton, existing.superview === container {
                button = existing
            } else {
                installedButton?.removeFromSuperview()
                let newButton = UIButton(type: .custom)
                newButton.backgroundColor = .clear
                if #available(iOS 15.0, *) {
                    var config = UIButton.Configuration.plain()
                    config.baseBackgroundColor = .clear
                    newButton.configuration = config
                } else {
                    newButton.adjustsImageWhenHighlighted = false
                }
                container.addSubview(newButton)
                installedButton = newButton
                button = newButton
            }

            button.setImage(BespokeNavBarButtonArtwork.image(for: coordinator.icon), for: .normal)
            button.accessibilityLabel = coordinator.icon == .menu ? "Menu" : "Close"
            button.removeTarget(nil, action: nil, for: .allEvents)
            button.addAction(UIAction { [weak coordinator] _ in coordinator?.onTap() }, for: .touchUpInside)

            if barHidden {
                let safeTop = navigationController.view.safeAreaInsets.top
                button.frame = CGRect(x: 8, y: safeTop + 6, width: 44, height: 44)
            } else {
                let height = navigationController.navigationBar.bounds.height
                button.frame = CGRect(x: 8, y: max(0, (height - 44) / 2), width: 44, height: 44)
            }
            button.autoresizingMask = [.flexibleRightMargin, .flexibleBottomMargin]
            container.bringSubviewToFront(button)
        }

        func removeInstalledButton() {
            installedButton?.removeFromSuperview()
            installedButton = nil
        }
    }

    final class Coordinator {
        var onTap: () -> Void
        var icon: Icon
        var overlaysWhenBarHidden: Bool
        var isVisible: Bool

        init(onTap: @escaping () -> Void, icon: Icon, overlaysWhenBarHidden: Bool, isVisible: Bool) {
            self.onTap = onTap
            self.icon = icon
            self.overlaysWhenBarHidden = overlaysWhenBarHidden
            self.isVisible = isVisible
        }
    }
}

enum BespokeNavBarButtonArtwork {
    static func image(for icon: BespokeNavBarLeadingButtonHost.Icon) -> UIImage {
        switch icon {
        case .menu:
            return drawMenuIcon()
        case .close:
            return drawCloseIcon()
        }
    }

    private static func drawMenuIcon() -> UIImage {
        let size = CGSize(width: 24, height: 24)
        return UIGraphicsImageRenderer(size: size).image { _ in
            UIColor.white.setFill()
            let lineHeight: CGFloat = 2.2
            let lineWidth: CGFloat = 18
            let originX = (size.width - lineWidth) / 2
            for index in 0..<3 {
                let y = 4 + CGFloat(index) * 7
                UIBezierPath(
                    roundedRect: CGRect(x: originX, y: y, width: lineWidth, height: lineHeight),
                    cornerRadius: lineHeight / 2
                ).fill()
            }
        }.withRenderingMode(.alwaysOriginal)
    }

    private static func drawCloseIcon() -> UIImage {
        let size = CGSize(width: 24, height: 24)
        return UIGraphicsImageRenderer(size: size).image { _ in
            UIColor.white.setStroke()
            let path = UIBezierPath()
            path.lineWidth = 2.2
            path.lineCapStyle = .round
            path.move(to: CGPoint(x: 6, y: 6))
            path.addLine(to: CGPoint(x: 18, y: 18))
            path.move(to: CGPoint(x: 18, y: 6))
            path.addLine(to: CGPoint(x: 6, y: 18))
            path.stroke()
        }.withRenderingMode(.alwaysOriginal)
    }
}

struct BespokeInteractivePopGestureEnabler: UIViewControllerRepresentable {
    var hidesNavigationBar: Bool = false

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        controller.view.isUserInteractionEnabled = false
        controller.view.backgroundColor = .clear
        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        DispatchQueue.main.async {
            guard let navigationController = uiViewController.navigationController else { return }
            let coordinator = context.coordinator
            coordinator.navigationController = navigationController

            if let popGesture = navigationController.interactivePopGestureRecognizer {
                popGesture.isEnabled = true
                popGesture.delegate = coordinator
            }

            if hidesNavigationBar {
                uiViewController.navigationItem.hidesBackButton = true
                uiViewController.navigationItem.setHidesBackButton(true, animated: false)
                uiViewController.navigationItem.leftBarButtonItem = nil
                uiViewController.navigationItem.leftBarButtonItems = nil
                uiViewController.navigationItem.leftItemsSupplementBackButton = false
            }
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var navigationController: UINavigationController?

        func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
            guard let navigationController else { return false }
            guard navigationController.viewControllers.count > 1 else { return false }

            guard let pan = gestureRecognizer as? UIPanGestureRecognizer,
                  let view = pan.view else { return true }

            let velocity = pan.velocity(in: view)
            let speed = hypot(velocity.x, velocity.y)
            guard speed > 30 else { return true }
            return abs(velocity.x) > abs(velocity.y)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            false
        }
    }
}

private enum BespokeNavigationBarAppearance {
    static func apply(to navigationBar: UINavigationBar, cornerRadius: CGFloat) {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = .clear
        appearance.shadowColor = .clear
        appearance.titleTextAttributes = [.foregroundColor: UIColor.white]
        appearance.largeTitleTextAttributes = [.foregroundColor: UIColor.white]

        let backgroundImage = roundedBackgroundImage(cornerRadius: cornerRadius)
        appearance.backgroundImage = backgroundImage
        appearance.backgroundImageContentMode = .scaleToFill

        navigationBar.standardAppearance = appearance
        navigationBar.scrollEdgeAppearance = appearance
        navigationBar.compactAppearance = appearance
        navigationBar.compactScrollEdgeAppearance = appearance
        navigationBar.isTranslucent = false
        navigationBar.barTintColor = UIColor(BespokeColor.forest)
    }

    private static func roundedBackgroundImage(cornerRadius: CGFloat) -> UIImage {
        let width = max(UIScreen.main.bounds.width, 1)
        let height = cornerRadius + 4
        let size = CGSize(width: width, height: height)

        let image = UIGraphicsImageRenderer(size: size).image { context in
            let rect = CGRect(origin: .zero, size: size)
            let path = UIBezierPath(
                roundedRect: rect,
                byRoundingCorners: [.bottomLeft, .bottomRight],
                cornerRadii: CGSize(width: cornerRadius, height: cornerRadius)
            )
            UIColor(BespokeColor.forest).setFill()
            path.fill()

            context.cgContext.saveGState()
            path.addClip()

            let patternColor = UIColor.white.withAlphaComponent(0.05)
            patternColor.setStroke()

            let starSize: CGFloat = 88
            let columns = Int(ceil(width / starSize)) + 1
            let rows = Int(ceil(height / starSize)) + 1

            for row in 0..<rows {
                for column in 0..<columns {
                    let center = CGPoint(
                        x: CGFloat(column) * starSize + starSize * 0.5,
                        y: CGFloat(row) * starSize + starSize * 0.5
                    )
                    Self.drawGeometricStar(at: center, radius: 28, in: context.cgContext)
                }
            }

            context.cgContext.restoreGState()
        }

        return image.resizableImage(
            withCapInsets: UIEdgeInsets(
                top: 0,
                left: width / 2,
                bottom: cornerRadius,
                right: width / 2
            ),
            resizingMode: .stretch
        )
    }

    private static func drawGeometricStar(at center: CGPoint, radius: CGFloat, in context: CGContext) {
        let points = 8
        let path = UIBezierPath()
        for index in 0..<(points * 2) {
            let angle = (CGFloat(index) * .pi / CGFloat(points)) - .pi / 2
            let pointRadius = index.isMultiple(of: 2) ? radius : radius * 0.42
            let point = CGPoint(
                x: center.x + cos(angle) * pointRadius,
                y: center.y + sin(angle) * pointRadius
            )
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.close()
        path.lineWidth = 1
        path.stroke()
    }
}

struct BespokeRoundedNavigationBarBackground: UIViewControllerRepresentable {
    var showsMainBar: Bool = true

    func makeUIViewController(context: Context) -> BespokeRoundedNavigationBarController {
        let controller = BespokeRoundedNavigationBarController()
        controller.showsMainBar = showsMainBar
        return controller
    }

    func updateUIViewController(_ uiViewController: BespokeRoundedNavigationBarController, context: Context) {
        uiViewController.showsMainBar = showsMainBar
        uiViewController.applyRoundedAppearance()
    }
}

final class BespokeRoundedNavigationBarController: UIViewController {
    var showsMainBar = true

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        applyRoundedAppearance()
    }

    func applyRoundedAppearance() {
        DispatchQueue.main.async { [weak self] in
            guard let self, let navigationController = self.navigationController else { return }
            let navigationBar = navigationController.navigationBar
            let isRoot = navigationController.viewControllers.count <= 1

            if let topItem = navigationController.topViewController?.navigationItem {
                topItem.hidesBackButton = true
                topItem.setHidesBackButton(true, animated: false)
                topItem.leftItemsSupplementBackButton = false
            }

            guard isRoot, showsMainBar else {
                UIView.performWithoutAnimation {
                    navigationBar.isHidden = true
                    navigationBar.viewWithTag(Self.legacyNavTitleLabelTag)?.isHidden = true
                }
                return
            }

            UIView.performWithoutAnimation {
                navigationBar.isHidden = false
                BespokeNavigationBarAppearance.apply(
                    to: navigationBar,
                    cornerRadius: BespokeLayout.navBarBottomCornerRadius
                )
                navigationBar.viewWithTag(Self.legacyNavTitleLabelTag)?.isHidden = true
            }
        }
    }

    private static let legacyNavTitleLabelTag = 982_441
}

/// Defers restoring the home main navigation bar until an interactive pop fully completes.
struct BespokeHomeNavigationTransitionObserver: UIViewControllerRepresentable {
    @Binding var showsMainNavigationBar: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(showsMainNavigationBar: $showsMainNavigationBar)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = UIViewController()
        controller.view.isUserInteractionEnabled = false
        controller.view.backgroundColor = .clear
        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        DispatchQueue.main.async {
            guard let navigationController = uiViewController.navigationController else { return }
            if navigationController.delegate !== context.coordinator {
                context.coordinator.navigationController = navigationController
                navigationController.delegate = context.coordinator
            }
        }
    }

    static func dismantleUIViewController(_ uiViewController: UIViewController, coordinator: Coordinator) {
        coordinator.navigationController?.delegate = nil
    }

    final class Coordinator: NSObject, UINavigationControllerDelegate {
        @Binding var showsMainNavigationBar: Bool
        weak var navigationController: UINavigationController?

        init(showsMainNavigationBar: Binding<Bool>) {
            _showsMainNavigationBar = showsMainNavigationBar
        }

        func navigationController(
            _ navigationController: UINavigationController,
            willShow viewController: UIViewController,
            animated: Bool
        ) {
            let isRoot = viewController === navigationController.viewControllers.first
            showsMainNavigationBar = isRoot
        }
    }
}
#endif
