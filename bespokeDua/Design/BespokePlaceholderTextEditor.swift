import SwiftUI

/// Multiline input with a placeholder that reliably hides while typing.
/// `TextEditor` + inline `if text.isEmpty` placeholders can fail to refresh inside large parent views.
struct BespokePlaceholderTextEditor: View {
    @Binding var text: String
    var placeholder: String
    var minHeight: CGFloat = 120
    var focus: FocusState<Bool>.Binding

    var body: some View {
        ZStack(alignment: .topLeading) {
            Text(placeholder)
                .font(BespokeFont.inter(16, weight: .regular))
                .foregroundStyle(BespokeColor.subtle)
                .padding(.horizontal, 5)
                .padding(.vertical, 8)
                .allowsHitTesting(false)
                .accessibilityHidden(!text.isEmpty)
                .opacity(text.isEmpty ? 1 : 0)

            TextEditor(text: $text)
                .font(BespokeFont.inter(16, weight: .regular))
                .foregroundStyle(BespokeColor.bodyText)
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 1)
                .frame(minHeight: minHeight)
                .focused(focus)
        }
    }
}
