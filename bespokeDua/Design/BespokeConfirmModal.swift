import SwiftUI

struct BespokeConfirmModal: View {
    let title: String
    let message: String
    let confirmTitle: String
    var confirmStyle: ConfirmStyle = .destructive
    var inFlight: Bool = false
    var errorMessage: String? = nil
    let onCancel: () -> Void
    let onConfirm: () -> Void

    enum ConfirmStyle {
        case destructive
        case primary
    }

    var body: some View {
        ZStack {
            BespokeColor.authBackdrop
                .ignoresSafeArea()
                .onTapGesture {
                    guard !inFlight else { return }
                    onCancel()
                }

            VStack(alignment: .leading, spacing: 18) {
                Text(title)
                    .font(BespokeFont.inter(29.6, weight: .semibold))
                    .foregroundStyle(BespokeColor.forest)

                Text(message)
                    .font(BespokeFont.inter(16, weight: .regular))
                    .foregroundStyle(BespokeColor.bodyText)
                    .fixedSize(horizontal: false, vertical: true)

                if let errorMessage, !errorMessage.isEmpty {
                    Text(errorMessage)
                        .font(BespokeFont.inter(14, weight: .regular))
                        .foregroundStyle(BespokeColor.error)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 12) {
                    Button(action: onCancel) {
                        Text("Cancel")
                            .font(BespokeFont.inter(16, weight: .semibold))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                    .buttonStyle(.bordered)
                    .tint(BespokeColor.forest)
                    .disabled(inFlight)

                    Button(action: onConfirm) {
                        Text(confirmTitle)
                            .font(BespokeFont.inter(16, weight: .semibold))
                            .foregroundStyle(BespokeColor.cream)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                            .background(confirmBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            .bespokeButtonHitArea(cornerRadius: 16)
                    }
                    .buttonStyle(BespokePlainButtonStyle())
                    .disabled(inFlight)
                    .opacity(inFlight ? 0.65 : 1)
                }
            }
            .frame(maxWidth: 540)
            .padding(24)
            .background(BespokeColor.authCard)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(BespokeColor.forest.opacity(0.18), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.18), radius: 35, x: 0, y: 25)
            .padding(16)
        }
    }

    private var confirmBackground: Color {
        switch confirmStyle {
        case .destructive: BespokeColor.error
        case .primary: BespokeColor.forest
        }
    }
}
