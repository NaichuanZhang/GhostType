import SwiftUI

/// Displays archived conversation turns (user + assistant messages).
struct ConversationView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        LazyVStack(spacing: 8) {
            ForEach(appState.conversationMessages) { message in
                ConversationBubble(message: message)
                    .id(message.id)
            }
        }
        .padding(.vertical, 4)
        .background(.quaternary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct ConversationBubble: View {
    let message: ConversationMessage

    var body: some View {
        HStack(alignment: .top) {
            if message.role == "user" { Spacer(minLength: 40) }

            VStack(alignment: message.role == "user" ? .trailing : .leading, spacing: 2) {
                if message.role == "assistant" {
                    MarkdownView(text: message.content, isStreaming: false)
                        .font(.system(size: 12))
                        .textSelection(.enabled)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(AnyShapeStyle(.quaternary.opacity(0.5)))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                        .transaction { $0.animation = nil }
                } else {
                    Text(message.content)
                        .font(.system(size: 12))
                        .foregroundStyle(.white)
                        .textSelection(.enabled)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(AnyShapeStyle(.purple.opacity(0.8)))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
            }

            if message.role == "assistant" { Spacer(minLength: 40) }
        }
        .padding(.horizontal, 8)
    }
}
