import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Multiline dua input. Height stays capped, overflow scrolls inside the box,
/// and the placeholder uses the same inset as the caret.
struct BespokePlaceholderTextEditor: View {
    @Binding var text: String
    var placeholder: String
    var minHeight: CGFloat = 120
    var maxHeight: CGFloat = 200
    var isEditable: Bool = true
    var focus: FocusState<Bool>.Binding

    var body: some View {
        BespokeDuaTextView(
            text: $text,
            placeholder: placeholder,
            minHeight: minHeight,
            maxHeight: maxHeight,
            isEditable: isEditable,
            isFocused: focus
        )
        .frame(height: minHeight)
        .opacity(isEditable ? 1 : 0.55)
        .allowsHitTesting(isEditable)
        .accessibilityLabel(placeholder)
    }
}

#if canImport(UIKit)
private struct BespokeDuaTextView: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var minHeight: CGFloat
    var maxHeight: CGFloat
    var isEditable: Bool
    var isFocused: FocusState<Bool>.Binding

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> DuaTextView {
        let view = DuaTextView()
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.textColor = UIColor(red: 51 / 255, green: 51 / 255, blue: 51 / 255, alpha: 1)
        view.tintColor = UIColor(red: 200 / 255, green: 155 / 255, blue: 60 / 255, alpha: 1)
        view.font = UIFont(name: "Inter-Regular", size: 16) ?? .systemFont(ofSize: 16)
        view.textContainerInset = UIEdgeInsets(top: 8, left: 4, bottom: 8, right: 4)
        view.textContainer.lineFragmentPadding = 0
        view.isScrollEnabled = true
        view.alwaysBounceVertical = false
        view.showsVerticalScrollIndicator = true
        view.keyboardDismissMode = .none
        view.returnKeyType = .default
        view.autocorrectionType = .yes
        view.autocapitalizationType = .sentences
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        context.coordinator.placeholderLabel.text = placeholder
        view.placeholderLabel = context.coordinator.placeholderLabel
        view.addSubview(context.coordinator.placeholderLabel)
        return view
    }

    func updateUIView(_ uiView: DuaTextView, context: Context) {
        context.coordinator.parent = self
        // Writing text back into a live field resigns first responder and closes the keyboard.
        if !uiView.isFirstResponder, uiView.text != text {
            uiView.text = text
            context.coordinator.placeholderLabel.isHidden = text.isEmpty == false
        }
        if uiView.isEditable != isEditable {
            uiView.isEditable = isEditable
            uiView.isSelectable = isEditable
        }
        context.coordinator.placeholderLabel.text = placeholder
        context.coordinator.layoutPlaceholder(in: uiView)
    }

    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        var parent: BespokeDuaTextView
        let placeholderLabel = UILabel()
        private weak var textView: UITextView?
        private var outsideTap: UITapGestureRecognizer?

        init(parent: BespokeDuaTextView) {
            self.parent = parent
            placeholderLabel.font = UIFont(name: "Inter-Regular", size: 16) ?? .systemFont(ofSize: 16)
            placeholderLabel.textColor = UIColor(red: 136 / 255, green: 136 / 255, blue: 136 / 255, alpha: 1)
            placeholderLabel.numberOfLines = 0
        }

        func layoutPlaceholder(in textView: UITextView) {
            let inset = textView.textContainerInset
            let width = max(0, textView.bounds.width - inset.left - inset.right)
            let size = placeholderLabel.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
            placeholderLabel.frame = CGRect(
                x: inset.left,
                y: inset.top,
                width: width,
                height: size.height
            )
        }

        func textViewDidChange(_ textView: UITextView) {
            placeholderLabel.isHidden = !textView.text.isEmpty
            let updated = textView.text ?? ""
            // Updating SwiftUI during this callback ends editing and closes the keyboard.
            DispatchQueue.main.async { [weak self] in
                guard let self, self.parent.text != updated else { return }
                self.parent.text = updated
            }
        }

        func textViewDidBeginEditing(_ textView: UITextView) {
            self.textView = textView
            parent.isFocused.wrappedValue = true
            DispatchQueue.main.async { [weak self] in
                guard let self, textView.isFirstResponder else { return }
                self.installOutsideTap(on: textView)
            }
        }

        func textViewDidEndEditing(_ textView: UITextView) {
            removeOutsideTap()
            parent.isFocused.wrappedValue = false
        }

        func installOutsideTap(on textView: UITextView) {
            guard outsideTap == nil, let window = textView.window else { return }
            let tap = UITapGestureRecognizer(target: self, action: #selector(outsideTapped(_:)))
            tap.cancelsTouchesInView = false
            tap.delegate = self
            window.addGestureRecognizer(tap)
            outsideTap = tap
        }

        func removeOutsideTap() {
            if let outsideTap {
                outsideTap.view?.removeGestureRecognizer(outsideTap)
            }
            outsideTap = nil
        }

        @objc func outsideTapped(_ recognizer: UITapGestureRecognizer) {
            parent.isFocused.wrappedValue = false
            textView?.resignFirstResponder()
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let textView, let window = textView.window else { return false }
            // Keyboard taps are not "outside the field". Treating them as such closes the keyboard after one letter.
            if touch.window !== window { return false }
            let windowPoint = touch.location(in: window)
            let fieldFrame = textView.convert(textView.bounds, to: window).insetBy(dx: -12, dy: -12)
            if fieldFrame.contains(windowPoint) { return false }
            if window.bounds.height - windowPoint.y < 360 { return false }
            return true
        }
    }
}

private final class DuaTextView: UITextView {
    weak var placeholderLabel: UILabel?

    override func layoutSubviews() {
        super.layoutSubviews()
        guard let placeholderLabel else { return }
        let inset = textContainerInset
        let width = max(0, bounds.width - inset.left - inset.right)
        let size = placeholderLabel.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        placeholderLabel.frame = CGRect(x: inset.left, y: inset.top, width: width, height: size.height)
    }

    /// Keep vertical drags in this box once the text is taller than the field,
    /// so the page behind it does not steal the scroll.
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer === panGestureRecognizer {
            return contentSize.height > bounds.height + 1
        }
        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }
}
#endif
