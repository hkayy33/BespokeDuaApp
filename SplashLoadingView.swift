import SwiftUI

struct SplashLoadingView: View {
    var body: some View {
        ZStack {
            BespokeColor.splashBackground
                .ignoresSafeArea()

            VStack(spacing: 28) {
                Image("SplashWordmark")
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 248, maxHeight: 182)
                    .accessibilityLabel("BespokeDua")

                VStack(spacing: 8) {
                    Text("I am as My servant thinks I am…")
                        .font(BespokeFont.inter(16, weight: .regular))
                        .foregroundStyle(BespokeColor.splashTitle.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("[Hadith Qudsi]")
                        .font(BespokeFont.inter(13, weight: .medium))
                        .foregroundStyle(BespokeColor.splashTitle.opacity(0.68))
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 32)
        }
    }
}

#Preview {
    SplashLoadingView()
}
