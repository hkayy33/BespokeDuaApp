import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

struct WriteOwnDuaToolbarButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 36, height: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(BespokePlainButtonStyle())
        .accessibilityLabel("Write your own dua")
    }
}

struct WriteOwnDuaModalView: View {
    @Environment(AppSession.self) private var session
    @Environment(\.openBespokeDua) private var openBespokeDua

    @Binding var isPresented: Bool
    /// When set, Save also adds the written dua to this collection.
    var collectionId: String?
    var onSaved: ((SavedDuaDTO) -> Void)?

    @State private var text = ""
    @State private var saveInFlight = false
    @State private var savedRow: SavedDuaDTO?
    @State private var saveError: String?
    @State private var keyboardHeight: CGFloat = 0
    @FocusState private var editorFocused: Bool

    private var trimmedText: String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSubmit: Bool {
        !trimmedText.isEmpty && !saveInFlight
    }

    private var modalBinding: Binding<Bool> {
        Binding(
            get: { isPresented },
            set: { newValue in
                guard !saveInFlight else { return }
                isPresented = newValue
            }
        )
    }

    var body: some View {
        BespokeCardModalView(isPresented: modalBinding, title: "Write your dua") {
            Text(helperText)
                .font(BespokeFont.inter(15, weight: .regular))
                .foregroundStyle(BespokeColor.muted)
                .fixedSize(horizontal: false, vertical: true)

            BespokePlaceholderTextEditor(
                text: $text,
                placeholder: "Type your dua here…",
                minHeight: 140,
                focus: $editorFocused
            )
            .padding(12)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(editorFocused ? BespokeColor.gold : BespokeColor.inputBorder, lineWidth: editorFocused ? 2 : 1)
            )

            if let saveError, !saveError.isEmpty {
                Text(saveError)
                    .font(BespokeFont.inter(14, weight: .regular))
                    .foregroundStyle(BespokeColor.error)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 12) {
                Button {
                    Task { await saveWrittenDua() }
                } label: {
                    Text(saveInFlight ? "Saving…" : "Save")
                        .font(BespokeFont.inter(16, weight: .semibold))
                        .foregroundStyle(BespokeColor.cream)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                        .background(BespokeColor.forest)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .bespokeButtonHitArea(cornerRadius: 16)
                }
                .buttonStyle(BespokePlainButtonStyle())
                .disabled(!canSubmit)
                .opacity(canSubmit ? 1 : 0.55)

                Button {
                    sendToBespoke()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Bespoke")
                            .font(BespokeFont.inter(16, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(LinearGradient.bespokeGold)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .bespokeButtonHitArea(cornerRadius: 16)
                }
                .buttonStyle(BespokePlainButtonStyle())
                .disabled(!canSubmit)
                .opacity(canSubmit ? 1 : 0.55)
            }
        }
        .offset(y: keyboardLift)
        .onAppear {
            editorFocused = true
        }
        #if canImport(UIKit)
        .onReceive(NotificationCenter.default.publisher(for: UIResponder.keyboardWillChangeFrameNotification)) { notification in
            guard
                let frame = notification.userInfo?[UIResponder.keyboardFrameEndUserInfoKey] as? CGRect
            else { return }
            let overlap = UIScreen.main.bounds.height - frame.minY
            keyboardHeight = max(0, overlap)
        }
        #endif
    }

    private var keyboardLift: CGFloat {
        guard keyboardHeight > 0 else { return 0 }
        return -min(keyboardHeight * 0.42, 180)
    }

    private var helperText: String {
        if collectionId != nil {
            return "Save it to this collection, or send it to Bespoke to generate refined duas."
        }
        return "Save it to your library, or send it to Bespoke to generate refined duas."
    }

    private func sendToBespoke() {
        guard canSubmit else { return }
        editorFocused = false
        let draft = trimmedText
        isPresented = false
        openBespokeDua(draft)
    }

    @MainActor
    private func saveWrittenDua() async {
        guard canSubmit else { return }
        guard let uid = session.currentUser?.userId else {
            session.presentAuth()
            return
        }

        saveInFlight = true
        saveError = nil
        defer { saveInFlight = false }

        do {
            let saved: SavedDuaDTO
            if let savedRow {
                saved = savedRow
            } else {
                saved = try await session.api().saveDua(userId: uid, duaText: trimmedText)
                session.insertSavedDua(saved)
                savedRow = saved
            }

            if let collectionId {
                try await addToCollection(saved, collectionId: collectionId)
            }

            BespokeHaptics.success()
            onSaved?(saved)
            isPresented = false
        } catch {
            saveError = (error as? LocalizedError)?.errorDescription ?? "Something went wrong. Try again."
        }
    }

    @MainActor
    private func addToCollection(_ saved: SavedDuaDTO, collectionId: String) async throws {
        let detail = try await session.api().duaCollection(id: collectionId)
        var duaIds = detail.savedDuaIds
        if !duaIds.contains(saved.duaId) {
            duaIds.append(saved.duaId)
        }
        let updated = try await session.api().updateDuaCollection(
            id: collectionId,
            body: UpdateDuaCollectionRequest(
                name: detail.name,
                description: detail.description,
                duaIds: duaIds
            )
        )
        session.upsertDuaCollection(from: updated)
    }
}
