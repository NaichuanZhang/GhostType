import SwiftUI
import Cocoa
import ApplicationServices

/// The main floating panel view — prompt input + streaming response + action buttons.
struct PromptPanelView: View {
    @EnvironmentObject var appState: AppState
    @FocusState private var isPromptFocused: Bool

    /// Whether the conversation has had at least one completed turn.
    private var hasConversationHistory: Bool {
        !appState.conversationMessages.isEmpty
    }

    var body: some View {
        let _ = NSLog("[GhostType][Body] eval — generating: %@, responseLen: %d, msgCount: %d",
                      appState.isGenerating ? "Y" : "N",
                      appState.responseText.count,
                      appState.conversationMessages.count)
        VStack(spacing: 0) {
            headerBar
            Divider()

            VStack(spacing: 12) {
                // Conversation history (visible after first completed turn)
                if hasConversationHistory {
                    conversationHistory
                }

                promptInput

                if !appState.selectedContext.isEmpty && appState.conversationMessages.isEmpty {
                    contextIndicator
                }

                // Screenshot preview (visible before first generation)
                if appState.screenshotImage != nil && !hasConversationHistory {
                    screenshotIndicator
                }

                // Quick actions (only before any generation, first turn only)
                if appState.responseText.isEmpty && !appState.isGenerating && !hasConversationHistory {
                    quickActions
                }

                // Error display
                if let error = appState.errorMessage {
                    errorBanner(error)
                }

                // Response area
                if appState.isGenerating || !appState.responseText.isEmpty {
                    responseArea
                }

                // Action bar (when response is ready)
                if !appState.responseText.isEmpty && !appState.isGenerating {
                    actionBar
                }
            }
            .padding(16)
        }
        .frame(width: appState.panelWidth)
        .frame(minHeight: 120, maxHeight: 900)
        .background(.clear)
        .onAppear {
            isPromptFocused = true
        }
        .onChange(of: appState.isPromptVisible) { visible in
            if visible {
                // Slight delay so this fires after PanelManager has made the
                // window key — @FocusState requires key window status.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isPromptFocused = true
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .ghostTypeEnterPressed)) { _ in
            // Guard against stale notification arriving after state changed
            guard !appState.responseText.isEmpty, !appState.isGenerating else { return }
            handleEnterKey()
        }
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack {
            Image(systemName: "text.cursor")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Text("GhostType")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            // Backend status indicator
            if appState.backendMode == "agentcore" {
                Circle()
                    .fill(!appState.agentCoreEndpoint.isEmpty ? .blue : .orange)
                    .frame(width: 6, height: 6)
            } else if appState.backendStatus == .running {
                Circle()
                    .fill(.green)
                    .frame(width: 6, height: 6)
            } else {
                Circle()
                    .fill(.orange)
                    .frame(width: 6, height: 6)
            }

            // Mode indicator (after first turn)
            if hasConversationHistory {
                Text(appState.conversationMode == .chat ? "Chat" : "Draft")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            Spacer()

            if appState.isGenerating {
                Button(action: cancelGeneration) {
                    HStack(spacing: 3) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 8))
                        Text("Stop")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            } else {
                // New conversation button (visible after first turn)
                if hasConversationHistory {
                    Button(action: startNewConversation) {
                        HStack(spacing: 3) {
                            Image(systemName: "plus.circle")
                                .font(.system(size: 10))
                            Text("New")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 6)
                }

                Text("Esc to close")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // MARK: - Conversation History

    private var conversationHistory: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(appState.conversationMessages) { message in
                        conversationBubble(message)
                            .id(message.id)
                    }
                }
                .padding(.vertical, 4)
            }
            .frame(maxHeight: 300)
            .fixedSize(horizontal: false, vertical: true)
            .background(.quaternary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .onChange(of: appState.conversationMessages.count) { _ in
                if let last = appState.conversationMessages.last {
                    // No animation — animated scrollTo during rapid view updates
                    // (token streaming) deadlocks SwiftUI's layout engine.
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private func conversationBubble(_ message: ConversationMessage) -> some View {
        HStack(alignment: .top) {
            if message.role == "user" { Spacer(minLength: 40) }

            if message.role == "assistant" {
                AvatarView(size: 20, isAnimating: false)
                    .padding(.top, 2)
            }

            VStack(alignment: message.role == "user" ? .trailing : .leading, spacing: 2) {
                Text(message.content)
                    .font(.system(size: 12))
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
            }

            if message.role == "assistant" { Spacer(minLength: 40) }
        }
        .padding(.horizontal, 8)
    }

    // MARK: - Prompt Input

    private var promptInput: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 14))
                .foregroundStyle(.purple)
                .padding(.top, 2)

            TextField(
                promptPlaceholder,
                text: $appState.promptText,
                axis: .vertical
            )
                .textFieldStyle(.plain)
                .font(.system(size: 14))
                .lineLimit(1...4)
                .focused($isPromptFocused)
                .onSubmit {
                    handleEnterKey()
                }

            // Submit button (visible when there's a prompt or selected context to act on)
            if (!appState.promptText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || !appState.selectedContext.isEmpty)
                && !appState.isGenerating {
                Button(action: submitPrompt) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.purple)
                }
                .buttonStyle(.plain)
                .padding(.top, 0)
            }
        }
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

