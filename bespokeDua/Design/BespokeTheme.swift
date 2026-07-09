import CoreText
import SwiftUI

enum BespokeColor {
    /// Launch / splash screen — matches branded artwork background (~`#1b3d2f`).
    static let splashBackground = Color(red: 27 / 255, green: 61 / 255, blue: 47 / 255)
    /// Prayer-hand stroke on the app icon (~`#efc978`).
    static let iconHandGold = Color(red: 239 / 255, green: 201 / 255, blue: 120 / 255)
    /// Wordmark on splash (~warm tan from brand artwork).
    static let splashTitle = Color(red: 216 / 255, green: 176 / 255, blue: 140 / 255)

    static let pageBackground = Color(red: 250 / 255, green: 250 / 255, blue: 250 / 255)
    /// Home screen canvas (~`#F9F8F3`).
    static let homeBackground = Color(red: 249 / 255, green: 248 / 255, blue: 243 / 255)
    /// Mint tile behind home action-card icons (~`#E5EEE9`).
    static let homeMintIcon = Color(red: 229 / 255, green: 238 / 255, blue: 233 / 255)
    /// Beige tile behind the Sunnah home card icon (~`#F2EBE0`).
    static let homeBeigeIcon = Color(red: 242 / 255, green: 235 / 255, blue: 224 / 255)
    /// Continue-card icon tile (~`#E8F0EA`).
    static let homeContinueIcon = Color(red: 232 / 255, green: 240 / 255, blue: 234 / 255)
    /// Light cream fill for the Sunnah home card (~`#F7F4EC`).
    static let homeCardCream = Color(red: 247 / 255, green: 244 / 255, blue: 236 / 255)
    /// Light green fill for the Dua Feed home card (~`#EEF5F0`).
    static let homeCardGreen = Color(red: 238 / 255, green: 245 / 255, blue: 240 / 255)
    /// Dua Feed banners and action surfaces (~`#F1F8E9`).
    static let feedSurface = Color(red: 241 / 255, green: 248 / 255, blue: 233 / 255)
    static let forest = Color(red: 15 / 255, green: 61 / 255, blue: 46 / 255)
    static let forestHover = Color(red: 13 / 255, green: 53 / 255, blue: 40 / 255)
    static let gold = Color(red: 200 / 255, green: 155 / 255, blue: 60 / 255)
    /// Home accent gold for chevrons and links (~`#B08D49`).
    static let homeGold = Color(red: 176 / 255, green: 141 / 255, blue: 73 / 255)
    static let goldHover = Color(red: 184 / 255, green: 144 / 255, blue: 58 / 255)
    static let goldDeep = Color(red: 169 / 255, green: 119 / 255, blue: 34 / 255)
    static let cream = Color(red: 247 / 255, green: 244 / 255, blue: 236 / 255)
    static let quoteText = Color(red: 232 / 255, green: 232 / 255, blue: 232 / 255)
    static let navBorderGold = Color(red: 200 / 255, green: 155 / 255, blue: 60 / 255).opacity(0.18)

    static let heading = Color(red: 47 / 255, green: 47 / 255, blue: 47 / 255)
    static let muted = Color(red: 102 / 255, green: 102 / 255, blue: 102 / 255)
    static let subtle = Color(red: 136 / 255, green: 136 / 255, blue: 136 / 255)
    static let bodyText = Color(red: 51 / 255, green: 51 / 255, blue: 51 / 255)

    static let inputBorder = Color(red: 228 / 255, green: 228 / 255, blue: 228 / 255)
    static let sectionRule = Color(red: 236 / 255, green: 236 / 255, blue: 236 / 255)

    static let cardBorder = Color(red: 232 / 255, green: 232 / 255, blue: 232 / 255)
    static let cardBackground = pageBackground
    static let nameGold = Color(red: 183 / 255, green: 137 / 255, blue: 47 / 255)

    static let error = Color(red: 198 / 255, green: 40 / 255, blue: 40 / 255)
    static let fieldLabel = Color(red: 38 / 255, green: 74 / 255, blue: 56 / 255)
    static let inputSurface = Color(red: 251 / 255, green: 252 / 255, blue: 251 / 255)

    static let loaderIndigo = Color(red: 79 / 255, green: 70 / 255, blue: 229 / 255)
    static let loaderGreen = Color(red: 34 / 255, green: 197 / 255, blue: 94 / 255)

    static let modalBackdrop = Color.black.opacity(0.5)
    static let authBackdrop = Color.black.opacity(0.6)

