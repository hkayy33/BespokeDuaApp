import SwiftUI

enum BespokeSubpageLayoutMetrics {
    static let archedPanelTopRadius: CGFloat = 24
    static let archedPanelOverlap: CGFloat = 10
    static let listTopSpacing: CGFloat = 16
}

struct BespokeSubpageLayout<Trailing: View, Content: View>: View {
    let title: String
    let subtitle: String?
    var showsBackButton: Bool
    var showsMenuButton: Bool
    var reservesLeadingButtonSpace: Bool
    var centersTitle: Bool
    var usesHomeBackground: Bool
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: () -> Content

    init(
        title: String,
        subtitle: String? = nil,
        showsBackButton: Bool = true,
        showsMenuButton: Bool = false,
        reservesLeadingButtonSpace: Bool = false,
        centersTitle: Bool = false,
        usesHomeBackground: Bool = false,
        @ViewBuilder content: @escaping () -> Content
    ) where Trailing == EmptyView {
        self.title = title
        self.subtitle = subtitle
        self.showsBackButton = showsBackButton
        self.showsMenuButton = showsMenuButton
        self.reservesLeadingButtonSpace = reservesLeadingButtonSpace
        self.centersTitle = centersTitle
        self.usesHomeBackground = usesHomeBackground
        self.trailing = { EmptyView() }
        self.content = content
    }

    init(
        title: String,
        subtitle: String? = nil,
        showsBackButton: Bool = true,
        showsMenuButton: Bool = false,
        reservesLeadingButtonSpace: Bool = false,
        centersTitle: Bool = false,
        usesHomeBackground: Bool = false,
        @ViewBuilder trailing: @escaping () -> Trailing,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.title = title
        self.subtitle = subtitle
        self.showsBackButton = showsBackButton
        self.showsMenuButton = showsMenuButton
        self.reservesLeadingButtonSpace = reservesLeadingButtonSpace
        self.centersTitle = centersTitle
        self.usesHomeBackground = usesHomeBackground
        self.trailing = trailing
        self.content = content
    }

    var body: some View {
        VStack(spacing: 0) {
            BespokeSubpageHeader(
                title: title,
                subtitle: subtitle,
                showsBackButton: showsBackButton,
                showsMenuButton: showsMenuButton,
                reservesLeadingButtonSpace: reservesLeadingButtonSpace,
                centersTitle: centersTitle,
                trailing: trailing
            )

            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .background {
                    if usesHomeBackground {
                        LinearGradient.bespokeHomeCanvas
                    } else {
                        BespokeColor.cream
                    }
                }
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: BespokeSubpageLayoutMetrics.archedPanelTopRadius,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: BespokeSubpageLayoutMetrics.archedPanelTopRadius,
                        style: .continuous
                    )
                )
                .padding(.top, -BespokeSubpageLayoutMetrics.archedPanelOverlap)
        }
        .background(BespokeColor.forest)
    }
}

struct BespokeSubpageHeader<Trailing: View>: View {
    @Environment(\.dismiss) private var dismiss

    let title: String
    let subtitle: String?
    var showsBackButton: Bool
    var showsMenuButton: Bool
    var reservesLeadingButtonSpace: Bool
    var centersTitle: Bool
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        if centersTitle {
            centeredHeader
        } else {
            leadingHeader
        }
    }

    private var leadingHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            headerToolbarRow

            titleBlock(alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 20)
        .padding(.bottom, 18)
        .safeAreaPadding(.top, 6)
        .background(headerBackground)
    }

    private var centeredHeader: some View {
        VStack(spacing: 8) {
            ZStack {
                headerToolbarRow

                Text(title)
                    .font(BespokeFont.display(22))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.22), radius: 4, x: 0, y: 1)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .accessibilityAddTraits(.isHeader)
            }
            .frame(height: 44)

            if let subtitle {
                Text(subtitle)
                    .font(BespokeFont.inter(14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.94))
                    .shadow(color: .black.opacity(0.22), radius: 3, x: 0, y: 1)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 4)
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 18)
        .safeAreaPadding(.top, 6)
        .background(headerBackground)
    }

    private var headerToolbarRow: some View {
        HStack(alignment: .center, spacing: 12) {
            leadingAccessory

            Spacer(minLength: 0)

            trailing()

            if centersTitle, Trailing.self == EmptyView.self {
                Color.clear
                    .frame(width: 44, height: 44)
                    .accessibilityHidden(true)
            }
        }
    }

    @ViewBuilder
    private var leadingAccessory: some View {
        if showsBackButton {
            Button {
                dismiss()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.28), radius: 3, x: 0, y: 1)
            }
            .buttonStyle(BespokePlainButtonStyle())
        } else if showsMenuButton {
            BespokeMenuToolbarButton()
        } else if reservesLeadingButtonSpace {
            Color.clear
                .frame(width: 44, height: 44)
                .accessibilityHidden(true)
        }
    }

    private func titleBlock(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 8) {
            Text(title)
                .font(BespokeFont.display(22))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.22), radius: 4, x: 0, y: 1)
                .fixedSize(horizontal: false, vertical: true)
                .multilineTextAlignment(alignment == .center ? .center : .leading)
                .frame(maxWidth: .infinity, alignment: alignment == .center ? .center : .leading)
                .accessibilityAddTraits(.isHeader)

            if let subtitle {
                Text(subtitle)
                    .font(BespokeFont.inter(14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.94))
                    .shadow(color: .black.opacity(0.22), radius: 3, x: 0, y: 1)
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(alignment == .center ? .center : .leading)
                    .frame(maxWidth: .infinity, alignment: alignment == .center ? .center : .leading)
            }
        }
    }

    private var headerBackground: some View {
        BespokeColor.forest
            .ignoresSafeArea(edges: .top)
    }
}
