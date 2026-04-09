import SwiftUI

/// Action buttons shown when a response is ready (Insert, Copy, Retry, etc.).
struct ActionBar: View {
    @EnvironmentObject var appState: AppState
    let onInsert: () -> Void
    let onCopy: () -> Void
    let onRetry: () -> Void

    @State private var showCopyFeedback = false
    @State private var showInsertFeedback = false

    private var hasContext: Bool {
        !appState.selectedContext.isEmpty
    }

    var body: some View {
        HStack(spacing: 8) {
            // Insert/Replace — primary action in draft mode
            if appState.conversationMode == .draft {
                Button(action: {
                    showInsertFeedback = true
                    onInsert()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                        showInsertFeedback = false
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: showInsertFeedback ? "checkmark" : (hasContext ? "arrow.triangle.2.circlepath" : "text.insert"))
                            .font(.system(size: 11))
                        Text(showInsertFeedback ? "Done" : (hasContext ? "Replace" : "Insert"))
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(showInsertFeedback ? .green : .purple)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .animation(.easeInOut(duration: 0.15), value: showInsertFeedback)
                }
                .buttonStyle(.plain)
            }

            Button(action: {
                showCopyFeedback = true
                onCopy()
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    showCopyFeedback = false
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: showCopyFeedback ? "checkmark" : "doc.on.doc")
                        .font(.system(size: 11))
                    Text(showCopyFeedback ? "Copied" : "Copy")
                        .font(.system(size: 12, weight: .medium))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(showCopyFeedback ? AnyShapeStyle(.green) : (appState.conversationMode == .chat ? AnyShapeStyle(.purple) : AnyShapeStyle(.quaternary.opacity(0.5))))
                .foregroundColor(showCopyFeedback || appState.conversationMode == .chat ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 6))
                .animation(.easeInOut(duration: 0.15), value: showCopyFeedback)
            }
            .buttonStyle(.plain)

            Button(action: onRetry) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12))
                    .padding(6)
                    .background(.quaternary.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)

            // Insert button for chat mode (optional — for pasting an answer)
            if appState.conversationMode == .chat {
                Button(action: onInsert) {
                    HStack(spacing: 4) {
                        Image(systemName: "text.insert")
                            .font(.system(size: 11))
                        Text("Insert")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.quaternary.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }

            Spacer()

            if appState.conversationMode == .draft {
                Text(hasContext ? "Enter to replace \u{00B7} \u{2318}Enter to send" : "Enter to insert \u{00B7} \u{2318}Enter to send")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            } else {
                Text("Enter to continue \u{00B7} \u{2318}Enter to send")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
    }
}
