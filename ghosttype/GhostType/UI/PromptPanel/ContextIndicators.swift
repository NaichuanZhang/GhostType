import SwiftUI

/// Shows selected text context indicator.
struct ContextIndicator: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "text.quote")
                .font(.system(size: 10))
            let contextPreview = appState.selectedContext.prefix(50)
            Text("Selected: \(contextPreview)\(appState.selectedContext.count > 50 ? "..." : "")")
                .font(.system(size: 11))
                .lineLimit(1)
            Spacer()
            Button(action: {
                appState.selectedContext = ""
                appState.responseViewTab = .generated
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.secondary)
        .padding(8)
        .background(.quaternary.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

/// Shows attached browser context indicator.
struct BrowserContextIndicator: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "globe")
                .font(.system(size: 10))
                .foregroundStyle(.blue)
            let title = appState.browserContext?.title ?? "Browser page"
            let truncatedTitle = title.count > 40 ? String(title.prefix(40)) + "..." : title
            Text(truncatedTitle)
                .font(.system(size: 11))
                .lineLimit(1)
            Spacer()
            Button(action: {
                appState.clearBrowserContext()
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.secondary)
        .padding(8)
        .background(Color.blue.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

/// Shows screenshot preview indicator.
struct ScreenshotIndicator: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        HStack(spacing: 8) {
            if let nsImage = appState.screenshotImage {
                Image(nsImage: nsImage)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
                    )
            }
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "camera.viewfinder")
                        .font(.system(size: 10))
                    Text("Screenshot captured")
                        .font(.system(size: 11, weight: .medium))
                }
                Text("Sent as visual context with your prompt")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button(action: {
                appState.screenshotBase64 = nil
                appState.screenshotImage = nil
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 10))
            }
            .buttonStyle(.plain)
        }
        .foregroundStyle(.secondary)
        .padding(8)
        .background(.quaternary.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

/// Error banner display.
struct ErrorBanner: View {
    let message: String
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(8)
        .background(.red.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

/// Quick action buttons (Rewrite, Fix Grammar, Shorter, etc.).
struct QuickActions: View {
    @EnvironmentObject var appState: AppState
    let onQuickAction: (String) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                quickActionButton("Rewrite", icon: "arrow.triangle.2.circlepath", prompt: "Rewrite this text to be clearer and more professional")
                quickActionButton("Fix Grammar", icon: "checkmark.circle", prompt: "Fix all grammar and spelling errors")
                quickActionButton("Shorter", icon: "arrow.down.right.and.arrow.up.left", prompt: "Make this text more concise")
                quickActionButton("Expand", icon: "arrow.up.left.and.arrow.down.right", prompt: "Expand on this text with more detail")
                quickActionButton("Friendly", icon: "face.smiling", prompt: "Rewrite in a friendly, casual tone")
                quickActionButton("Professional", icon: "briefcase", prompt: "Rewrite in a formal, professional tone")
            }
        }
    }

    private func quickActionButton(_ title: String, icon: String, prompt: String) -> some View {
        Button(action: { onQuickAction(prompt) }) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(title)
                    .font(.system(size: 11, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.quaternary.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .disabled(appState.selectedContext.isEmpty)
        .opacity(appState.selectedContext.isEmpty ? 0.4 : 1.0)
    }
}
