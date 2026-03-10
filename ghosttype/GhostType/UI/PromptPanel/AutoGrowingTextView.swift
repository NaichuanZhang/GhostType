import SwiftUI
import Cocoa

/// A self-sizing `NSTextView` wrapped for SwiftUI. Grows vertically as text is
/// entered and reports its intrinsic content height via a binding — no hidden
/// measurement view or `PreferenceKey` needed.
///
/// The text view is embedded in an `NSScrollView` with a hidden vertical
/// scroller so word-wrap works correctly, but no scrollbar is ever visible.
struct AutoGrowingTextView: NSViewRepresentable {
    @Binding var text: String
    @Binding var intrinsicHeight: CGFloat
    var font: NSFont
    var maxHeight: CGFloat
    var isFocused: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeNSView(context: Context) -> NSScrollView {
        let textView = NSTextView()
        textView.delegate = context.coordinator
        textView.font = font
        textView.drawsBackground = false
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        // Track the scroll view's clip view width — without this the text view
        // starts at zero width and text glyphs are invisible (cursor still renders
        // because it's a zero-width line).
        textView.autoresizingMask = [.width]
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.textContainerInset = NSSize(width: 0, height: 4)

        if let textContainer = textView.textContainer {
            textContainer.lineFragmentPadding = 0
            textContainer.widthTracksTextView = true
        }

        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = false
        scrollView.documentView = textView

        context.coordinator.textView = textView

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }

        // Sync text from SwiftUI → NSTextView only when different (avoids cursor jump)
        if textView.string != text {
            textView.string = text
            // Move cursor to end — external changes (like Shift+Enter newline)
            // should place the insertion point after the new content
            let endPos = textView.string.count
            textView.setSelectedRange(NSRange(location: endPos, length: 0))
        }

        // Resolve text color from the view's effective appearance.
        // .labelColor can't be used because it resolves against the wrong
        // appearance context across the NSHostingView boundary inside
        // NSVisualEffectView, producing text that matches the background.
        let isDark = textView.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let color: NSColor = isDark ? .white : .black
        textView.textColor = color
        textView.insertionPointColor = color
        textView.typingAttributes[.foregroundColor] = color

        if textView.font != font {
            textView.font = font
        }

        context.coordinator.parent = self
        context.coordinator.recalculateHeight()

        // Focus management
        if isFocused, let window = scrollView.window, window.firstResponder !== textView {
            window.makeFirstResponder(textView)
        }
    }

    // MARK: - Coordinator

    final class Coordinator: NSObject, NSTextViewDelegate {
        var parent: AutoGrowingTextView
        weak var textView: NSTextView?

        init(_ parent: AutoGrowingTextView) {
            self.parent = parent
        }

        func textDidChange(_ notification: Notification) {
            guard let textView = notification.object as? NSTextView else { return }
            parent.text = textView.string
            recalculateHeight()
        }

        func recalculateHeight() {
            guard let textView,
                  let layoutManager = textView.layoutManager,
                  let textContainer = textView.textContainer else { return }

            layoutManager.ensureLayout(for: textContainer)
            let usedRect = layoutManager.usedRect(for: textContainer)
            let inset = textView.textContainerInset
            let newHeight = usedRect.height + inset.height * 2

            if abs(newHeight - parent.intrinsicHeight) > 0.5 {
                DispatchQueue.main.async { [parent] in
                    parent.intrinsicHeight = newHeight
                }
            }
        }
    }
}
