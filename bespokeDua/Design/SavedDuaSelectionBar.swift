import SwiftUI

enum SavedDuaSelectionContext {
    case library
    case collection

    var deleteTitle: String {
        switch self {
        case .library: "Delete"
        case .collection: "Remove"
        }
    }

    var deleteIcon: String {
        switch self {
        case .library: "trash"
        case .collection: "folder.badge.minus"
        }
    }
}

struct SavedDuaSelectionBar: View {
    let selectedCount: Int
    let context: SavedDuaSelectionContext
    let showsMove: Bool
    let onDelete: () -> Void
    let onMove: () -> Void
    let onDone: () -> Void

    static let layoutHeight: CGFloat = 62

    static var scrollClearanceHeight: CGFloat {
        layoutHeight + MainTabBarLayout.bottomSafeInset
    }

    private var actionsEnabled: Bool { selectedCount > 0 }

    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(BespokeColor.sectionRule)
                .frame(height: 1)

            HStack(alignment: .top, spacing: 0) {
                HStack(alignment: .top, spacing: 28) {
                    selectionActionButton(
                        icon: context.deleteIcon,
                        title: context.deleteTitle,
                        color: BespokeColor.error,
                        action: onDelete
                    )

                    if showsMove {
                        selectionActionButton(
                            icon: "folder",
                            title: "Move to collection",
                            color: BespokeColor.forest,
                            action: onMove
                        )
                    }
                }

                Spacer(minLength: 16)

                Button(action: onDone) {
                    HStack(spacing: 6) {
                        Text("Close")
                            .font(BespokeFont.inter(16, weight: .semibold))
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(BespokeColor.bodyText)
                    .frame(height: 21, alignment: .center)
                }
                .buttonStyle(BespokePlainButtonStyle())
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 2)
        }
        .background {
            Color.white
                .ignoresSafeArea(edges: .bottom)
        }
        .ignoresSafeArea(edges: .bottom)
    }

    private func selectionActionButton(
        icon: String,
        title: String,
        color: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 21, weight: .regular))
                    .frame(height: 21)

                Text(title)
                    .font(BespokeFont.inter(12, weight: .medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(actionsEnabled ? color : BespokeColor.muted)
            .padding(.vertical, 4)
        }
        .buttonStyle(BespokePlainButtonStyle())
        .disabled(!actionsEnabled)
    }
}
