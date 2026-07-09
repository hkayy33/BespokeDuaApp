import SwiftUI

#if canImport(UIKit)
import UIKit
#endif

struct EditSavedDuaView: View {
    @Environment(AppSession.self) private var session

    @Binding var isPresented: Bool
    let row: SavedDuaDTO
    let userId: Int?
    var onSaved: ((SavedDuaDTO) -> Void)?

    @State private var editableText: String
    @State private var originalLockedContents: [String]
    @State private var explanations: [ExplanationModel]
    @State private var saveInFlight = false
    @State private var saveError: String?

    init(
        isPresented: Binding<Bool>,
        row: SavedDuaDTO,
        userId: Int?,
        onSaved: ((SavedDuaDTO) -> Void)? = nil
    ) {
        _isPresented = isPresented
        self.row = row
        self.userId = userId
        self.onSaved = onSaved

        let receiver = SavedDuaDisplay.duaReceiver(from: row, userId: userId)
        let parsed = DuaTextSegments.parse(duaText: receiver.duaText, explanations: receiver.explanations)
        _editableText = State(initialValue: DuaTextSegments.assemble(parsed))
        _originalLockedContents = State(initialValue: parsed.filter(\.isLocked).map(\.content))
        _explanations = State(initialValue: receiver.explanations)
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

    private var trimmedText: String {
        editableText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canSave: Bool {
        !saveInFlight && !trimmedText.isEmpty
    }

    var body: some View {
        BespokeCardModalView(isPresented: modalBinding, title: "Edit dua") {
            Text("Divine names stay in place and cannot be changed or removed.")
                .font(BespokeFont.inter(15, weight: .regular))
                .foregroundStyle(BespokeColor.muted)
                .fixedSize(horizontal: false, vertical: true)

            LockedNamesTextEditor(
                text: $editableText,
                lockedTexts: originalLockedContents
            )
            .padding(16)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(BespokeColor.cardBorder, lineWidth: 1)
            )

            if let saveError {
                Text(saveError)
                    .font(BespokeFont.inter(14, weight: .medium))
                    .foregroundStyle(BespokeColor.error)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                Task { await save() }
            } label: {
                Group {
                    if saveInFlight {
                        ProgressView()
                            .tint(.white)
                    } else {
                        Text("Save")
                            .font(BespokeFont.inter(17, weight: .semibold))
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(canSave ? AnyShapeStyle(LinearGradient.bespokeGold) : AnyShapeStyle(BespokeColor.muted.opacity(0.35)))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .bespokeButtonHitArea(cornerRadius: 16)
            }
            .buttonStyle(BespokePlainButtonStyle())
            .disabled(!canSave)
            .padding(.top, 4)
        }
    }

    private func save() async {
        saveError = nil

        guard DuaTextSegments.lockedTextsIntact(originalLocked: originalLockedContents, in: editableText) else {
            saveError = "The divine names cannot be changed or removed."
            return
        }

        guard !trimmedText.isEmpty else {
            saveError = "Dua text cannot be empty."
            return
        }

        saveInFlight = true
        defer { saveInFlight = false }

        let payload = SavedDuaDisplay.encodeForStorage(duaText: editableText, explanations: explanations)

        do {
            let updated = try await session.updateSavedDuaRow(row, duaPayload: payload)
            if let uid = userId {
                SavedDuaReflectionsCache.store(userId: uid, duaId: updated.duaId, explanations: explanations)
            }
            onSaved?(updated)
            isPresented = false
        } catch {
            saveError = (error as? LocalizedError)?.errorDescription ?? "Couldn't save changes. Try again."
        }
    }
}

#if canImport(UIKit)

private enum DuaEditUIFont {
    static let regular: UIFont = {
        UIFont(name: "Inter-Regular", size: 16)
            ?? .systemFont(ofSize: 16, weight: .regular)
    }()
}

private final class AutoSizingLockedNamesTextView: UITextView {
    override var intrinsicContentSize: CGSize {
        let width = bounds.width > 0 ? bounds.width : UIScreen.main.bounds.width - 96
        let height = sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude)).height
        return CGSize(width: UIView.noIntrinsicMetric, height: max(120, ceil(height)))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        invalidateIntrinsicContentSize()
    }
}

private struct LockedNamesTextEditor: UIViewRepresentable {
    @Binding var text: String
    let lockedTexts: [String]

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UITextView {
        let textView = AutoSizingLockedNamesTextView()
        textView.delegate = context.coordinator
        textView.backgroundColor = .clear
        textView.textContainerInset = .zero
        textView.textContainer.lineFragmentPadding = 0
        textView.isScrollEnabled = false
        textView.font = DuaEditUIFont.regular
        textView.textColor = UIColor(BespokeColor.bodyText)
        textView.tintColor = UIColor(BespokeColor.forest)
        context.coordinator.apply(text: text, to: textView, preserveSelection: false)
        return textView
    }

