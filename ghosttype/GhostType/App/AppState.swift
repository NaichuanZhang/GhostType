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

    /// Dynamic panel width — set to 70% of the active app's window width when the panel opens.
    @Published var panelWidth: CGFloat = 420

    /// The AXUIElement that was focused when the panel opened (not @Published — no UI binding needed).
    var targetElement: AXUIElement?

    /// Bundle identifier of the frontmost app when the panel opened (e.g. "com.google.Chrome").
    var targetBundleID: String?

    /// The text selection range (location + length) saved when the panel opened.
    /// Used to restore selection for text replacement after a rewrite.
    var selectedTextRange: CFRange?

    /// Base64-encoded JPEG screenshot of the frontmost app's window, captured when the panel opened.
    /// Sent to the backend as visual context for the agent.
    var screenshotBase64: String?

    /// NSImage of the captured screenshot for UI thumbnail preview.
    @Published var screenshotImage: NSImage?

    /// WebSocket client for backend communication.
    let wsClient = WebSocketClient()

    /// HTTP client for AgentCore backend communication.
    let agentCoreClient = AgentCoreClient()

    /// Text-to-Speech client for MiniMax T2A API.
    let ttsClient = TTSClient()

    private var cancellables = Set<AnyCancellable>()

    // Token batching: buffer tokens and flush periodically to reduce view updates during streaming.
    private var tokenBuffer = ""
    private var tokenFlushTimer: Timer?

    // MARK: - Settings (persisted in UserDefaults)

    /// Backend mode: "local" for WebSocket to localhost:8420, "agentcore" for HTTP to AgentCore endpoint.
    @Published var backendMode: String = UserDefaults.standard.string(forKey: "backendMode") ?? "local"

    /// AgentCore endpoint URL (HTTP URL or ARN).
    @Published var agentCoreEndpoint: String = UserDefaults.standard.string(forKey: "agentCoreEndpoint") ?? ""

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
                } else if self?.backendStatus == .running {
                    self?.backendStatus = .stopped
                }
            }
            .store(in: &cancellables)

        ttsClient.$state
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newState in self?.ttsState = newState }
            .store(in: &cancellables)
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

    func saveSettings() {
        UserDefaults.standard.set(backendMode, forKey: "backendMode")
        UserDefaults.standard.set(agentCoreEndpoint, forKey: "agentCoreEndpoint")
        UserDefaults.standard.set(modelId, forKey: "modelId")
        UserDefaults.standard.set(awsProfile, forKey: "awsProfile")
        UserDefaults.standard.set(awsRegion, forKey: "awsRegion")
        UserDefaults.standard.set(minimaxApiKey, forKey: "minimaxApiKey")
        UserDefaults.standard.set(ttsVoiceId, forKey: "ttsVoiceId")
        UserDefaults.standard.set(ttsSpeed, forKey: "ttsSpeed")
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

    /// Full conversation reset — clears history, mode, and response state.
    func clearConversation() {
        conversationMessages = []
        conversationMode = .draft
        clearResponse()
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
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
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
}
