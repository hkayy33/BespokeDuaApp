import SwiftUI

enum DuaFeedAvatar {
    struct Style: Hashable {
        let symbolName: String
        let background: Color
        let accent: Color
    }

    static let options: [Style] = [
        Style(
            symbolName: "star.fill",
            background: Color(red: 255 / 255, green: 249 / 255, blue: 196 / 255),
            accent: Color(red: 249 / 255, green: 168 / 255, blue: 37 / 255)
        ),
        Style(
            symbolName: "hands.sparkles",
            background: Color(red: 240 / 255, green: 247 / 255, blue: 240 / 255),
            accent: Color(red: 45 / 255, green: 90 / 255, blue: 39 / 255)
        ),
        Style(
            symbolName: "moon.fill",
            background: Color(red: 255 / 255, green: 247 / 255, blue: 237 / 255),
            accent: Color(red: 154 / 255, green: 99 / 255, blue: 36 / 255)
        ),
        Style(
            symbolName: "person.crop.circle.fill",
            background: Color(red: 243 / 255, green: 240 / 255, blue: 247 / 255),
            accent: Color(red: 74 / 255, green: 59 / 255, blue: 140 / 255)
        )
    ]

    static func style(for postID: UUID) -> Style {
        let seed = postID.uuid.0 ^ postID.uuid.1 ^ postID.uuid.2 ^ postID.uuid.3
        let index = Int(seed) % options.count
        return options[index]
    }
}

struct DuaFeedAvatarView: View {
    let postID: UUID
    var size: CGFloat = 40

    private var style: DuaFeedAvatar.Style {
        DuaFeedAvatar.style(for: postID)
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(style.background)
                .frame(width: size, height: size)

            Image(systemName: style.symbolName)
                .font(.system(size: size * 0.42, weight: .semibold))
                .foregroundStyle(style.accent)
        }
        .accessibilityHidden(true)
    }
}
