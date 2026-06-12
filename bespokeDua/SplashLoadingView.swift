import SwiftUI

struct SplashLoadingView: View {
    @State private var appeared = false
    @State private var glowPulse = false

    var body: some View {
        ZStack {
            splashBackground
                .ignoresSafeArea()

            Circle()
                .fill(BespokeColor.iconHandGold.opacity(0.1))
                .frame(width: 300, height: 300)
                .blur(radius: 56)
                .scaleEffect(glowPulse ? 1.1 : 0.9)
                .opacity(appeared ? 1 : 0)

            VStack(spacing: 0) {
                Spacer()

                brandMark
                    .padding(.bottom, 40)

                quoteBlock
                    .padding(.bottom, 52)

                SplashLoadingIndicator()
                    .opacity(appeared ? 1 : 0)

                Spacer()
                    .frame(height: 56)
            }
            .padding(.horizontal, 36)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.6)) {
                appeared = true
            }
            withAnimation(.easeInOut(duration: 2.4).repeatForever(autoreverses: true)) {
                glowPulse = true
            }
        }
    }

    private var splashBackground: some View {
        ZStack {
            BespokeColor.splashBackground

            RadialGradient(
                colors: [
                    Color(red: 36 / 255, green: 82 / 255, blue: 62 / 255),
                    BespokeColor.splashBackground,
                    Color(red: 16 / 255, green: 40 / 255, blue: 30 / 255)
                ],
                center: .center,
                startRadius: 20,
                endRadius: 460
            )

            LinearGradient(
                colors: [
                    BespokeColor.iconHandGold.opacity(0.06),
                    .clear,
                    .clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    private var brandMark: some View {
        ZStack {
            Image("SplashHands")
                .resizable()
                .scaledToFit()
                .frame(maxWidth: 236, maxHeight: 214)
                .shadow(color: BespokeColor.iconHandGold.opacity(0.22), radius: 18, y: 6)
                .scaleEffect(appeared ? 1 : 0.94)
                .opacity(appeared ? 1 : 0)

            Text("BespokeDua")
                .font(BespokeFont.display(30))
                .foregroundStyle(LinearGradient.bespokeGold)
                .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
                .offset(y: 14)
                .opacity(appeared ? 1 : 0)
                .offset(y: appeared ? 0 : 8)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("BespokeDua")
    }

    private var quoteBlock: some View {
        VStack(spacing: 10) {
            Text("I am as My servant thinks I am…")
                .font(BespokeFont.inter(15, weight: .regular))
                .foregroundStyle(BespokeColor.iconHandGold.opacity(0.88))
                .multilineTextAlignment(.center)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            Text("Hadith Qudsi")
                .font(BespokeFont.inter(11, weight: .semibold))
                .foregroundStyle(BespokeColor.iconHandGold.opacity(0.55))
                .tracking(1.4)
                .textCase(.uppercase)
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 12)
    }
}

private struct SplashLoadingIndicator: View {
    var body: some View {
        HStack(spacing: 9) {
            ForEach(0 ..< 3, id: \.self) { index in
                PhaseAnimator([false, true]) { pulsed in
                    Circle()
                        .fill(BespokeColor.iconHandGold)
                        .frame(width: 6, height: 6)
                        .scaleEffect(pulsed ? 1.2 : 0.85)
                        .opacity(pulsed ? 1 : 0.35)
                } animation: { _ in
                    .easeInOut(duration: 0.55)
                        .delay(Double(index) * 0.18)
                        .repeatForever(autoreverses: true)
                }
            }
        }
        .accessibilityLabel("Loading")
    }
}

#Preview {
    SplashLoadingView()
}
