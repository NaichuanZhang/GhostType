import SwiftUI
import Cocoa
import ApplicationServices

/// The main floating panel view — orchestrates sub-views and routes actions.
struct PromptPanelView: View {
    @EnvironmentObject var appState: AppState
    @FocusState private var isPromptFocused: Bool
    @State private var showHistorySidebar = false
    @State private var showMentionPopup = false
    @State private var tabMonitor: Any?
    @State private var intrinsicTextHeight: CGFloat = 36

    /// Whether the conversation has had at least one completed turn.
    private var hasConversationHistory: Bool {
        !appState.conversationMessages.isEmpty
    }

    var body: some View {
        let _ = NSLog("[GhostType][Body] eval — generating: %@, responseLen: %d, msgCount: %d",
                      appState.isGenerating ? "Y" : "N",
                      appState.responseText.count,
                      appState.conversationMessages.count)
        HStack(spacing: 0) {
            // History sidebar (expands panel when visible)
            if showHistorySidebar {
                HistorySidebarView(onContinueSession: {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showHistorySidebar = false
                    }
                    isPromptFocused = true
                })
                    .frame(width: 260)
                    .transition(.move(edge: .leading))
                Divider()
            }

            // Main prompt content
            VStack(spacing: 0) {
                HeaderBar(
                    showHistorySidebar: $showHistorySidebar,
                    onCancel: cancelGeneration,
                    onNewConversation: startNewConversation
                )
                Divider()

                // Scrollable content area
                ScrollView {
                    VStack(spacing: 12) {
                        if hasConversationHistory {
                            ConversationView()
                        }
                        if appState.isGenerating || !appState.responseText.isEmpty {
                            ResponseArea()
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                }
                .frame(maxHeight: .infinity)

                Divider()

                // Pinned bottom input area
                VStack(spacing: 8) {
                    if !appState.selectedContext.isEmpty && appState.conversationMessages.isEmpty {
                        ContextIndicator()
                    }

                    if appState.isBrowserContextAttached {
                        BrowserContextIndicator()
                    }

                    if appState.screenshotImage != nil && !hasConversationHistory {
                        ScreenshotIndicator()
                    }

                    if let error = appState.errorMessage {
                        ErrorBanner(message: error, onDismiss: { appState.errorMessage = nil })
                    }

                    PromptInputBar(
                        isPromptFocused: $isPromptFocused,
                        intrinsicTextHeight: $intrinsicTextHeight,
                        showMentionPopup: $showMentionPopup,
                        onSubmit: submitPrompt,
                        onAcceptMention: acceptMentionSuggestion
                    )

                    if appState.responseText.isEmpty && !appState.isGenerating && !hasConversationHistory {
                        QuickActions(onQuickAction: { prompt in
                            appState.promptText = prompt
                            submitPrompt()
                        })
                    }

                    if !appState.responseText.isEmpty && !appState.isGenerating {
                        ActionBar(
                            onInsert: insertText,
                            onCopy: copyText,
                            onRetry: retry
                        )
                    }
                }
                .padding(16)
            }
            .frame(minWidth: appState.panelWidth, maxWidth: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.clear)
        .animation(.easeInOut(duration: 0.2), value: showHistorySidebar)
        .onAppear {
            isPromptFocused = true
            tabMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.keyCode == 48, self.showMentionPopup {
                    self.acceptMentionSuggestion()
                    return nil
                }
                return event
            }
        }
        .onDisappear {
            if let monitor = tabMonitor {
                NSEvent.removeMonitor(monitor)
                tabMonitor = nil
            }
        }
        .onChange(of: appState.isPromptVisible) { visible in
            if visible {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    isPromptFocused = true
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .ghostTypeEnterPressed)) { _ in
            guard !appState.responseText.isEmpty, !appState.isGenerating else { return }
            handleEnterKey()
        }
        .onReceive(NotificationCenter.default.publisher(for: .ghostTypeSubmitPressed)) { _ in
            if appState.isGenerating {
                appState.pendingSubmit = true
                NSLog("[GhostType][Submit] Cmd+Enter during generation — queued pending submit")
            } else {
                archiveCurrentResponseIfNeeded()
                submitPrompt()
            }
        }
        .onReceive(appState.$isGenerating.dropFirst()) { isGenerating in
            if !isGenerating && appState.pendingSubmit {
                appState.pendingSubmit = false
                NSLog("[GhostType][Submit] Generation complete — firing pending submit")
                archiveCurrentResponseIfNeeded()
                submitPrompt()
            }
        }
    }

    // MARK: - @Mention

    private func acceptMentionSuggestion() {
        if appState.promptText.hasSuffix("@") {
            appState.promptText = String(appState.promptText.dropLast())
        }
        showMentionPopup = false
        appState.fetchBrowserContext()
    }

    // MARK: - Actions

    private func handleEnterKey() {
        NSLog("[GhostType][Enter] handleEnterKey — responseText.isEmpty: %@, isGenerating: %@, mode: %@",
              appState.responseText.isEmpty ? "YES" : "NO",
              appState.isGenerating ? "YES" : "NO",
              appState.conversationMode == .chat ? "chat" : "draft")

        if !appState.responseText.isEmpty && !appState.isGenerating {
            if appState.conversationMode == .chat {
                NSLog("[GhostType][Enter] Chat mode — completing turn, focusing prompt")
                completeTurnAndPrepareNext()
            } else {
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

        guard !trimmed.isEmpty || hasContext else {
            NSLog("[GhostType][Submit] BLOCKED — empty prompt and no context")
            return
        }
        guard !appState.isGenerating else {
            NSLog("[GhostType][Submit] BLOCKED — already generating")
            return
        }

        let effectivePrompt = trimmed.isEmpty && hasContext
            ? "Rewrite this text to be clearer and more professional"
            : trimmed

        let mode = Self.determineMode(prompt: effectivePrompt, hasContext: hasContext)
        let modeType: ConversationMode = (hasContext || ["rewrite", "fix", "translate"].contains(mode)) ? .draft : .chat
        appState.conversationMode = modeType

        appState.appendMessage(role: "user", content: effectivePrompt)

        appState.promptText = ""
        appState.responseText = ""
        appState.isGenerating = true
        appState.errorMessage = nil
        appState.responseViewTab = .generated
        appState.activeToolCalls = []
        appState.isToolCallsExpanded = false

        appState.startTokenBatching()

        let modeTypeStr = modeType == .chat ? "chat" : "draft"
        let screenshot = appState.conversationMessages.count <= 1 ? appState.screenshotBase64 : nil
        let agentId = appState.effectiveAgentId()

        // Browser context text for subprocess
        let browserCtxText = appState.isBrowserContextAttached ? appState.browserContext?.content : nil

        NSLog("[GhostType][Submit] Generating: mode=%@, mode_type=%@, screenshot=%@, agent=%@, browserCtx=%@",
              mode, modeTypeStr, screenshot != nil ? "YES" : "NO", agentId ?? "default",
              appState.isBrowserContextAttached ? "YES" : "NO")

        // Use subprocess (primary) or WebSocket (fallback) or StubAgent (no backend)
        if appState.subprocess.isRunning || !appState.wsClient.backendAvailable {
            // Primary: subprocess path
            appState.generationService.generate(
                prompt: effectivePrompt,
                context: appState.selectedContext,
                mode: mode,
                modeType: modeTypeStr,
                config: appState.modelConfigForRequest(),
                screenshot: screenshot,
                agent: agentId,
                browserContext: browserCtxText,
                appState: appState
            )
        } else if appState.backendStatus == .running {
            // Legacy fallback: WebSocket
            generateWithBackend(prompt: effectivePrompt, context: appState.selectedContext, mode: mode, modeType: modeTypeStr, screenshot: screenshot, agent: agentId, includeBrowserContext: appState.isBrowserContextAttached)
        } else {
            NSLog("[GhostType][Submit] Backend unavailable, using StubAgent")
            generateWithStub(prompt: effectivePrompt, context: appState.selectedContext)
        }
    }

    /// Determines the generation mode based on prompt content.
    static func determineMode(prompt: String, hasContext: Bool) -> String {
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

    private func archiveCurrentResponseIfNeeded() {
        guard !appState.responseText.isEmpty, !appState.isGenerating else { return }
        NSLog("[GhostType][MultiTurn] Archiving unarchived response (len=%d) before new submit",
              appState.responseText.count)
        appState.appendMessage(role: "assistant", content: appState.responseText)
        appState.responseText = ""
    }

    private func completeTurnAndPrepareNext() {
        NSLog("[GhostType][MultiTurn] completeTurnAndPrepareNext — promptLen=%d, responseLen=%d, msgCount=%d",
              appState.promptText.count, appState.responseText.count, appState.conversationMessages.count)

        if let pendingPrompt = appState.completeTurn() {
            NSLog("[GhostType][MultiTurn] Auto-submitting pending follow-up: '%@'", String(pendingPrompt.prefix(60)))
            DispatchQueue.main.async { [self] in
                appState.promptText = pendingPrompt
                submitPrompt()
            }
        } else {
            isPromptFocused = true
        }
    }

    private func startNewConversation() {
        NSLog("[GhostType][NewConversation] Resetting conversation")
        appState.generationService.newConversation()
        appState.wsClient.sendNewConversation()  // Legacy fallback
        appState.clearConversation()
        isPromptFocused = true
    }

    // MARK: - Backend Generation

    private func generateWithBackend(prompt: String, context: String, mode: String, modeType: String, screenshot: String? = nil, agent: String? = nil, includeBrowserContext: Bool = false) {
        let wsClient = appState.wsClient

        wsClient.onToken = { [weak appState] token in
            appState?.appendToken(token)
        }

        wsClient.onComplete = { [weak appState] fullResponse in
            appState?.stopTokenBatching()
            appState?.completeAllToolCalls()
            let streamedLen = appState?.responseText.count ?? 0
            NSLog("[GhostType][WS] Generation complete, response_len=%d, streamed_len=%d",
                  fullResponse.count, streamedLen)
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
            appState?.completeAllToolCalls()
            NSLog("[GhostType][WS] Cancelled")
            appState?.isGenerating = false
        }

        wsClient.onToolEvent = { [weak appState] eventType, toolName, toolId, toolInput in
            switch eventType {
            case "tool_start":
                appState?.handleToolStart(name: toolName, id: toolId)
            case "tool_done":
                appState?.handleToolDone(name: toolName, id: toolId, input: toolInput)
            default:
                break
            }
        }

        let config = appState.modelConfigForRequest()
        wsClient.generate(prompt: prompt, context: context, mode: mode, modeType: modeType, config: config, screenshot: screenshot, agent: agent, includeBrowserContext: includeBrowserContext)
    }

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
        NSLog("[GhostType][Cancel] Cancelling generation — responseLen=%d, msgCount=%d",
              appState.responseText.count, appState.conversationMessages.count)
        appState.stopTokenBatching()
        appState.generationService.cancel()
        appState.wsClient.cancelGeneration()  // Legacy fallback
        appState.isGenerating = false
    }

    // MARK: - Text Insertion

    private func insertText() {
        let text = appState.responseText
        let targetElement = appState.targetElement
        let hadSelectedContext = !appState.selectedContext.isEmpty
        let savedRange = appState.selectedTextRange

        TextInsertionService.insert(
            text: text,
            targetElement: targetElement,
            targetBundleID: appState.targetBundleID,
            selectedTextRange: savedRange,
            hasSelectedContext: hadSelectedContext,
            dismissPanel: dismissPanel
        )
    }

    private func copyText() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(appState.responseText, forType: .string)
    }

    private func retry() {
        appState.responseText = ""
        appState.errorMessage = nil
        submitPrompt()
    }

    private func dismissPanel() {
        appState.isPromptVisible = false
        appState.clearConversation()
        NotificationCenter.default.post(name: .ghostTypeDismissPanel, object: nil)
    }

    // MARK: - Web App Detection (kept as static for PanelManager compatibility)

    static func isWebBasedApp(_ bundleID: String) -> Bool {
        TextInsertionService.isWebBasedApp(bundleID)
    }
}

extension Notification.Name {
    static let ghostTypeDismissPanel = Notification.Name("ghostTypeDismissPanel")
    static let ghostTypeEnterPressed = Notification.Name("ghostTypeEnterPressed")
    static let ghostTypeSubmitPressed = Notification.Name("ghostTypeSubmitPressed")
}
