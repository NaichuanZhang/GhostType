import SwiftUI

/// Read-only view of a saved session's messages.
struct SessionDetailView: View {
    @EnvironmentObject var appState: AppState
    let session: Session
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            detailHeader
            Divider()
            sessionMetadata
            Divider()
            messageList
        }
    }

    // MARK: - Header

    private var detailHeader: some View {
        HStack {
            Button(action: onBack) {
                HStack(spacing: 3) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .medium))
                    Text("Back")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)

            Spacer()

            Text(session.title)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
                .foregroundStyle(.primary)

            Spacer()

            // Invisible spacer to center the title
            HStack(spacing: 3) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 10))
                Text("Back")
                    .font(.system(size: 10))
            }
            .hidden()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    // MARK: - Metadata

    private var sessionMetadata: some View {
        HStack(spacing: 8) {
            Label(formattedDate(session.createdAt), systemImage: "calendar")
            Label(session.mode, systemImage: session.mode == "chat" ? "bubble.left.and.bubble.right" : "doc.text")
            if let agentId = session.agentId {
                Label(agentId, systemImage: "person.circle")
            }
        }
        .font(.system(size: 9))
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    // MARK: - Messages

    private var messageList: some View {
        ScrollView {
            LazyVStack(spacing: 8) {
                ForEach(session.messages, id: \.id) { message in
                    messageBubble(message)
                }
            }
            .padding(.vertical, 8)
        }
    }

    private func messageBubble(_ message: SessionMessage) -> some View {
        HStack(alignment: .top) {
            if message.role == "user" { Spacer(minLength: 20) }

            VStack(alignment: message.role == "user" ? .trailing : .leading, spacing: 4) {
                // Context snippet (for user messages with context)
                if let context = message.context, !context.isEmpty {
                    HStack(spacing: 4) {
                        Image(systemName: "text.quote")
                            .font(.system(size: 8))
                        Text(context.prefix(100) + (context.count > 100 ? "..." : ""))
                            .font(.system(size: 9))
                            .lineLimit(2)
                    }
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(.quaternary.opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                // Screenshot thumbnail
                if let filename = message.screenshotFilename {
                    screenshotThumbnail(filename: filename)
                }

                // Message content bubble
                Text(message.content)
                    .font(.system(size: 11))
                    .foregroundStyle(message.role == "user" ? .white : .primary)
                    .textSelection(.enabled)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(
                        message.role == "user"
                            ? AnyShapeStyle(.purple.opacity(0.8))
                            : AnyShapeStyle(.quaternary.opacity(0.5))
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .contextMenu {
                        Button(action: { copyToClipboard(message.content) }) {
                            Label("Copy", systemImage: "doc.on.doc")
                        }
                    }
            }

            if message.role == "assistant" { Spacer(minLength: 20) }
        }
        .padding(.horizontal, 8)
    }

    // MARK: - Screenshot Thumbnail

    private func screenshotThumbnail(filename: String) -> some View {
        Group {
            let url = appState.sessionStore.screenshotURL(filename: filename)
            if let data = try? Data(contentsOf: url),
               let nsImage = NSImage(data: data) {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 180, maxHeight: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(.quaternary, lineWidth: 1)
                    )
            }
        }
    }

    // MARK: - Helpers

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }

    private func copyToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
