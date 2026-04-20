import SwiftUI

/// The prompt text input area with auto-growing text view, placeholder, and submit button.
struct PromptInputBar: View {
    @EnvironmentObject var appState: AppState
    @FocusState.Binding var isPromptFocused: Bool
    @Binding var intrinsicTextHeight: CGFloat
    @Binding var showMentionPopup: Bool
    let onSubmit: () -> Void
    let onAcceptMention: () -> Void

    private var hasConversationHistory: Bool {
        !appState.conversationMessages.isEmpty
    }

    private var promptEditorHeight: CGFloat {
        let minH: CGFloat = 36
        let maxH: CGFloat = 200
        return min(max(intrinsicTextHeight, minH), maxH)
    }

    private var promptPlaceholder: String {
        if hasConversationHistory {
            return appState.conversationMode == .chat
                ? "Ask a follow-up..."
                : "Refine the draft..."
        }
        return appState.selectedContext.isEmpty
            ? "What do you want to write?"
            : "How should this be rewritten? (Enter for default)"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 14))
                .foregroundStyle(.purple)
                .padding(.top, 8)

            ZStack(alignment: .topLeading) {
                if appState.promptText.isEmpty {
                    Text(promptPlaceholder)
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 4)
                        .allowsHitTesting(false)
                }

                AutoGrowingTextView(
                    text: $appState.promptText,
                    intrinsicHeight: $intrinsicTextHeight,
                    font: .systemFont(ofSize: 14),
                    maxHeight: 200,
                    isFocused: isPromptFocused
                )
                .frame(height: promptEditorHeight)
            }
            .animation(.easeInOut(duration: 0.15), value: promptEditorHeight)

            // Submit button
            if (!appState.promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !appState.selectedContext.isEmpty)
                && !appState.isGenerating {
                Button(action: onSubmit) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.purple)
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
            }
        }
        .overlay(alignment: .topLeading) {
            if showMentionPopup {
                MentionPopup(onAccept: onAcceptMention)
                    .offset(y: -36)
            }
        }
        .onChange(of: appState.promptText) { newValue in
            showMentionPopup = newValue.hasSuffix("@")
        }
    }
}

// MARK: - Mention Popup

struct MentionPopup: View {
    let onAccept: () -> Void

    var body: some View {
        Button(action: onAccept) {
            HStack(spacing: 6) {
                Image(systemName: "globe")
                    .font(.system(size: 12))
                    .foregroundStyle(.blue)
                Text("@browser")
                    .font(.system(size: 12, weight: .medium))
                Text("— active Chrome tab")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.ultraThickMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .shadow(color: .black.opacity(0.15), radius: 4, y: 2)
        }
        .buttonStyle(.plain)
    }
}
