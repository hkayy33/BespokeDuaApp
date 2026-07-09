import SwiftUI
#if canImport(UIKit)
import UIKit
import MessageUI
#endif

enum FeedbackIntent {
    case general
    case featureRequest
}

struct FeedbackView: View {
    var intent: FeedbackIntent = .general

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.mainTabBarClearance) private var mainTabBarClearance

    @State private var message = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(intent == .featureRequest ? "Tell us what you’d like to see next" : "We’d love to hear from you")
                    .font(BespokeFont.display(22))
                    .foregroundStyle(BespokeColor.forest)

                Text(intent == .featureRequest
                     ? "Describe a feature or improvement that would help your dua practice."
                     : "Share ideas, report a problem, or tell us how BespokeDua has helped you.")
                    .font(BespokeFont.inter(14, weight: .regular))
                    .foregroundStyle(BespokeColor.muted)
                    .fixedSize(horizontal: false, vertical: true)

                ZStack(alignment: .topLeading) {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(BespokeColor.inputBorder, lineWidth: 1)
                        .background(
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color.white)
                        )

                    if message.isEmpty {
                        Text(intent == .featureRequest ? "Describe your feature idea…" : "Write your feedback here…")
                            .font(BespokeFont.inter(15, weight: .regular))
                            .foregroundStyle(BespokeColor.subtle)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 14)
                            .allowsHitTesting(false)
                    }

                    TextEditor(text: $message)
                        .font(BespokeFont.inter(15, weight: .regular))
                        .foregroundStyle(BespokeColor.bodyText)
                        .scrollContentBackground(.hidden)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .frame(minHeight: 160)
                        .focused($fieldFocused)
                }
                .frame(minHeight: 180)

                Button(action: sendFeedback) {
                    Text("Send feedback")
                        .font(BespokeFont.inter(16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(canSend ? BespokeColor.forest : BespokeColor.forest.opacity(0.45))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .buttonStyle(BespokePlainButtonStyle())
                .disabled(!canSend)
            }
            .padding(.horizontal, 20)
            .padding(.top, 24)
            .padding(.bottom, 24 + mainTabBarClearance)
        }
        .scrollIndicators(.hidden, axes: .vertical)
        .scrollDismissesKeyboard(.interactively)
        .background(BespokeColor.pageBackground)
        .navigationTitle(intent == .featureRequest ? "Feature request" : "Feedback")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
                    .font(BespokeFont.inter(16, weight: .semibold))
                    .foregroundStyle(BespokeColor.forest)
            }
        }
    }

    private var canSend: Bool {
        !message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func sendFeedback() {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let subject = intent == .featureRequest ? "BespokeDua Feature Request" : "BespokeDua Feedback"
        let body = """
        \(trimmed)

        —
        App: \(BespokeAppMetadata.marketingName) \(BespokeAppMetadata.shortVersionString)
        """

        BespokeAppMetadata.openEmail(
            url: BespokeAppMetadata.mailtoURL(subject: subject, body: body),
            openURL: { openURL($0) }
        )

        dismiss()
    }
}
