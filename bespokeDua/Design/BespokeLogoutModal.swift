import SwiftUI

struct BespokeLogoutModal: View {
    let message: String
    let onCancel: () -> Void
    let onConfirm: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.32)
                .ignoresSafeArea()
                .background(.ultraThinMaterial)
                .onTapGesture(perform: onCancel)

            VStack(spacing: 0) {
                ZStack {
                    Circle()
                        .fill(BespokeColor.error.opacity(0.1))
                        .frame(width: 68, height: 68)

                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(BespokeColor.error)
                }
                .padding(.top, 28)

                VStack(spacing: 10) {
                    Text("Log out?")
                        .font(BespokeFont.display(24))
                        .foregroundStyle(BespokeColor.forest)

                    Text(message)
                        .font(BespokeFont.inter(15, weight: .regular))
                        .foregroundStyle(BespokeColor.muted)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)

                VStack(spacing: 10) {
                    Button(action: onConfirm) {
                        Text("Log out")
                            .font(BespokeFont.inter(16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(BespokeColor.error)
                            .clipShape(Capsule())
                            .bespokeButtonHitArea(Capsule())
                    }
                    .buttonStyle(BespokePlainButtonStyle())

                    Button(action: onCancel) {
                        Text("Cancel")
                            .font(BespokeFont.inter(16, weight: .semibold))
                            .foregroundStyle(BespokeColor.forest)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(BespokePlainButtonStyle())
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
            .shadow(color: .black.opacity(0.14), radius: 36, x: 0, y: 18)
            .padding(.horizontal, 24)
        }
        .transition(.opacity.combined(with: .scale(scale: 0.94)))
    }
}
