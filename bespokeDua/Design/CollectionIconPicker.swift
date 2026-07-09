import SwiftUI

struct CollectionIconPicker: View {
    @Binding var selectedSymbol: String

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 4)

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(DuaCollectionIcons.options, id: \.self) { symbol in
                Button {
                    selectedSymbol = symbol
                } label: {
                    Image(systemName: symbol)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(selectedSymbol == symbol ? BespokeColor.forest : BespokeColor.muted)
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(selectedSymbol == symbol ? BespokeColor.cream : Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .stroke(
                                    selectedSymbol == symbol ? BespokeColor.forest.opacity(0.35) : BespokeColor.cardBorder,
                                    lineWidth: selectedSymbol == symbol ? 1.5 : 1
                                )
                        }
                        .bespokeButtonHitArea(cornerRadius: 14)
                }
                .buttonStyle(BespokePlainButtonStyle())
                .accessibilityLabel(symbol)
                .accessibilityAddTraits(selectedSymbol == symbol ? .isSelected : [])
            }
        }
    }
}
