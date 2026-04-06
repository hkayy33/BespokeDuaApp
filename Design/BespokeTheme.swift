import CoreText
import SwiftUI

enum BespokeColor {
    /// Launch / splash screen — matches branded artwork background (~`#1b3d2f`).
    static let splashBackground = Color(red: 27 / 255, green: 61 / 255, blue: 47 / 255)
    /// Wordmark on splash (~warm tan from brand artwork).
    static let splashTitle = Color(red: 216 / 255, green: 176 / 255, blue: 140 / 255)

    static let pageBackground = Color(red: 250 / 255, green: 250 / 255, blue: 250 / 255)
    static let forest = Color(red: 15 / 255, green: 61 / 255, blue: 46 / 255)
    static let forestHover = Color(red: 13 / 255, green: 53 / 255, blue: 40 / 255)
    static let gold = Color(red: 200 / 255, green: 155 / 255, blue: 60 / 255)
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
    static var bespokeGold: LinearGradient {
        LinearGradient(
            colors: [BespokeColor.gold, BespokeColor.goldDeep],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    /// Forest toolbar with a soft fade into the scroll background at the bottom edge.
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
}
