import Cocoa
import Combine
import ApplicationServices

enum BackendStatus: Equatable {
    case stopped
    case running
    case error(String)
}

enum ResponseViewTab {
    case original
    case generated
}

enum ConversationMode {
    case draft    // Iterative writing, paste-ready output
    case chat     // Conversational Q&A
}

// MARK: - Tool Call Models

enum ToolStatus: Equatable {
    case running
    case completed
}

struct ToolCallInfo: Identifiable, Equatable {
    let id: String
    let name: String
    var status: ToolStatus
    let startTime: Date
    var toolInput: String?

    init(id: String, name: String, status: ToolStatus = .running, startTime: Date = Date(), toolInput: String? = nil) {
        self.id = id
        self.name = name
        self.status = status
        self.startTime = startTime
        self.toolInput = toolInput
    }

    /// Human-readable display name computed from the raw tool name.
    var displayName: String {
        Self.displayName(for: name)
    }

    /// Returns a new copy with updated status (immutable pattern).
    func withStatus(_ newStatus: ToolStatus) -> ToolCallInfo {
        ToolCallInfo(id: id, name: name, status: newStatus, startTime: startTime, toolInput: toolInput)
    }

    /// Returns a new copy with tool input set (immutable pattern).
    func withInput(_ input: String?) -> ToolCallInfo {
        ToolCallInfo(id: id, name: name, status: status, startTime: startTime, toolInput: input)
    }

    // MARK: - Display Name Mapping

    private static let knownNames: [String: String] = [
        "rewrite_text": "Rewriting text",
        "fix_grammar": "Fixing grammar",
        "translate_text": "Translating",
        "count_words": "Counting words",
        "extract_key_points": "Extracting key points",
        "change_tone": "Changing tone",
        "save_memory": "Saving to memory",
        "recall_memories": "Recalling memories",
        "forget_memory": "Forgetting memory",
    ]

    static func displayName(for toolName: String) -> String {
        if let known = knownNames[toolName] {
            return known
        }
        // Fallback: title-case with underscores replaced by spaces
        return toolName
            .split(separator: "_")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }
}

struct ConversationMessage: Identifiable {
    let id = UUID()
    let role: String        // "user" or "assistant"
    let content: String
    let timestamp = Date()
}

/// Loads default settings from ~/.config/ghosttype/default.json.
/// UserDefaults values take priority; these are only used when no saved value exists.
private struct DefaultConfig {
    let modelId: String
    let awsProfile: String
    let awsRegion: String
    let minimaxApiKey: String
    let ttsVoiceId: String
    let ttsSpeed: Double

    static let shared = DefaultConfig.load()

    private static func load() -> DefaultConfig {
        let path = NSString("~/.config/ghosttype/default.json").expandingTildeInPath
        let url = URL(fileURLWithPath: path)

        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            NSLog("[GhostType][Config] No default.json found at %@, using built-in defaults", path)
            return DefaultConfig(
                modelId: "global.anthropic.claude-opus-4-6-v1",
                awsProfile: "",
                awsRegion: "us-west-2",
                minimaxApiKey: "",
                ttsVoiceId: "English_Graceful_Lady",
                ttsSpeed: 1.0
            )
        }

        NSLog("[GhostType][Config] Loaded default.json from %@", path)
        return DefaultConfig(
            modelId: json["modelId"] as? String ?? "global.anthropic.claude-opus-4-6-v1",
            awsProfile: json["awsProfile"] as? String ?? "",
            awsRegion: json["awsRegion"] as? String ?? "us-west-2",
            minimaxApiKey: json["minimaxApiKey"] as? String ?? "",
            ttsVoiceId: json["ttsVoiceId"] as? String ?? "English_Graceful_Lady",
            ttsSpeed: json["ttsSpeed"] as? Double ?? 1.0
        )
    }
}

