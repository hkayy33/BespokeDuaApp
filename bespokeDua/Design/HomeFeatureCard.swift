import SwiftUI

// MARK: - Theme

struct HomeFeatureCardTheme {
    let cardBackground: Color
    let cardBorder: Color
    let iconTileBackground: Color
    let eyebrowColor: Color
    let subtitleColor: Color
    let tagBackground: Color
    let tagTextColor: Color
    let chevronButtonBackground: Color
    let chevronButtonBorder: Color
    let chevronColor: Color
    let backdropOpacity: Double

    static let create = HomeFeatureCardTheme(
        cardBackground: Color(red: 252 / 255, green: 254 / 255, blue: 252 / 255),
        cardBorder: Color(red: 220 / 255, green: 235 / 255, blue: 226 / 255),
        iconTileBackground: BespokeColor.homeMintIcon,
        eyebrowColor: BespokeColor.homeGold.opacity(0.88),
        subtitleColor: Color(red: 92 / 255, green: 108 / 255, blue: 98 / 255),
        tagBackground: Color(red: 232 / 255, green: 242 / 255, blue: 236 / 255),
        tagTextColor: BespokeColor.forest,
        chevronButtonBackground: .white,
        chevronButtonBorder: Color(red: 220 / 255, green: 235 / 255, blue: 226 / 255),
        chevronColor: BespokeColor.homeGold,
        backdropOpacity: 0.42
    )

    static let discover = HomeFeatureCardTheme(
        cardBackground: Color(red: 253 / 255, green: 250 / 255, blue: 244 / 255),
        cardBorder: Color(red: 235 / 255, green: 220 / 255, blue: 190 / 255).opacity(0.55),
        iconTileBackground: BespokeColor.homeBeigeIcon,
        eyebrowColor: BespokeColor.homeGold.opacity(0.9),
        subtitleColor: Color(red: 108 / 255, green: 98 / 255, blue: 82 / 255),
        tagBackground: Color(red: 245 / 255, green: 236 / 255, blue: 214 / 255),
        tagTextColor: Color(red: 138 / 255, green: 108 / 255, blue: 58 / 255),
        chevronButtonBackground: Color(red: 255 / 255, green: 253 / 255, blue: 248 / 255),
        chevronButtonBorder: Color(red: 228 / 255, green: 210 / 255, blue: 170 / 255).opacity(0.7),
        chevronColor: BespokeColor.homeGold,
        backdropOpacity: 0.28
    )

    static let reflect = HomeFeatureCardTheme(
        cardBackground: Color(red: 246 / 255, green: 251 / 255, blue: 248 / 255),
        cardBorder: Color(red: 214 / 255, green: 232 / 255, blue: 222 / 255),
        iconTileBackground: BespokeColor.homeMintIcon,
        eyebrowColor: BespokeColor.homeGold.opacity(0.88),
        subtitleColor: Color(red: 92 / 255, green: 108 / 255, blue: 98 / 255),
        tagBackground: Color(red: 236 / 255, green: 245 / 255, blue: 240 / 255),
        tagTextColor: BespokeColor.forest,
        chevronButtonBackground: .white,
        chevronButtonBorder: Color(red: 214 / 255, green: 232 / 255, blue: 222 / 255),
        chevronColor: BespokeColor.homeGold,
        backdropOpacity: 0.38
    )
}

// MARK: - Content

struct HomeFeatureCardContent {
    let eyebrow: String
    let title: String
    let subtitle: String
    let tag: String
    let tagSymbolName: String
    let theme: HomeFeatureCardTheme
    let iconImageName: String
    let backdropImageName: String
    let backdropAlignment: Alignment

    static let bespoke = HomeFeatureCardContent(
        eyebrow: "CREATE",
        title: "Bespoke my dua",
        subtitle: "Write what's in your heart and receive a refined dua.",
        tag: "From your own words",
        tagSymbolName: "sparkle",
        theme: .create,
        iconImageName: "HomeCardIconBespoke",
        backdropImageName: "HomeCardBackdropBespoke",
        backdropAlignment: .bottomTrailing
    )

    static let sunnah = HomeFeatureCardContent(
        eyebrow: "DISCOVER",
        title: "Sunnah Duas",
        subtitle: "Get authentic duas for how you feel.",
        tag: "Matched to your need",
        tagSymbolName: "heart.fill",
        theme: .discover,
        iconImageName: "HomeCardIconSunnah",
        backdropImageName: "HomeCardBackdropSunnah",
        backdropAlignment: .trailing
    )

    static let names = HomeFeatureCardContent(
        eyebrow: "REFLECT",
        title: "99 Names",
        subtitle: "Explore the beautiful names of Allah.",
        tag: "Daily reflection",
        tagSymbolName: "star.fill",
        theme: .reflect,
        iconImageName: "HomeCardIconNames",
        backdropImageName: "HomeCardBackdropNames",
        backdropAlignment: .bottomTrailing
    )
}

// MARK: - Card

