import SwiftUI

struct DuaFeedPaywallOverlay: View {
    var requiresSignIn = false
    let onUnlock: () -> Void
    let onDismiss: () -> Void

    private enum Layout {
        static let cardCornerRadius: CGFloat = 22
        static let cardMaxWidth: CGFloat = 380
        static let emblemSize: CGFloat = 76
        static let iconCircleSize: CGFloat = 36
        /// Space between the card's top edge and the first line of content, clearing the overlapping emblem.
        static var contentTopInset: CGFloat { emblemSize / 2 + 16 }
    }

    private struct Feature: Identifiable {
        let id = UUID()
        let title: String
        let icon: FeatureIcon

        static let items: [Feature] = [
            Feature(title: "Post a saved du'a anonymously", icon: .share),
            Feature(title: "Make du'a for others in the feed", icon: .community),
            Feature(title: "Browse Today, Recent, and Most made", icon: .filters),
        ]
    }

    private enum FeatureIcon {
        case share
        case community
        case filters
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)

            paywallCard
                .padding(.horizontal, BespokeLayout.libraryHorizontalPadding)

            Spacer(minLength: 12)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var paywallCard: some View {
        ZStack(alignment: .top) {
            cardBody
                .padding(.top, Layout.emblemSize / 2 + 6)

            emblemCluster
        }
        .frame(maxWidth: Layout.cardMaxWidth)
        .frame(maxWidth: .infinity)
    }