class AppState: ObservableObject {
    @Published var isPromptVisible = false
    @Published var promptText = ""
    @Published var responseText = ""
    @Published var isGenerating = false
    @Published var selectedContext = ""
    @Published var accessibilityGranted = false
    @Published var backendStatus: BackendStatus = .stopped
    @Published var errorMessage: String?
    @Published var responseViewTab: ResponseViewTab = .generated
    @Published var conversationMessages: [ConversationMessage] = []
    @Published var conversationMode: ConversationMode = .draft

    // MARK: - Tool Call Tracking
    @Published var activeToolCalls: [ToolCallInfo] = []
    @Published var isToolCallsExpanded: Bool = false

    // MARK: - Session History
    var sessionStore = SessionStore()
    @Published var sessionHistory: [Session] = []

    // MARK: - Browser Context (@browser mention)
    @Published var browserContext: BrowserContextService.BrowserContextData?
    @Published var isBrowserContextAttached: Bool = false

    // MARK: - Agent Selection
    @Published var availableAgents: [AgentInfo] = []
    @Published var selectedAgentId: String?
    var defaultAgentId: String?

    /// Fixed panel width for the GPT-style chat layout.
    let panelWidth: CGFloat = 480

    /// The AXUIElement that was focused when the panel opened (not @Published — no UI binding needed).
    var targetElement: AXUIElement?

    /// Bundle identifier of the frontmost app when the panel opened (e.g. "com.google.Chrome").
    var targetBundleID: String?

    /// The text selection range (location + length) saved when the panel opened.
    /// Used to restore selection for text replacement after a rewrite.
    var selectedTextRange: CFRange?

    /// Timestamp when the panel was last dismissed. Used with `sessionResumeTimeout`
    /// to decide whether to restore the previous session on re-invoke.
    var lastPanelDismissTime: Date?

    /// How long (in seconds) after dismiss the previous session can be resumed.
    static let sessionResumeTimeout: TimeInterval = 120

    /// Base64-encoded JPEG screenshot of the frontmost app's window, captured when the panel opened.
    /// Sent to the backend as visual context for the agent.
    var screenshotBase64: String?

    /// NSImage of the captured screenshot for UI thumbnail preview.
    @Published var screenshotImage: NSImage?

    /// WebSocket client for backend communication.
    let wsClient = WebSocketClient()

    /// Text-to-Speech client for MiniMax T2A API.
    let ttsClient = TTSClient()

    private var cancellables = Set<AnyCancellable>()

    // Token batching: buffer tokens and flush periodically to reduce view updates during streaming.
    private var tokenBuffer = ""
    private var tokenFlushTimer: Timer?

    // MARK: - Settings (persisted in UserDefaults)

    /// Whether to show the avatar WKWebView panel on the left side of the prompt.
    @Published var showAvatarPanel: Bool = UserDefaults.standard.object(forKey: "showAvatarPanel") as? Bool ?? true

    /// Fixed width of the avatar panel.
    let avatarPanelWidth: CGFloat = 300

    /// URL loaded in the avatar WKWebView.
    @Published var avatarURL: String = UserDefaults.standard.string(forKey: "avatarURL") ?? "https://aloe-cherry-29999215.figma.site"

    @Published var modelId: String = UserDefaults.standard.string(forKey: "modelId") ?? DefaultConfig.shared.modelId

    // AWS credentials (Bedrock)
    @Published var awsProfile: String = UserDefaults.standard.string(forKey: "awsProfile") ?? DefaultConfig.shared.awsProfile
    @Published var awsRegion: String = UserDefaults.standard.string(forKey: "awsRegion") ?? DefaultConfig.shared.awsRegion

    // TTS settings (MiniMax)
    @Published var minimaxApiKey: String = UserDefaults.standard.string(forKey: "minimaxApiKey") ?? DefaultConfig.shared.minimaxApiKey
    @Published var ttsVoiceId: String = UserDefaults.standard.string(forKey: "ttsVoiceId") ?? DefaultConfig.shared.ttsVoiceId
    @Published var ttsSpeed: Double = UserDefaults.standard.double(forKey: "ttsSpeed") == 0 ? DefaultConfig.shared.ttsSpeed : UserDefaults.standard.double(forKey: "ttsSpeed")
    @Published var ttsState: TTSState = .idle

