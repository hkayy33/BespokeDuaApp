import SwiftUI

enum CraftingDhikrMetrics {
    static let panelHeight: CGFloat = 228
}

struct CraftingDhikr: Identifiable {
    let id: String
    let arabic: String
    let transliteration: String
    let english: String

    static let carousel: [CraftingDhikr] = [
        CraftingDhikr(
            id: "subhanallah",
            arabic: "سُبْحَانَ اللَّهِ",
            transliteration: "SubhanAllah",
            english: "Glory be to Allah"
        ),
        CraftingDhikr(
            id: "allahuakbar",
            arabic: "اللَّهُ أَكْبَرُ",
            transliteration: "Allahu Akbar",
            english: "Allah is the Greatest"
        ),
        CraftingDhikr(
            id: "alhamdulillah",
            arabic: "الْحَمْدُ لِلَّهِ",
            transliteration: "Alhamdulillah",
            english: "All praise is for Allah"
        ),
        CraftingDhikr(
            id: "salawat",
            arabic: "اللَّهُمَّ صَلِّ عَلَى مُحَمَّدٍ",
            transliteration: "Salawat",
            english: "Send blessings upon Muhammad ﷺ"
        )
    ]
}

struct DuaCraftingDhikrCarousel: View {
    var statusText: String = "Crafting your duas with care…"

    @State private var selectedIndex = 0
    private let dhikrItems = CraftingDhikr.carousel
    private let rotationInterval: TimeInterval = 3.2

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .fill(BespokeColor.feedSurface)

            Image("DhikrCardBackdrop")
                .resizable()
                .scaledToFit()
                .opacity(0.88)
                .blendMode(.multiply)
                .padding(10)
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))

            VStack(spacing: 8) {
                dhikrContent(for: dhikrItems[selectedIndex])
                    .id(dhikrItems[selectedIndex].id)
                    .transition(.opacity.combined(with: .scale(scale: 0.98)))

                Rectangle()
                    .fill(BespokeColor.sectionRule)
                    .frame(height: 1)
                    .padding(.horizontal, 8)

                Text(statusText)
                    .font(BespokeFont.inter(13, weight: .medium))
                    .foregroundStyle(BespokeColor.forest)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)

                paginationDots
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(maxWidth: .infinity)
        .frame(height: CraftingDhikrMetrics.panelHeight)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(BespokeColor.forest.opacity(0.08), lineWidth: 1)
        }
        .task {
            await rotateDhikr()
        }
    }

    @ViewBuilder
    private func dhikrContent(for item: CraftingDhikr) -> some View {
        VStack(spacing: 6) {
            Text(item.arabic)
                .font(BespokeFont.display(26))
                .foregroundStyle(BespokeColor.forest)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.85)
                .environment(\.layoutDirection, .rightToLeft)

            Text(item.transliteration)
                .font(BespokeFont.display(19))
                .foregroundStyle(BespokeColor.forest)
                .lineLimit(1)
                .minimumScaleFactor(0.9)

            Text(item.english)
                .font(BespokeFont.inter(13, weight: .regular))
                .foregroundStyle(BespokeColor.muted)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.9)
        }
        .frame(maxWidth: .infinity)
    }

    private var paginationDots: some View {
        HStack(spacing: 8) {
            ForEach(dhikrItems.indices, id: \.self) { index in
                Circle()
                    .fill(index == selectedIndex ? BespokeColor.forest : BespokeColor.forest.opacity(0.2))
                    .frame(width: index == selectedIndex ? 8 : 6, height: index == selectedIndex ? 8 : 6)
            }
        }
    }

    @MainActor
    private func rotateDhikr() async {
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(rotationInterval))
            withAnimation(.easeInOut(duration: 0.45)) {
                selectedIndex = (selectedIndex + 1) % dhikrItems.count
            }
        }
    }
}

struct DuaCraftingResultsPlaceholder: View {
    var body: some View {
        VStack(spacing: 10) {
            Text("No duas yet")
                .font(BespokeFont.inter(17, weight: .semibold))
                .foregroundStyle(BespokeColor.forest)

            Text("Write what is in your heart, then tap Bespoke my dua to generate options you can save or copy.")
                .font(BespokeFont.inter(14, weight: .regular))
                .foregroundStyle(BespokeColor.muted)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 20)
        .background(Color.white.opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(BespokeColor.cardBorder, lineWidth: 1)
        }
    }
}
