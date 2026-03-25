import SwiftUI

/// Action buttons shown when a response is ready (Insert, Copy, Retry, etc.).
struct ActionBar: View {
    @EnvironmentObject var appState: AppState
    let onInsert: () -> Void
    let onCopy: () -> Void
    let onRetry: () -> Void

    private var hasContext: Bool {
        !appState.selectedContext.isEmpty
    }

    var body: some View {
        HStack(spacing: 8) {
            // Insert/Replace — primary action in draft mode
            if appState.conversationMode == .draft {
                Button(action: onInsert) {
                    HStack(spacing: 4) {
                        Image(systemName: hasContext ? "arrow.triangle.2.circlepath" : "text.insert")
                            .font(.system(size: 11))
                        Text(hasContext ? "Replace" : "Insert")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.purple)
                    .foregroundColor(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }

            Button(action: onCopy) {
                HStack(spacing: 4) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 11))
                    Text("Copy")
                        .font(.system(size: 12, weight: .medium))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(appState.conversationMode == .chat ? AnyShapeStyle(.purple) : AnyShapeStyle(.quaternary.opacity(0.5)))
                .foregroundColor(appState.conversationMode == .chat ? .white : .primary)
                .clipShape(RoundedRectangle(cornerRadius: 6))
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
