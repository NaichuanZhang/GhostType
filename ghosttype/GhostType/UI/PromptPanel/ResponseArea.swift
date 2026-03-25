import SwiftUI

/// Displays the current streaming response with tool calls and original/generated toggle.
struct ResponseArea: View {
    @EnvironmentObject var appState: AppState

    private var hasConversationHistory: Bool {
        !appState.conversationMessages.isEmpty
    }

    var body: some View {
        VStack(spacing: 8) {
            if !appState.selectedContext.isEmpty && (appState.isGenerating || !appState.responseText.isEmpty) && !hasConversationHistory {
                responseToggle
            }

            // Tool call chips
            if !appState.activeToolCalls.isEmpty {
                ToolCallsView(
                    toolCalls: appState.activeToolCalls,
                    isExpanded: $appState.isToolCallsExpanded
                )
            }

            HStack(alignment: .top, spacing: 8) {
                Group {
                    if appState.responseViewTab == .original && !appState.selectedContext.isEmpty && !hasConversationHistory {
                        Text(appState.selectedContext)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                    } else {
                        MarkdownView(text: appState.responseText, isStreaming: appState.isGenerating)
                            .padding(12)
                    }
                }
                .background(.quaternary.opacity(0.2))
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(alignment: .bottomTrailing) {
                    if appState.isGenerating && appState.responseViewTab == .generated {
                        ProgressView()
                            .scaleEffect(0.6)
                            .padding(8)
                    }
                }
            }
        }
    }

    private var responseToggle: some View {
        Picker("", selection: $appState.responseViewTab) {
            Text("Generated").tag(ResponseViewTab.generated)
            Text("Original").tag(ResponseViewTab.original)
        }
        .pickerStyle(.segmented)
        .frame(width: 200)
    }
}