    // MARK: - Context Indicator

    private var contextIndicator: some View {
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

    // MARK: - Screenshot Indicator

    private var screenshotIndicator: some View {
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

    // MARK: - Error Banner

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(2)
            Spacer()
            Button(action: { appState.errorMessage = nil }) {
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

    // MARK: - Quick Actions

    private var quickActions: some View {
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
        Button(action: {
            appState.promptText = prompt
            submitPrompt()
        }) {
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

    // MARK: - Response Area

    private var responseToggle: some View {
        Picker("", selection: $appState.responseViewTab) {
            Text("Generated").tag(ResponseViewTab.generated)
            Text("Original").tag(ResponseViewTab.original)
        }
        .pickerStyle(.segmented)
        .frame(width: 200)
    }

    private var responseArea: some View {
        VStack(spacing: 8) {
            if !appState.selectedContext.isEmpty && (appState.isGenerating || !appState.responseText.isEmpty) && !hasConversationHistory {
                responseToggle
            }

            HStack(alignment: .top, spacing: 8) {
                AvatarView(size: 28, isAnimating: appState.isGenerating)
                    .padding(.top, 8)

                ScrollView {
                    Group {
                        if appState.responseViewTab == .original && !appState.selectedContext.isEmpty && !hasConversationHistory {
                            Text(appState.selectedContext)
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(12)
                        } else {
                            MarkdownView(text: appState.responseText)
                                .padding(12)
                        }
                    }
                }
                .frame(maxHeight: 600)
                .fixedSize(horizontal: false, vertical: true)
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

    // MARK: - Action Bar

    private var hasContext: Bool {
        !appState.selectedContext.isEmpty
    }

    private var actionBar: some View {
        HStack(spacing: 8) {
            // Insert/Replace — primary action in draft mode, secondary in chat
            if appState.conversationMode == .draft {
                Button(action: insertText) {
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

            Button(action: copyText) {
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

            Button(action: retry) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12))
                    .padding(6)
                    .background(.quaternary.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)

            // Speak / Stop TTS button
            if !appState.minimaxApiKey.isEmpty {
                Button(action: toggleSpeech) {
                    HStack(spacing: 4) {
                        Image(systemName: appState.ttsState == .speaking ? "stop.fill" : "speaker.wave.2")
                            .font(.system(size: 11))
                        Text(appState.ttsState == .speaking ? "Stop" : "Speak")
                            .font(.system(size: 12, weight: .medium))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(.quaternary.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
                .disabled(appState.ttsState == .connecting)
                .opacity(appState.ttsState == .connecting ? 0.5 : 1.0)
            }

            // Insert button for chat mode (optional — for pasting an answer)
            if appState.conversationMode == .chat {
                Button(action: insertText) {
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
                Text(hasContext ? "Enter to replace" : "Enter to insert")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            } else {
                Text("Enter to continue")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Actions

    private func handleEnterKey() {
        NSLog("[GhostType][Enter] handleEnterKey — responseText.isEmpty: %@, isGenerating: %@, mode: %@",
              appState.responseText.isEmpty ? "YES" : "NO",
              appState.isGenerating ? "YES" : "NO",
              appState.conversationMode == .chat ? "chat" : "draft")

        if !appState.responseText.isEmpty && !appState.isGenerating {
            if appState.conversationMode == .chat {
                // Chat mode: Enter starts next turn instead of inserting
                NSLog("[GhostType][Enter] Chat mode — completing turn, focusing prompt")
                completeTurnAndPrepareNext()
            } else {
                // Draft mode: Enter inserts text (existing behavior)
                NSLog("[GhostType][Enter] Draft mode — routing to insertText()")
                insertText()
            }
        } else {
            NSLog("[GhostType][Enter] Routing to submitPrompt()")
            submitPrompt()
        }
    }

    private func submitPrompt() {
        let trimmed = appState.promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasContext = !appState.selectedContext.isEmpty

        NSLog("[GhostType][Submit] submitPrompt — promptLen=%d, hasContext=%@, isGenerating=%@, msgCount=%d, mode=%@",
              trimmed.count,
              hasContext ? "YES" : "NO",
              appState.isGenerating ? "YES" : "NO",
              appState.conversationMessages.count,
              appState.conversationMode == .chat ? "chat" : "draft")

        // Need either a prompt or selected context to proceed
        guard !trimmed.isEmpty || hasContext else {
            NSLog("[GhostType][Submit] BLOCKED — empty prompt and no context")
            return
        }
        guard !appState.isGenerating else {
            NSLog("[GhostType][Submit] BLOCKED — already generating")
            return
        }

        // When there's selected context but no specific prompt, default to rewrite
        let effectivePrompt = trimmed.isEmpty && hasContext
            ? "Rewrite this text to be clearer and more professional"
            : trimmed

        // Determine mode based on prompt content
        let mode = determineMode(prompt: effectivePrompt, hasContext: hasContext)

        // Auto-detect conversation mode type
        let modeType: ConversationMode = (hasContext || ["rewrite", "fix", "translate"].contains(mode)) ? .draft : .chat
        appState.conversationMode = modeType

        // Save user message to conversation history
        appState.appendMessage(role: "user", content: effectivePrompt)

        // Clear prompt and response for new generation
        appState.promptText = ""
        appState.responseText = ""
        appState.isGenerating = true
        appState.errorMessage = nil
        appState.responseViewTab = .generated

        // Start token batching to reduce view updates during streaming
        appState.startTokenBatching()

        let modeTypeStr = modeType == .chat ? "chat" : "draft"
        // Send screenshot only on first turn (most relevant context)
        let screenshot = appState.conversationMessages.count <= 1 ? appState.screenshotBase64 : nil

        // Route generation through selected backend
        if appState.backendMode == "agentcore" && !appState.agentCoreEndpoint.isEmpty {
            NSLog("[GhostType][Submit] Using AgentCore: mode=%@, mode_type=%@, screenshot=%@", mode, modeTypeStr, screenshot != nil ? "YES" : "NO")
            generateWithAgentCore(prompt: effectivePrompt, context: appState.selectedContext, mode: mode, modeType: modeTypeStr, screenshot: screenshot)
        } else if appState.backendStatus == .running {
            NSLog("[GhostType][Submit] Using local backend: mode=%@, mode_type=%@, screenshot=%@", mode, modeTypeStr, screenshot != nil ? "YES" : "NO")
            generateWithBackend(prompt: effectivePrompt, context: appState.selectedContext, mode: mode, modeType: modeTypeStr, screenshot: screenshot)
        } else {
            NSLog("[GhostType][Submit] Backend unavailable, using StubAgent")
            generateWithStub(prompt: effectivePrompt, context: appState.selectedContext)
        }
    }

    /// Determines the generation mode based on prompt content.
    private func determineMode(prompt: String, hasContext: Bool) -> String {
        let lower = prompt.lowercased()

        if lower.contains("fix") || lower.contains("grammar") || lower.contains("spelling") {
            return "fix"
        }
        if lower.contains("translat") {
            return "translate"
        }
        if hasContext && (lower.contains("rewrite") || lower.contains("rephrase") ||
                         lower.contains("shorter") || lower.contains("expand") ||
                         lower.contains("professional") || lower.contains("friendly") ||
                         lower.contains("casual") || lower.contains("formal") ||
                         lower.contains("concise") || lower.contains("tone")) {
            return "rewrite"
        }
        return "generate"
    }

    // MARK: - Multi-Turn Helpers

    /// Saves the current response as an assistant message and prepares the prompt for the next turn.
    /// If the user already typed a follow-up before pressing Enter, it is submitted automatically
    /// so the conversation flows naturally without requiring a second Enter press.
    private func completeTurnAndPrepareNext() {
        NSLog("[GhostType][MultiTurn] completeTurnAndPrepareNext — promptLen=%d, responseLen=%d, msgCount=%d",
              appState.promptText.count, appState.responseText.count, appState.conversationMessages.count)

        if let pendingPrompt = appState.completeTurn() {
            NSLog("[GhostType][MultiTurn] Auto-submitting pending follow-up: '%@'", String(pendingPrompt.prefix(60)))
            // Defer to next run loop tick — completeTurn() just mutated several
            // @Published properties; submitting immediately cascades more state
            // changes during the same view update, which can trigger layout loops.
            DispatchQueue.main.async { [self] in
                appState.promptText = pendingPrompt
                submitPrompt()
            }
        } else {
            isPromptFocused = true
        }
    }

    /// Resets conversation and backend agent state.
    private func startNewConversation() {
        NSLog("[GhostType][NewConversation] Resetting conversation")
        appState.wsClient.sendNewConversation()
        appState.conversationMessages = []
        appState.conversationMode = .draft
        appState.clearCurrentResponse()
        isPromptFocused = true
    }

    // MARK: - Backend Generation

    private func generateWithBackend(prompt: String, context: String, mode: String, modeType: String, screenshot: String? = nil) {
        let wsClient = appState.wsClient

        NSLog("[GhostType][Generate] generateWithBackend — mode=%@, modeType=%@, promptLen=%d, contextLen=%d, hasScreenshot=%@, wsConnected=%@, backendStatus=%@",
              mode, modeType, prompt.count, context.count,
              screenshot != nil ? "YES" : "NO",
              wsClient.isConnected ? "YES" : "NO",
              appState.backendStatus == .running ? "running" : "not-running")

        wsClient.onToken = { [weak appState] token in
            appState?.appendToken(token)
        }

        wsClient.onComplete = { [weak appState] fullResponse in
            appState?.stopTokenBatching()
            let streamedLen = appState?.responseText.count ?? 0
            NSLog("[GhostType][WS] Generation complete, response_len=%d, streamed_len=%d",
                  fullResponse.count, streamedLen)
            // Safety: if no tokens were streamed (e.g. callback handler didn't
            // propagate on agent reuse), use the full response from the done message.
            if appState?.responseText.isEmpty == true && !fullResponse.isEmpty {
                NSLog("[GhostType][WS] No tokens streamed — using full response from done message")
                appState?.responseText = fullResponse
            }
            appState?.isGenerating = false
        }

        wsClient.onError = { [weak appState] error in
            appState?.stopTokenBatching()
            NSLog("[GhostType][WS] Error: %@", error)
            appState?.errorMessage = error
            appState?.isGenerating = false
        }

        wsClient.onCancelled = { [weak appState] in
            appState?.stopTokenBatching()
            NSLog("[GhostType][WS] Cancelled")
            appState?.isGenerating = false
        }

        let config = appState.modelConfigForRequest()
        wsClient.generate(prompt: prompt, context: context, mode: mode, modeType: modeType, config: config, screenshot: screenshot)
    }

    // MARK: - AgentCore Generation

    private func generateWithAgentCore(prompt: String, context: String, mode: String, modeType: String, screenshot: String? = nil) {
        let client = appState.agentCoreClient

        NSLog("[GhostType][AgentCore] generateWithAgentCore — mode=%@, modeType=%@, promptLen=%d, contextLen=%d",
              mode, modeType, prompt.count, context.count)

        client.onComplete = { [weak appState] fullResponse in
            guard let appState = appState else { return }
            appState.stopTokenBatching()
            NSLog("[GhostType][AgentCore] Generation complete, response_len=%d", fullResponse.count)

            // Simulate streaming: reveal the response word-by-word for typing animation feel
            let words = fullResponse.split(separator: " ", omittingEmptySubsequences: false)
            if words.isEmpty {
                appState.responseText = fullResponse
                appState.isGenerating = false
                return
            }

            var wordIndex = 0
            Timer.scheduledTimer(withTimeInterval: 0.015, repeats: true) { timer in
                guard wordIndex < words.count else {
                    timer.invalidate()
                    // Ensure final text matches exactly
                    appState.responseText = fullResponse
                    appState.isGenerating = false
                    return
                }

                if wordIndex == 0 {
                    appState.responseText = String(words[wordIndex])
                } else {
                    appState.responseText += " " + String(words[wordIndex])
                }
                wordIndex += 1
            }
        }

        client.onError = { [weak appState] error in
            appState?.stopTokenBatching()
            NSLog("[GhostType][AgentCore] Error: %@", error)
            appState?.errorMessage = error
            appState?.isGenerating = false
        }

        let config = appState.modelConfigForRequest()
        client.generate(
            endpoint: appState.agentCoreEndpoint,
            prompt: prompt,
            context: context,
            mode: mode,
            modeType: modeType,
            config: config,
            screenshot: screenshot
        )
    }

    // MARK: - Stub Fallback

    private func generateWithStub(prompt: String, context: String) {
        StubAgent.generate(prompt: prompt, context: context) { [weak appState] token in
            DispatchQueue.main.async {
                appState?.appendToken(token)
            }
        } completion: { [weak appState] in
            DispatchQueue.main.async {
                appState?.stopTokenBatching()
                appState?.isGenerating = false
            }
        }
    }

    // MARK: - Cancel

    private func cancelGeneration() {
        NSLog("[GhostType][Cancel] Cancelling generation — responseLen=%d, msgCount=%d, backend=%@",
              appState.responseText.count, appState.conversationMessages.count, appState.backendMode)
        appState.stopTokenBatching()
        if appState.backendMode == "agentcore" {
            appState.agentCoreClient.cancel()
        } else {
            appState.wsClient.cancelGeneration()
        }
        appState.isGenerating = false
    }

    // MARK: - Text Insertion

    private func insertText() {
        let text = appState.responseText
        let targetElement = appState.targetElement
        let hadSelectedContext = !appState.selectedContext.isEmpty
        let savedRange = appState.selectedTextRange
        guard !text.isEmpty else {
            NSLog("[GhostType][Insert] insertText called but responseText is empty, aborting")
            return
        }

        NSLog("[GhostType][Insert] insertText called — text length: %d, savedElement: %@, replace: %@",
              text.count, targetElement != nil ? "yes" : "nil",
              hadSelectedContext ? "yes" : "no")

        // Dismiss panel first — this deactivates GhostType and returns
        // focus to the previous app, which is required for AX text insertion
        dismissPanel()

        if hadSelectedContext, let range = savedRange {
            NSLog("[GhostType][Insert] Panel dismissed, starting replacement (range: %d+%d)",
                  range.location, range.length)
            attemptReplacement(text: text, targetElement: targetElement, range: range, attempt: 1)
        } else {
            NSLog("[GhostType][Insert] Panel dismissed, starting insertion")
            attemptInsertion(text: text, targetElement: targetElement, attempt: 1)
        }
    }

    private func attemptInsertion(text: String, targetElement: AXUIElement?, attempt: Int) {
        // Web-based apps (Chrome, VSCode, Brave, etc.): AX returns success but
        // silently drops text. Skip retries and paste directly after a brief
        // delay for the target app to regain focus.
        if let bid = appState.targetBundleID, Self.isWebBasedApp(bid) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
                NSLog("[GhostType][Insert] Web app (%@), using simulatePaste", bid)
                AccessibilityEngine.simulatePaste(text)
            }
            return
        }

        let delays: [Double] = [0.15, 0.30, 0.50]
        guard attempt <= delays.count else {
            NSLog("[GhostType][Insert] AX exhausted after %d attempts. Trying direct paste.", delays.count)
            AccessibilityEngine.simulatePaste(text)
            return
        }

        let delay = delays[attempt - 1]
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [self] in
            do {
                // Strategy 1: AX insert into saved element (works for native apps like Notes/TextEdit)
                if let element = targetElement {
                    do {
                        try AccessibilityEngine.insertText(text, into: element)
                        NSLog("[GhostType][Insert] Success on attempt %d (delay: %.2fs) via saved element", attempt, delay)
                        return
                    } catch {
                        NSLog("[GhostType][Insert] Saved element AX failed, trying system-wide (attempt %d)", attempt)
                    }
                }
                // Strategy 2: System-wide query → AX insert or simulatePaste fallback
                // (handles Chrome/Electron once the app has regained focus)
                try AccessibilityEngine.insertText(text)
                NSLog("[GhostType][Insert] Success on attempt %d (delay: %.2fs) via system query", attempt, delay)
            } catch {
                NSLog("[GhostType][Insert] Attempt %d failed (delay: %.2fs): %@",
                      attempt, delay, error.localizedDescription)
                self.attemptInsertion(text: text, targetElement: targetElement, attempt: attempt + 1)
            }
        }
    }

    /// Attempts to replace the originally-selected text by restoring the saved selection range
    /// then setting the selected text. Falls back to simulatePaste.
    private func attemptReplacement(text: String, targetElement: AXUIElement?, range: CFRange, attempt: Int) {
        // Web-based apps: AX range restore doesn't work; paste directly
        if let bid = appState.targetBundleID, Self.isWebBasedApp(bid) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
                NSLog("[GhostType][Replace] Web app (%@), using simulatePaste", bid)
                AccessibilityEngine.simulatePaste(text)
            }
            return
        }

        let delays: [Double] = [0.15, 0.30, 0.50]
        guard attempt <= delays.count else {
            NSLog("[GhostType][Replace] All attempts exhausted, falling back to simulatePaste")
            AccessibilityEngine.simulatePaste(text)
            return
        }

        let delay = delays[attempt - 1]
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [self] in
            if let element = targetElement,
               AccessibilityEngine.replaceTextInRange(range, with: text, on: element) {
                NSLog("[GhostType][Replace] Success on attempt %d (delay: %.2fs)", attempt, delay)
                return
            }
            NSLog("[GhostType][Replace] Attempt %d failed (delay: %.2fs)", attempt, delay)
            self.attemptReplacement(text: text, targetElement: targetElement, range: range, attempt: attempt + 1)
        }
    }

    /// Returns true for apps where AX text insertion silently fails (Chrome, Electron, etc.).
    static func isWebBasedApp(_ bundleID: String) -> Bool {
        bundleID.hasPrefix("com.google.Chrome") ||
        bundleID.hasPrefix("com.microsoft.VSCode") ||
        bundleID.hasPrefix("com.brave.Browser") ||
        bundleID.hasPrefix("com.operasoftware.Opera") ||
        bundleID.hasPrefix("com.tinyspeck.slackmacgap") ||
        bundleID.hasPrefix("com.hnc.Discord") ||
        bundleID.hasPrefix("com.microsoft.teams") ||
        bundleID.hasPrefix("notion.id") ||
        bundleID.hasPrefix("com.figma.Desktop") ||
        bundleID.hasPrefix("com.linear") ||
        bundleID.contains(".electron.")
    }

    private func copyText() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(appState.responseText, forType: .string)
    }

    private func retry() {
        appState.ttsClient.stop()
        appState.responseText = ""
        appState.errorMessage = nil
        submitPrompt()
    }

    private func toggleSpeech() {
        if appState.ttsState == .speaking {
            appState.ttsClient.stop()
        } else {
            appState.ttsClient.voiceId = appState.ttsVoiceId
            appState.ttsClient.speed = appState.ttsSpeed
            appState.ttsClient.speak(appState.responseText, apiKey: appState.minimaxApiKey)
        }
    }

    private func dismissPanel() {
        appState.isPromptVisible = false
        appState.clearConversation()
        NotificationCenter.default.post(name: .ghostTypeDismissPanel, object: nil)
    }
}

extension Notification.Name {
    static let ghostTypeDismissPanel = Notification.Name("ghostTypeDismissPanel")
    static let ghostTypeEnterPressed = Notification.Name("ghostTypeEnterPressed")
}