    private var cardBody: some View {
        VStack(spacing: 14) {
            premiumLabel

            headerBlock

            VStack(spacing: 8) {
                ForEach(Feature.items) { feature in
                    featureRow(feature)
                }
            }

            unlockButton
            orDivider
            dismissButton
        }
        .padding(.horizontal, 22)
        .padding(.top, Layout.contentTopInset)
        .padding(.bottom, 22)
        .background {
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.06), radius: 1, x: 0, y: 1)
        }
        .background {
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius, style: .continuous)
                .fill(Color.white)
                .shadow(color: .black.opacity(0.12), radius: 24, x: 0, y: 12)
        }
        .overlay {
            RoundedRectangle(cornerRadius: Layout.cardCornerRadius, style: .continuous)
                .stroke(BespokeColor.cardBorder.opacity(0.55), lineWidth: 1)
        }
        .overlay(alignment: .top) {
            decorativeStars
                .padding(.top, Layout.contentTopInset - 8)
        }
    }

    private var emblemCluster: some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 253 / 255, green: 249 / 255, blue: 241 / 255),
                            Color(red: 246 / 255, green: 236 / 255, blue: 214 / 255),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: Layout.emblemSize, height: Layout.emblemSize)
                .overlay {
                    Circle()
                        .stroke(BespokeColor.homeGold.opacity(0.18), lineWidth: 1)
                }
                .shadow(color: BespokeColor.homeGold.opacity(0.18), radius: 10, x: 0, y: 4)

            Image(systemName: "moon.stars.fill")
                .font(.system(size: 30, weight: .medium))
                .foregroundStyle(
                    LinearGradient(
                        colors: [BespokeColor.gold, BespokeColor.goldDeep],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(BespokePlusOfferCopy.freeMonthHeadline)
    }

    private var decorativeStars: some View {
        HStack(spacing: 0) {
            starAccent(size: 7, offsetX: -58)
            Spacer()
            starAccent(size: 5, offsetX: 52, offsetY: 8)
        }
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
    }

    private func starAccent(size: CGFloat, offsetX: CGFloat, offsetY: CGFloat = 0) -> some View {
        Image(systemName: "sparkle")
            .font(.system(size: size, weight: .bold))
            .foregroundStyle(BespokeColor.homeGold.opacity(0.75))
            .offset(x: offsetX, y: offsetY)
    }

    private var premiumLabel: some View {
        HStack(spacing: 6) {
            Image(systemName: "diamond.fill")
                .font(.system(size: 9, weight: .bold))

            Text(BespokePlusOfferCopy.premiumBadge)
                .font(BespokeFont.inter(11.5, weight: .semibold))
                .textCase(.uppercase)
                .tracking(0.45)
        }
        .foregroundStyle(BespokeColor.goldDeep)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(BespokeColor.homeGold.opacity(0.16))
        .clipShape(Capsule())
        .overlay {
            Capsule()
                .stroke(BespokeColor.homeGold.opacity(0.22), lineWidth: 1)
        }
    }

    private var headerBlock: some View {
        VStack(spacing: 8) {
            Text(requiresSignIn ? "Sign in to continue" : "Unlock Dua Feed")
                .font(BespokeFont.display(26))
                .foregroundStyle(BespokeColor.forest)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            Text(requiresSignIn
                ? "Sign in first to join the feed. You can start a free month after you're logged in."
                : "Start with 1 month free. Make du'a for others, share yours anonymously, and join the community feed.")
                .font(BespokeFont.inter(14, weight: .regular))
                .foregroundStyle(BespokeColor.muted)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .frame(maxWidth: .infinity)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func featureRow(_ feature: Feature) -> some View {
        HStack(alignment: .center, spacing: 12) {
            featureIcon(feature.icon)
                .frame(width: Layout.iconCircleSize, height: Layout.iconCircleSize)

            Text(feature.title)
                .font(BespokeFont.inter(14, weight: .semibold))
                .foregroundStyle(BespokeColor.heading)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, 12)
        .padding(.trailing, 14)
        .padding(.vertical, 12)
        .background(
            LinearGradient(
                colors: [
                    Color(red: 244 / 255, green: 250 / 255, blue: 245 / 255),
                    BespokeColor.feedSurface,
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(BespokeColor.forest.opacity(0.08), lineWidth: 1)
        }
    }

    @ViewBuilder
    private func featureIcon(_ icon: FeatureIcon) -> some View {
        ZStack {
            Circle()
                .fill(
                    LinearGradient(
                        colors: [BespokeColor.forest, BespokeColor.forestHover],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            switch icon {
            case .share:
                Image(systemName: "person.badge.shield.checkmark.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .symbolRenderingMode(.hierarchical)

            case .community:
                Image("Hands")
                    .renderingMode(.template)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 18, height: 18)
                    .foregroundStyle(.white)

            case .filters:
                Image(systemName: "line.3.horizontal.decrease.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                    .symbolRenderingMode(.hierarchical)
            }
        }
    }

    private var unlockButton: some View {
        Button(action: onUnlock) {
            HStack(spacing: 8) {
                Image(systemName: requiresSignIn ? "person.crop.circle" : "lock")
                    .font(.system(size: 15, weight: .semibold))

                Text(requiresSignIn ? "Sign in" : BespokePlusOfferCopy.startFreeMonth)
                    .font(BespokeFont.inter(15.5, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 15)
            .background(
                LinearGradient(
                    colors: [
                        Color(red: 201 / 255, green: 158 / 255, blue: 72 / 255),
                        Color(red: 176 / 255, green: 128 / 255, blue: 48 / 255),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .bespokeButtonHitArea(cornerRadius: 14)
            .shadow(color: BespokeColor.goldDeep.opacity(0.28), radius: 10, x: 0, y: 5)
        }
        .buttonStyle(BespokePlainButtonStyle())
        .padding(.top, 2)
    }

    private var orDivider: some View {
        HStack(spacing: 10) {
            Rectangle()
                .fill(BespokeColor.cardBorder)
                .frame(height: 1)

            Text("or")
                .font(BespokeFont.inter(12, weight: .medium))
                .foregroundStyle(BespokeColor.subtle)

            Rectangle()
                .fill(BespokeColor.cardBorder)
                .frame(height: 1)
        }
    }

    private var dismissButton: some View {
        Button(action: onDismiss) {
            Text("Maybe later")
                .font(BespokeFont.inter(15, weight: .semibold))
                .foregroundStyle(BespokeColor.forest)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 2)
        }
        .buttonStyle(BespokePlainButtonStyle())
    }
}

#Preview {
    ZStack {
        LinearGradient.bespokeHomeCanvas.ignoresSafeArea()
        DuaFeedPaywallOverlay(onUnlock: {}, onDismiss: {})
    }
}