    static let authCard = Color(red: 247 / 255, green: 244 / 255, blue: 236 / 255).opacity(0.98)
    static let authToggleBg = Color(red: 15 / 255, green: 61 / 255, blue: 46 / 255).opacity(0.08)

    static let clearBtnBorder = Color(red: 226 / 255, green: 226 / 255, blue: 226 / 255)
    static let clearBtnText = Color(red: 90 / 255, green: 90 / 255, blue: 90 / 255)

    /// Bottom tab bar — inactive icon and label (~desaturated grey-green).
    static let tabBarInactive = Color(red: 138 / 255, green: 158 / 255, blue: 150 / 255)
}

enum BespokeFont {
    /// Matches `Playfair Display` / `h1` on web (≈600).
    static func display(_ size: CGFloat) -> Font {
        .custom("PlayfairDisplayRoman-SemiBold", size: size)
    }

    static func inter(_ size: CGFloat, weight: InterWeight = .regular) -> Font {
        .custom(weight.postScriptName, size: size)
    }

    enum InterWeight {
        case regular, medium, semibold, bold

        fileprivate var postScriptName: String {
            switch self {
            case .regular: "Inter-Regular"
            case .medium: "Inter-Regular_Medium"
            case .semibold: "Inter-Regular_SemiBold"
            case .bold: "Inter-Regular_Bold"
            }
        }
    }
}

enum BespokeFonts {
    static func register() {
        let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? []
        for url in urls {
            var error: Unmanaged<CFError>?
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, &error)
        }
    }
}

extension LinearGradient {
    @MainActor
    static var bespokeGold: LinearGradient {
        LinearGradient(
            colors: [BespokeColor.gold, BespokeColor.goldDeep],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Forest toolbar with a soft fade into the scroll background at the bottom edge.
    @MainActor
    static var bespokeNavBar: LinearGradient {
        LinearGradient(
            stops: [
                .init(color: BespokeColor.forest, location: 0),
                .init(color: BespokeColor.forest, location: 0.55),
                .init(color: BespokeColor.forest.opacity(0.42), location: 0.82),
                .init(color: BespokeColor.pageBackground, location: 1)
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Flat forest toolbar for library-style tabs where content carries the page title.
    @MainActor
    static var bespokeNavBarCompact: LinearGradient {
        LinearGradient(
            colors: [BespokeColor.forest, BespokeColor.forest],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    /// Home, Dua Feed, and Saved tab canvas.
    @MainActor
    static var bespokeHomeCanvas: LinearGradient {
        LinearGradient(
            colors: [
                BespokeColor.homeBackground,
                BespokeColor.pageBackground
            ],
            startPoint: .top,
            endPoint: UnitPoint(x: 0.5, y: 0.22)
        )
    }
}

// MARK: - Button hit testing

/// Plain button style that keeps the full custom label area tappable.
struct BespokePlainButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .contentShape(Rectangle())
            .opacity(configuration.isPressed ? 0.94 : 1)
    }
}

/// Playfair’s old-style figures sit lower than capitals — nudge leading digits up for titles like “99 Names”.
struct BespokeDisplayTitle: View {
    let text: String
    let size: CGFloat
    var color: Color = BespokeColor.forest

    var body: some View {
        Group {
            if let split = Self.splitLeadingDigits(from: text) {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(split.digits)
                        .baselineOffset(size * 0.14)
                    Text(split.remainder)
                }
            } else {
                Text(text)
            }
        }
        .font(BespokeFont.display(size))
        .foregroundStyle(color)
    }

    private struct DigitSplit {
        let digits: String
        let remainder: String
    }

    private static func splitLeadingDigits(from text: String) -> DigitSplit? {
        guard let firstNonDigit = text.firstIndex(where: { !$0.isNumber }) else { return nil }
        let digits = String(text[..<firstNonDigit])
        guard !digits.isEmpty else { return nil }
        let remainder = String(text[firstNonDigit...]).trimmingCharacters(in: .whitespaces)
        guard !remainder.isEmpty else { return nil }
        return DigitSplit(digits: digits, remainder: remainder)
    }
}

extension View {
    /// Use at the end of custom `Button` labels so the full styled area receives taps.
    func bespokeButtonHitArea<S: Shape>(_ shape: S) -> some View {
        contentShape(shape)
    }

    func bespokeButtonHitArea(cornerRadius: CGFloat) -> some View {
        contentShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}