    func updateUIView(_ textView: UITextView, context: Context) {
        context.coordinator.parent = self
        if textView.text != text {
            context.coordinator.apply(text: text, to: textView, preserveSelection: false)
        }
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: LockedNamesTextEditor
        private var isApplying = false

        init(parent: LockedNamesTextEditor) {
            self.parent = parent
        }

        func apply(text: String, to textView: UITextView, preserveSelection: Bool) {
            isApplying = true
            defer { isApplying = false }

            let selectedRange = textView.selectedRange
            textView.attributedText = styledText(for: text)

            if preserveSelection {
                let maxLength = (textView.text as NSString?)?.length ?? 0
                let location = min(selectedRange.location, maxLength)
                let length = min(selectedRange.length, max(0, maxLength - location))
                textView.selectedRange = NSRange(location: location, length: length)
            }

            textView.invalidateIntrinsicContentSize()
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isApplying else { return }
            let current = textView.text ?? ""
            guard let snapped = snappedSelection(for: textView.selectedRange, in: current) else { return }
            isApplying = true
            textView.selectedRange = snapped
            isApplying = false
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText: String) -> Bool {
            guard !isApplying else { return true }

            let current = textView.text ?? ""
            for lockedRange in Self.lockedRanges(in: current, lockedTexts: parent.lockedTexts) {
                if NSIntersectionRange(range, lockedRange).length > 0 {
                    return false
                }
            }
            return true
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isApplying else { return }
            parent.text = textView.text ?? ""
            apply(text: parent.text, to: textView, preserveSelection: true)
        }

        private func styledText(for text: String) -> NSAttributedString {
            let attributed = NSMutableAttributedString(
                string: text,
                attributes: [
                    .font: DuaEditUIFont.regular,
                    .foregroundColor: UIColor(BespokeColor.bodyText),
                ]
            )

            for lockedRange in Self.lockedRanges(in: text, lockedTexts: parent.lockedTexts) {
                attributed.addAttribute(
                    .foregroundColor,
                    value: UIColor(BespokeColor.muted),
                    range: lockedRange
                )
            }

            return attributed
        }

        private func snappedSelection(for selection: NSRange, in text: String) -> NSRange? {
            for lockedRange in Self.lockedRanges(in: text, lockedTexts: parent.lockedTexts) {
                if selection.length > 0 {
                    guard NSIntersectionRange(selection, lockedRange).length > 0 else { continue }
                } else {
                    let position = selection.location
                    guard position >= lockedRange.location,
                          position < lockedRange.location + lockedRange.length else { continue }
                }

                return NSRange(location: lockedRange.location + lockedRange.length, length: 0)
            }

            return nil
        }

        private static func lockedRanges(in text: String, lockedTexts: [String]) -> [NSRange] {
            guard !lockedTexts.isEmpty else { return [] }

            let nsText = text as NSString
            var ranges: [NSRange] = []
            var location = 0

            for locked in lockedTexts {
                guard location < nsText.length else { break }
                let searchRange = NSRange(location: location, length: nsText.length - location)
                let found = nsText.range(of: locked, options: [], range: searchRange)
                guard found.location != NSNotFound else { break }
                ranges.append(found)
                location = found.location + found.length
            }

            return ranges
        }
    }
}

#else

private struct LockedNamesTextEditor: View {
    @Binding var text: String
    let lockedTexts: [String]

    var body: some View {
        TextEditor(text: $text)
            .font(BespokeFont.inter(16, weight: .regular))
            .foregroundStyle(BespokeColor.bodyText)
            .frame(minHeight: 120)
    }
}

#endif
