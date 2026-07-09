import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

enum FeelingBackdrop {
    static func assetName(for feelingLabelId: Int) -> String {
        "FeelingBackdrop\(String(format: "%02d", feelingLabelId))"
    }

    static let allAssetName = "FeelingBackdropAll"

    static func symbolName(for feelingLabelId: Int) -> String {
        switch feelingLabelId {
        case 1: "hands.sparkles.fill"
        case 2: "moon.zzz.fill"
        case 3: "sun.max.fill"
        case 4: "cloud.bolt.rain.fill"
        case 5: "leaf.fill"
        case 6: "figure.walk"
        case 7: "signpost.right.and.left.fill"
        case 8: "shield.lefthalf.filled"
        case 9: "heart.slash.fill"
        default: "sparkles"
        }
    }

    static let allSymbolName = "books.vertical.fill"

    static func accentColors(for feelingLabelId: Int) -> [Color] {
        switch feelingLabelId {
        case 1:
            [Color(red: 0.18, green: 0.42, blue: 0.48), Color(red: 0.72, green: 0.58, blue: 0.34)]
        case 2:
            [Color(red: 0.28, green: 0.30, blue: 0.42), Color(red: 0.45, green: 0.40, blue: 0.52)]
        case 3:
            [Color(red: 0.78, green: 0.58, blue: 0.22), Color(red: 0.92, green: 0.76, blue: 0.38)]
        case 4:
            [Color(red: 0.22, green: 0.32, blue: 0.46), Color(red: 0.38, green: 0.44, blue: 0.58)]
        case 5:
            [Color(red: 0.32, green: 0.40, blue: 0.50), Color(red: 0.52, green: 0.56, blue: 0.62)]
        case 6:
            [Color(red: 0.20, green: 0.38, blue: 0.34), Color(red: 0.58, green: 0.62, blue: 0.48)]
        case 7:
            [Color(red: 0.26, green: 0.36, blue: 0.44), Color(red: 0.48, green: 0.58, blue: 0.54)]
        case 8:
            [Color(red: 0.24, green: 0.28, blue: 0.42), Color(red: 0.62, green: 0.48, blue: 0.30)]
        case 9:
            [Color(red: 0.14, green: 0.22, blue: 0.38), Color(red: 0.34, green: 0.38, blue: 0.56)]
        default:
            [BespokeColor.forest, BespokeColor.goldDeep]
        }
    }

    static let allAccentColors: [Color] = [
        Color(red: 0.12, green: 0.34, blue: 0.28),
        Color(red: 0.62, green: 0.48, blue: 0.24)
    ]
}

struct FeelingBackdropView: View {
    enum OverlayStyle {
        case card
        case header
    }

    let assetName: String
    let symbolName: String
    let accentColors: [Color]
    var showsSymbol: Bool = true
    var overlayStyle: OverlayStyle = .card

    var body: some View {
        ZStack {
            if backdropImageExists(assetName) {
                Image(assetName)
                    .resizable()
                    .scaledToFill()
            } else {
                LinearGradient(
                    colors: accentColors,
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                if showsSymbol {
                    Image(systemName: symbolName)
                        .font(.system(size: 64, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.14))
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                        .padding(.trailing, 18)
                        .padding(.top, 8)
                }
            }

            overlay
        }
        .clipped()
    }

    @ViewBuilder
    private var overlay: some View {
        switch overlayStyle {
        case .card:
            LinearGradient(
                colors: [
                    Color.black.opacity(0.22),
                    Color.black.opacity(0.58)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        case .header:
            LinearGradient(
                colors: [
                    Color.black.opacity(0.34),
                    Color.black.opacity(0.5)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private func backdropImageExists(_ name: String) -> Bool {
        #if canImport(UIKit)
        UIImage(named: name) != nil
        #else
        false
        #endif
    }
}
