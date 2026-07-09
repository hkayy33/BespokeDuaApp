import SwiftUI

enum BespokeSocialBrand {
    case instagram
    case tiktok
    case email

    @ViewBuilder
    var icon: some View {
        switch self {
        case .instagram:
            Image("InstagramBrandIcon")
                .resizable()
                .scaledToFit()
        case .tiktok:
            Image("TikTokBrandIcon")
                .resizable()
                .scaledToFit()
        case .email:
            Image(systemName: "envelope.fill")
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(BespokeColor.forest)
        }
    }
}