    init() {
        // Sync backend availability → backendStatus
        wsClient.$backendAvailable
            .receive(on: DispatchQueue.main)
            .sink { [weak self] available in
                if available {
                    self?.backendStatus = .running
                    // Fetch agents when backend comes online (or comes back)
                    if self?.availableAgents.isEmpty == true {
                        self?.refreshAgents()
                    }
                } else if self?.backendStatus == .running {
                    self?.backendStatus = .stopped
                }
            }
            .store(in: &cancellables)

        ttsClient.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newState in self?.ttsState = newState }
            .store(in: &cancellables)

        loadSessionHistory()
    }

    /// Returns the config dict to send with each generate request.
    func modelConfigForRequest() -> [String: String] {
        var config: [String: String] = [
            "provider": "bedrock",
            "model_id": modelId,
        ]

        if !awsProfile.isEmpty { config["aws_profile"] = awsProfile }
        if !awsRegion.isEmpty { config["aws_region"] = awsRegion }

        return config
    }

    /// Resolves the effective agent ID: explicit selection > auto-detect from bundle > default.
    func effectiveAgentId() -> String? {
        if let selected = selectedAgentId {
            return selected
        }
        if let detected = AgentInfo.agentForBundle(targetBundleID, from: availableAgents) {
            return detected.id
        }
        return defaultAgentId
    }

    /// Fetches available agents from the backend and populates the agent list.
    func refreshAgents() {
        AgentService.fetchAgents { [weak self] agents, defaultId in
            self?.availableAgents = agents
            self?.defaultAgentId = defaultId
        }
    }

    func saveSettings() {
        UserDefaults.standard.set(showAvatarPanel, forKey: "showAvatarPanel")
        UserDefaults.standard.set(avatarURL, forKey: "avatarURL")
        UserDefaults.standard.set(modelId, forKey: "modelId")
        UserDefaults.standard.set(awsProfile, forKey: "awsProfile")
        UserDefaults.standard.set(awsRegion, forKey: "awsRegion")
        UserDefaults.standard.set(minimaxApiKey, forKey: "minimaxApiKey")
        UserDefaults.standard.set(ttsVoiceId, forKey: "ttsVoiceId")
        UserDefaults.standard.set(ttsSpeed, forKey: "ttsSpeed")
    }

    /// Fetches browser context from the backend and attaches it.
    func fetchBrowserContext() {
        BrowserContextService.fetchBrowserContext { [weak self] data in
            self?.browserContext = data
            self?.isBrowserContextAttached = data != nil
        }
    }

    /// Clears attached browser context.
    func clearBrowserContext() {
        browserContext = nil
        isBrowserContextAttached = false
    }

    func clearResponse() {
        ttsClient.stop()
        promptText = ""
        responseText = ""
        selectedContext = ""
        isGenerating = false
        errorMessage = nil
        responseViewTab = .generated
        screenshotBase64 = nil
        screenshotImage = nil
        activeToolCalls = []
        isToolCallsExpanded = false
        clearBrowserContext()
    }

    /// Clears current response but keeps conversation history (for multi-turn).
    func clearCurrentResponse() {
        promptText = ""
        responseText = ""
        isGenerating = false
        errorMessage = nil
        responseViewTab = .generated
    }

    /// Appends a message to the conversation history.
    func appendMessage(role: String, content: String) {
        conversationMessages.append(ConversationMessage(role: role, content: content))
    }

    /// Completes the current turn: archives assistant response, clears I/O state,
    /// returns any follow-up the user typed (before clearing blanks it), or nil.
    func completeTurn() -> String? {
        let pending = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !responseText.isEmpty {
            appendMessage(role: "assistant", content: responseText)
        }
        clearCurrentResponse()
        return pending.isEmpty ? nil : pending
    }

    /// Full conversation reset — auto-saves session before clearing.
    func clearConversation() {
        saveCurrentSession()
        conversationMessages = []
        conversationMode = .draft
        clearResponse()
    }

    // MARK: - Session Resume

    /// Returns true when the previous session should be restored (dismissed recently + has messages).
    func shouldResumeSession(now: Date = Date()) -> Bool {
        guard let dismissTime = lastPanelDismissTime else { return false }
        guard !conversationMessages.isEmpty else { return false }
        return now.timeIntervalSince(dismissTime) < Self.sessionResumeTimeout
    }

    /// Records the current time as the panel dismiss timestamp.
    func recordPanelDismiss(at date: Date = Date()) {
        lastPanelDismissTime = date
    }

    /// Clears screenshot state only, preserving conversation and all other state.
    func refreshScreenshot() {
        screenshotBase64 = nil
        screenshotImage = nil
    }

    // MARK: - Session Persistence

    /// Builds a Session from the current conversation state.
    /// Returns nil if fewer than 2 messages (need at least 1 user + 1 assistant).
    func buildSessionFromConversation(messages: [ConversationMessage]? = nil) -> Session? {
        let msgs = messages ?? conversationMessages
        guard msgs.count >= 2 else { return nil }

        let firstUserContent = msgs.first(where: { $0.role == "user" })?.content ?? ""
        let title = Session.generateTitle(from: firstUserContent)
        let now = Date()

        let sessionMessages = msgs.enumerated().map { index, msg in
            SessionMessage(
                id: msg.id.uuidString,
                role: msg.role,
                content: msg.content,
                timestamp: msg.timestamp,
                context: index == 0 ? (selectedContext.isEmpty ? nil : selectedContext) : nil,
                screenshotFilename: nil
            )
        }

        return Session(
            id: UUID().uuidString,
            title: title,
            createdAt: msgs.first?.timestamp ?? now,
            updatedAt: msgs.last?.timestamp ?? now,
            mode: conversationMode == .chat ? "chat" : "draft",
            agentId: effectiveAgentId(),
            modelId: modelId,
            messages: sessionMessages
        )
    }

    /// Saves the current conversation as a session (if it has enough messages).
    /// Also saves any attached screenshot.
    func saveCurrentSession() {
        // Build messages for saving without mutating conversationMessages
        var messagesForSave = conversationMessages
        if !responseText.isEmpty {
            messagesForSave.append(ConversationMessage(role: "assistant", content: responseText))
        }
        guard var session = buildSessionFromConversation(messages: messagesForSave) else { return }

        // Save screenshot if present
        if let base64 = screenshotBase64, let data = Data(base64Encoded: base64) {
            let filename = "\(session.id)_0.jpg"
            do {
                try sessionStore.saveScreenshot(data: data, filename: filename)
                // Update the first user message with the screenshot filename
                var updatedMessages = session.messages
                if !updatedMessages.isEmpty {
                    let first = updatedMessages[0]
                    updatedMessages[0] = SessionMessage(
                        id: first.id,
                        role: first.role,
                        content: first.content,
                        timestamp: first.timestamp,
                        context: first.context,
                        screenshotFilename: filename
                    )
                }
                session = Session(
                    id: session.id,
                    title: session.title,
                    createdAt: session.createdAt,
                    updatedAt: session.updatedAt,
                    mode: session.mode,
                    agentId: session.agentId,
                    modelId: session.modelId,
                    messages: updatedMessages
                )
            } catch {
                NSLog("[GhostType][AppState] Failed to save screenshot: %@", error.localizedDescription)
            }
        }

        do {
            try sessionStore.saveSession(session)
            NSLog("[GhostType][AppState] Saved session %@ (%d messages)", session.id, session.messages.count)
            loadSessionHistory()
        } catch {
            NSLog("[GhostType][AppState] Failed to save session: %@", error.localizedDescription)
        }
    }

    /// Loads a saved session into the active chat for continuation.
    /// Saves any existing conversation first, then populates the UI
    /// with the session's messages and syncs history to the backend.
    func restoreSession(_ session: Session) {
        guard !session.messages.isEmpty else { return }

        // Save current conversation before replacing
        clearConversation()

        // Set mode from session
        conversationMode = session.mode == "chat" ? .chat : .draft

        // Set agent from session
        selectedAgentId = session.agentId

        // Convert session messages to conversation messages.
        // All messages except the last assistant go into conversationMessages.
        // The last assistant message goes into responseText so the UI renders it
        // as the current (most recent) response.
        let allMessages = session.messages
        let lastAssistantIndex = allMessages.lastIndex(where: { $0.role == "assistant" })

        for (index, msg) in allMessages.enumerated() {
            if index == lastAssistantIndex {
                responseText = msg.content
            } else {
                conversationMessages.append(
                    ConversationMessage(role: msg.role, content: msg.content)
                )
            }
        }

        // Sync history to backend agent
        let simplifiedMessages = allMessages.map { ["role": $0.role, "content": $0.content] }
        wsClient.sendRestoreHistory(
            messages: simplifiedMessages,
            config: modelConfigForRequest(),
            modeType: session.mode == "chat" ? "chat" : "draft",
            agent: session.agentId
        )

        NSLog("[GhostType][AppState] Restored session %@ (%d messages)", session.id, session.messages.count)
    }

    /// Populates sessionHistory from disk.
    func loadSessionHistory() {
        sessionHistory = sessionStore.loadSessions()
    }

    /// Deletes a session by ID and refreshes the list.
    func deleteSession(id: String) {
        do {
            try sessionStore.deleteSession(id: id)
        } catch {
            NSLog("[GhostType][AppState] Failed to delete session %@: %@", id, error.localizedDescription)
        }
        loadSessionHistory()
    }

    // MARK: - Token Batching

    /// Start batching tokens for smoother UI updates during streaming.
    /// Timer runs in RunLoop.common mode so it fires even during scroll tracking
    /// (the run loop switches to .tracking mode during scroll gestures, which would
    /// starve a .default-mode timer and freeze the UI).
    func startTokenBatching() {
        NSLog("[GhostType][TokenBatch] Started")
        tokenBuffer = ""
        tokenFlushTimer?.invalidate()
        let timer = Timer(timeInterval: 0.15, repeats: true) { [weak self] _ in
            self?.flushTokenBuffer()
        }
        RunLoop.main.add(timer, forMode: .common)
        tokenFlushTimer = timer
    }

    /// Stop batching and flush any remaining buffered tokens.
    func stopTokenBatching() {
        tokenFlushTimer?.invalidate()
        tokenFlushTimer = nil
        flushTokenBuffer()
        NSLog("[GhostType][TokenBatch] Stopped, responseText length: %d", responseText.count)
    }

    /// Buffer a single token (called from onToken callback on main thread).
    func appendToken(_ token: String) {
        tokenBuffer += token
    }

    /// Flush buffered tokens to responseText in a single @Published update.
    private func flushTokenBuffer() {
        guard !tokenBuffer.isEmpty else { return }
        let flushed = tokenBuffer
        tokenBuffer = ""
        responseText += flushed
    }

    // MARK: - Tool Call Handling

    /// Called when a tool invocation starts.
    func handleToolStart(name: String, id: String) {
        let info = ToolCallInfo(id: id, name: name)
        activeToolCalls = activeToolCalls + [info]
    }

    /// Called when a tool invocation completes.
    func handleToolDone(name: String, id: String, input: String?) {
        activeToolCalls = activeToolCalls.map { call in
            guard call.id == id else { return call }
            return call.withStatus(.completed).withInput(input)
        }
    }

    /// Mark all remaining running tools as completed (e.g. on generation finish).
    func completeAllToolCalls() {
        activeToolCalls = activeToolCalls.map { call in
            call.status == .running ? call.withStatus(.completed) : call
        }
    }
}