struct HomeFeatureCard: View {
    let content: HomeFeatureCardContent
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: content.backdropAlignment) {
                content.theme.cardBackground

                Image(content.backdropImageName)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 160, maxHeight: 110)
                    .opacity(content.theme.backdropOpacity)
                    .allowsHitTesting(false)

                HStack(alignment: .center, spacing: HomeFeatureCardLayout.iconToTextSpacing) {
                    iconTile
                    contentStack
                        .layoutPriority(1)
                    chevronButton
                }
                .padding(.horizontal, HomeFeatureCardLayout.horizontalPadding)
                .padding(.vertical, HomeFeatureCardLayout.verticalPadding)
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: HomeFeatureCardLayout.height)
            .clipShape(RoundedRectangle(cornerRadius: HomeFeatureCardLayout.cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: HomeFeatureCardLayout.cornerRadius, style: .continuous)
                    .stroke(content.theme.cardBorder, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.06), radius: 16, x: 0, y: 6)
            .contentShape(RoundedRectangle(cornerRadius: HomeFeatureCardLayout.cornerRadius, style: .continuous))
        }
        .buttonStyle(HomeFeatureCardButtonStyle())
    }

    private var iconTile: some View {
        ZStack {
            RoundedRectangle(cornerRadius: HomeFeatureCardLayout.iconCornerRadius, style: .continuous)
                .fill(content.theme.iconTileBackground)
                .frame(width: HomeFeatureCardLayout.iconTileSize, height: HomeFeatureCardLayout.iconTileSize)

            Image(content.iconImageName)
                .resizable()
                .scaledToFit()
                .frame(width: HomeFeatureCardLayout.iconImageSize, height: HomeFeatureCardLayout.iconImageSize)
                .padding(HomeFeatureCardLayout.iconImageInset)
        }
        .frame(width: HomeFeatureCardLayout.iconTileSize, height: HomeFeatureCardLayout.iconTileSize)
        .clipShape(RoundedRectangle(cornerRadius: HomeFeatureCardLayout.iconCornerRadius, style: .continuous))
    }

    private var contentStack: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(content.eyebrow)
                .font(BespokeFont.inter(11, weight: .semibold))
                .tracking(1.1)
                .foregroundStyle(content.theme.eyebrowColor)
                .textCase(.uppercase)
                .padding(.bottom, 3)

            BespokeDisplayTitle(text: content.title, size: 20)
                .multilineTextAlignment(.leading)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
                .padding(.bottom, 4)

            Text(content.subtitle)
                .font(BespokeFont.inter(13, weight: .regular))
                .foregroundStyle(content.theme.subtitleColor)
                .multilineTextAlignment(.leading)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, HomeFeatureCardLayout.subtitleToTagSpacing)

            tagPill
        }
        .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)
    }

    private var tagPill: some View {
        HStack(spacing: 6) {
            Image(systemName: content.tagSymbolName)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(content.theme.tagTextColor)

            Text(content.tag)
                .font(BespokeFont.inter(12, weight: .medium))
                .foregroundStyle(content.theme.tagTextColor)
                .lineLimit(1)
                .minimumScaleFactor(0.9)
        }
        .padding(.horizontal, 12)
        .frame(height: HomeFeatureCardLayout.tagHeight)
        .background(content.theme.tagBackground)
        .clipShape(Capsule())
    }

    private var chevronButton: some View {
        ZStack {
            Circle()
                .fill(content.theme.chevronButtonBackground)
                .overlay {
                    Circle()
                        .stroke(content.theme.chevronButtonBorder, lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.05), radius: 6, x: 0, y: 2)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(content.theme.chevronColor)
        }
        .frame(width: HomeFeatureCardLayout.chevronSize, height: HomeFeatureCardLayout.chevronSize)
    }
}

// MARK: - Layout

enum HomeFeatureCardLayout {
    static let height: CGFloat = 144
    static let cornerRadius: CGFloat = 20
    static let horizontalPadding: CGFloat = 16
    static let verticalPadding: CGFloat = 12
    static let iconTileSize: CGFloat = 80
    static let iconCornerRadius: CGFloat = 22
    static let iconImageSize: CGFloat = 80
    static let iconImageInset: CGFloat = -10
    static let iconToTextSpacing: CGFloat = 12
    static let subtitleToTagSpacing: CGFloat = 8
    static let tagHeight: CGFloat = 26
    static let chevronSize: CGFloat = 40
    static let cardSpacing: CGFloat = 14
    static let pageHorizontalPadding: CGFloat = 22
}

private struct HomeFeatureCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .brightness(configuration.isPressed ? -0.012 : 0)
            .animation(.spring(response: 0.24, dampingFraction: 0.82), value: configuration.isPressed)
    }
}

#Preview("Home Feature Cards") {
    ScrollView {
        VStack(spacing: HomeFeatureCardLayout.cardSpacing) {
            HomeFeatureCard(content: .bespoke) {}
            HomeFeatureCard(content: .sunnah) {}
            HomeFeatureCard(content: .names) {}
        }
        .padding(HomeFeatureCardLayout.pageHorizontalPadding)
    }
    .background(BespokeColor.homeBackground)
}
