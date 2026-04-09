import Cocoa
import Combine
import ApplicationServices

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

    var displayName: String {
        Self.displayName(for: name)
    }

    func withStatus(_ newStatus: ToolStatus) -> ToolCallInfo {
        ToolCallInfo(id: id, name: name, status: newStatus, startTime: startTime, toolInput: toolInput)
    }

    func withInput(_ input: String?) -> ToolCallInfo {
        ToolCallInfo(id: id, name: name, status: status, startTime: startTime, toolInput: input)
    }

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
private struct DefaultConfig {
    let modelId: String
    let awsProfile: String
    let awsRegion: String
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
                awsRegion: "us-west-2"
            )
        }

        NSLog("[GhostType][Config] Loaded default.json from %@", path)
        return DefaultConfig(
            modelId: json["modelId"] as? String ?? "global.anthropic.claude-opus-4-6-v1",
            awsProfile: json["awsProfile"] as? String ?? "",
            awsRegion: json["awsRegion"] as? String ?? "us-west-2"
        )
    }
}

// MARK: - AppState

class AppState: ObservableObject {
    // Action triggers (incremented by PanelManager, observed by PromptPanelView)
    @Published var enterAction: UInt = 0
    @Published var submitAction: UInt = 0
    @Published var dismissAction: UInt = 0

    // UI state
    @Published var isPromptVisible = false
    @Published var promptText = ""
    @Published var responseText = ""
    @Published var isGenerating = false
    @Published var selectedContext = ""
    @Published var accessibilityGranted = false
    @Published var errorMessage: String?
    @Published var responseViewTab: ResponseViewTab = .generated
    @Published var pendingSubmit = false

    // Conversation
    @Published var conversationMessages: [ConversationMessage] = []
    @Published var conversationMode: ConversationMode = .draft

    // Tool calls
    @Published var activeToolCalls: [ToolCallInfo] = []
    @Published var isToolCallsExpanded: Bool = false

    // Sessions
    var sessionStore = SessionStore()
    @Published var sessionHistory: [Session] = []

    // Browser context
    @Published var browserContext: BrowserContextService.BrowserContextData?
    @Published var isBrowserContextAttached: Bool = false

    // Agents
    @Published var availableAgents: [AgentInfo] = []
    @Published var selectedAgentId: String?
    var defaultAgentId: String?

    // Panel
    let panelWidth: CGFloat = 480

    // Target app context
    var targetElement: AXUIElement?
    var targetBundleID: String?
    var selectedTextRange: CFRange?

    // Session resume
    var lastPanelDismissTime: Date?
    static let sessionResumeTimeout: TimeInterval = 120

    // Screenshot
    var screenshotBase64: String?
    @Published var screenshotImage: NSImage?

    // Backend
    let subprocess = SubprocessManager()
    lazy var generationService = GenerationService(subprocess: subprocess)

    // Token batching (internal, used by AppState+Generation)
    internal var tokenBuffer = ""
    internal var tokenFlushTimer: Timer?

    // Settings (persisted in UserDefaults)
    @Published var modelId: String = UserDefaults.standard.string(forKey: "modelId") ?? DefaultConfig.shared.modelId
    @Published var awsProfile: String = UserDefaults.standard.string(forKey: "awsProfile") ?? DefaultConfig.shared.awsProfile
    @Published var awsRegion: String = UserDefaults.standard.string(forKey: "awsRegion") ?? DefaultConfig.shared.awsRegion

    init() {
        loadSessionHistory()
    }

    // MARK: - Config

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
        UserDefaults.standard.set(modelId, forKey: "modelId")
        UserDefaults.standard.set(awsProfile, forKey: "awsProfile")
        UserDefaults.standard.set(awsRegion, forKey: "awsRegion")
    }

    // MARK: - Agents

    func effectiveAgentId() -> String? {
        if let selected = selectedAgentId { return selected }
        if let detected = AgentInfo.agentForBundle(targetBundleID, from: availableAgents) {
            return detected.id
        }
        return defaultAgentId
    }

    func refreshAgents() {
        generationService.fetchAgents { [weak self] agents, defaultId in
            self?.availableAgents = agents
            self?.defaultAgentId = defaultId
        }
    }

    // MARK: - Browser Context

    func fetchBrowserContext() {
        generationService.fetchBrowserContext { [weak self] data in
            self?.browserContext = data
            self?.isBrowserContextAttached = data != nil
        }
    }

    func clearBrowserContext() {
        browserContext = nil
        isBrowserContextAttached = false
    }

    // MARK: - State Reset

    func clearResponse() {
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

    func clearCurrentResponse() {
        promptText = ""
        responseText = ""
        isGenerating = false
        errorMessage = nil
        responseViewTab = .generated
    }

    func clearConversation() {
        saveCurrentSession()
        conversationMessages = []
        conversationMode = .draft
        clearResponse()
    }

    func refreshScreenshot() {
        screenshotBase64 = nil
        screenshotImage = nil
    }

    // MARK: - Conversation

    func appendMessage(role: String, content: String) {
        conversationMessages.append(ConversationMessage(role: role, content: content))
    }

    func completeTurn() -> String? {
        let pending = promptText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !responseText.isEmpty {
            appendMessage(role: "assistant", content: responseText)
        }
        clearCurrentResponse()
        return pending.isEmpty ? nil : pending
    }
}
