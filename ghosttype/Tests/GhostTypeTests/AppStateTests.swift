import Testing
import Foundation
@testable import GhostTypeLib

private func makeAppState() -> AppState {
    AppState()
}

/// Creates an AppState backed by a temp SessionStore for test isolation.
private func makeAppStateWithTempStore() -> (AppState, URL) {
    let base = FileManager.default.temporaryDirectory
        .appendingPathComponent("ghosttype-appstate-\(UUID().uuidString)")
    let state = AppState()
    state.sessionStore = SessionStore(baseDirectory: base)
    return (state, base)
}

private func cleanup(_ url: URL) {
    try? FileManager.default.removeItem(at: url)
}

// MARK: - clearCurrentResponse

@Test func clearCurrentResponseBlanksPromptAndResponse() {
    let state = makeAppState()
    state.promptText = "hello"
    state.responseText = "world"
    state.isGenerating = true
    state.errorMessage = "oops"

    state.clearCurrentResponse()

    #expect(state.promptText == "")
    #expect(state.responseText == "")
    #expect(state.isGenerating == false)
    #expect(state.errorMessage == nil)
}

@Test func clearCurrentResponsePreservesConversationHistory() {
    let state = makeAppState()
    state.appendMessage(role: "user", content: "question")
    state.appendMessage(role: "assistant", content: "answer")
    state.promptText = "follow-up"
    state.responseText = "new answer"

    state.clearCurrentResponse()

    #expect(state.conversationMessages.count == 2)
    #expect(state.conversationMessages[0].role == "user")
    #expect(state.conversationMessages[1].role == "assistant")
}

// MARK: - clearResponse vs clearCurrentResponse

@Test func clearResponseAlsoBlanksSelectedContext() {
    let state = makeAppState()
    state.promptText = "p"
    state.responseText = "r"
    state.selectedContext = "some selected text"
    state.isGenerating = true
    state.errorMessage = "err"

    state.clearResponse()

    #expect(state.promptText == "")
    #expect(state.responseText == "")
    #expect(state.selectedContext == "")
    #expect(state.isGenerating == false)
    #expect(state.errorMessage == nil)
}

// MARK: - appendMessage / clearConversation

@Test func appendMessageAddsToHistory() {
    let state = makeAppState()

    state.appendMessage(role: "user", content: "hi")

    #expect(state.conversationMessages.count == 1)
    #expect(state.conversationMessages[0].role == "user")
    #expect(state.conversationMessages[0].content == "hi")
}

@Test func appendMessageAccumulatesMultipleMessages() {
    let state = makeAppState()

    state.appendMessage(role: "user", content: "q1")
    state.appendMessage(role: "assistant", content: "a1")
    state.appendMessage(role: "user", content: "q2")

    #expect(state.conversationMessages.count == 3)
    #expect(state.conversationMessages[0].content == "q1")
    #expect(state.conversationMessages[1].content == "a1")
    #expect(state.conversationMessages[2].content == "q2")
}

@Test func clearConversationResetsAllState() {
    let state = makeAppState()
    state.appendMessage(role: "user", content: "q")
    state.appendMessage(role: "assistant", content: "a")
    state.conversationMode = .chat
    state.promptText = "leftover"
    state.responseText = "leftover response"
    state.selectedContext = "context"
    state.isGenerating = true

    state.clearConversation()

    #expect(state.conversationMessages.isEmpty)
    #expect(state.conversationMode == .draft)
    #expect(state.promptText == "")
    #expect(state.responseText == "")
    #expect(state.selectedContext == "")
    #expect(state.isGenerating == false)
}

// MARK: - completeTurn (REGRESSION TESTS for multi-turn bug)

/// Core regression test: completeTurn() must capture promptText BEFORE
/// clearCurrentResponse() blanks it. This was the root cause of the hang.
@Test func completeTurnPreservesPendingPrompt() {
    let state = makeAppState()
    state.responseText = "first answer"
    state.promptText = "follow-up question"

    let pending = state.completeTurn()

    #expect(pending == "follow-up question")
}

@Test func completeTurnArchivesAssistantResponse() {
    let state = makeAppState()
    state.appendMessage(role: "user", content: "question")
    state.responseText = "the answer"
    state.promptText = ""

    _ = state.completeTurn()

    #expect(state.conversationMessages.count == 2)
    #expect(state.conversationMessages[1].role == "assistant")
    #expect(state.conversationMessages[1].content == "the answer")
}

@Test func completeTurnClearsCurrentResponseState() {
    let state = makeAppState()
    state.responseText = "answer"
    state.promptText = "next"
    state.isGenerating = false
    state.errorMessage = "stale error"

    _ = state.completeTurn()

    #expect(state.promptText == "")
    #expect(state.responseText == "")
    #expect(state.isGenerating == false)
    #expect(state.errorMessage == nil)
}

@Test func completeTurnReturnsNilWhenNoPendingPrompt() {
    let state = makeAppState()
    state.responseText = "answer"
    state.promptText = ""

    let pending = state.completeTurn()

    #expect(pending == nil)
}

@Test func completeTurnTrimsWhitespaceOnlyPrompt() {
    let state = makeAppState()
    state.responseText = "answer"
    state.promptText = "  \n  "

    let pending = state.completeTurn()

    #expect(pending == nil)
}

@Test func completeTurnDoesNotArchiveEmptyResponse() {
    let state = makeAppState()
    state.responseText = ""
    state.promptText = "next question"

    let pending = state.completeTurn()

    #expect(pending == "next question")
    #expect(state.conversationMessages.isEmpty)
}

// MARK: - Full multi-turn integration

@Test func fullMultiTurnConversationFlow() {
    let state = makeAppState()

    // --- Turn 1: User asks, gets response ---
    state.appendMessage(role: "user", content: "What is Swift?")
    state.responseText = "Swift is a programming language."
    state.isGenerating = false

    // User types follow-up while response is visible
    state.promptText = "Tell me more"

    // completeTurn archives response and returns pending prompt
    let pending = state.completeTurn()

    #expect(pending == "Tell me more")
    #expect(state.conversationMessages.count == 2)
    #expect(state.conversationMessages[0].role == "user")
    #expect(state.conversationMessages[0].content == "What is Swift?")
    #expect(state.conversationMessages[1].role == "assistant")
    #expect(state.conversationMessages[1].content == "Swift is a programming language.")

    // State is cleared
    #expect(state.promptText == "")
    #expect(state.responseText == "")

    // --- Turn 2: simulate submitting the pending prompt ---
    state.promptText = pending!
    state.appendMessage(role: "user", content: state.promptText)
    state.promptText = ""
    state.responseText = ""
    state.isGenerating = true

    // Simulate response arriving
    state.responseText = "Swift was created by Apple."
    state.isGenerating = false

    #expect(state.conversationMessages.count == 3)
    #expect(state.conversationMessages[2].role == "user")
    #expect(state.conversationMessages[2].content == "Tell me more")
}

// MARK: - modelConfigForRequest

@Test func modelConfigForRequestIncludesRequiredFields() {
    let state = makeAppState()
    state.modelId = "anthropic.claude-3-haiku-20240307-v1:0"
    state.awsRegion = "us-east-1"
    state.awsProfile = "my-profile"

    let config = state.modelConfigForRequest()

    #expect(config["provider"] == "bedrock")
    #expect(config["model_id"] == "anthropic.claude-3-haiku-20240307-v1:0")
    #expect(config["aws_region"] == "us-east-1")
    #expect(config["aws_profile"] == "my-profile")
}

@Test func modelConfigForRequestOmitsEmptyProfile() {
    let state = makeAppState()
    state.awsProfile = ""
    state.awsRegion = "us-west-2"

    let config = state.modelConfigForRequest()

    #expect(config["aws_profile"] == nil)
    #expect(config["aws_region"] == "us-west-2")
}

// MARK: - effectiveAgentId

@Test func effectiveAgentIdReturnsSelectedWhenSet() {
    let state = makeAppState()
    state.availableAgents = [
        AgentInfo(id: "general", name: "General", description: "", supportedModes: ["draft"], isDefault: true, appMappings: []),
        AgentInfo(id: "coding", name: "Code", description: "", supportedModes: ["chat"], isDefault: false, appMappings: []),
    ]
    state.defaultAgentId = "general"
    state.selectedAgentId = "coding"

    #expect(state.effectiveAgentId() == "coding")
}

@Test func effectiveAgentIdAutoDetectsFromBundleId() {
    let state = makeAppState()
    state.availableAgents = [
        AgentInfo(id: "general", name: "General", description: "", supportedModes: ["draft"], isDefault: true, appMappings: []),
        AgentInfo(id: "coding", name: "Code", description: "", supportedModes: ["chat"], isDefault: false, appMappings: ["com.microsoft.VSCode"]),
    ]
    state.defaultAgentId = "general"
    state.selectedAgentId = nil
    state.targetBundleID = "com.microsoft.VSCode"

    #expect(state.effectiveAgentId() == "coding")
}

@Test func effectiveAgentIdFallsBackToDefault() {
    let state = makeAppState()
    state.availableAgents = [
        AgentInfo(id: "general", name: "General", description: "", supportedModes: ["draft"], isDefault: true, appMappings: []),
    ]
    state.defaultAgentId = "general"
    state.selectedAgentId = nil
    state.targetBundleID = nil

    #expect(state.effectiveAgentId() == "general")
}

@Test func effectiveAgentIdReturnsNilWhenNoAgents() {
    let state = makeAppState()
    state.availableAgents = []
    state.defaultAgentId = nil
    state.selectedAgentId = nil

    #expect(state.effectiveAgentId() == nil)
}

// MARK: - buildSessionFromConversation

@Test func buildSessionReturnsNilWhenNoMessages() {
    let state = makeAppState()

    let session = state.buildSessionFromConversation()

    #expect(session == nil)
}

@Test func buildSessionReturnsNilWithOnlyOneMessage() {
    let state = makeAppState()
    state.appendMessage(role: "user", content: "Hello")

    let session = state.buildSessionFromConversation()

    #expect(session == nil)
}

@Test func buildSessionCreatesValidSession() {
    let state = makeAppState()
    state.appendMessage(role: "user", content: "What is Swift?")
    state.appendMessage(role: "assistant", content: "A programming language.")
    state.conversationMode = .chat
    state.modelId = "test-model"

    let session = state.buildSessionFromConversation()

    #expect(session != nil)
    #expect(session?.title == "What is Swift?")
    #expect(session?.mode == "chat")
    #expect(session?.modelId == "test-model")
    #expect(session?.messages.count == 2)
    #expect(session?.messages[0].role == "user")
    #expect(session?.messages[0].content == "What is Swift?")
    #expect(session?.messages[1].role == "assistant")
    #expect(session?.messages[1].content == "A programming language.")
}

@Test func buildSessionTruncatesLongTitle() {
    let state = makeAppState()
    let longPrompt = String(repeating: "x", count: 100)
    state.appendMessage(role: "user", content: longPrompt)
    state.appendMessage(role: "assistant", content: "response")

    let session = state.buildSessionFromConversation()

    #expect(session != nil)
    #expect(session!.title.count == 63) // 60 + "..."
    #expect(session!.title.hasSuffix("..."))
}

@Test func buildSessionIncludesSelectedContext() {
    let state = makeAppState()
    state.selectedContext = "some selected text"
    state.appendMessage(role: "user", content: "Rewrite this")
    state.appendMessage(role: "assistant", content: "Rewritten text")

    let session = state.buildSessionFromConversation()

    #expect(session?.messages[0].context == "some selected text")
}

@Test func buildSessionIncludesAgentId() {
    let state = makeAppState()
    state.selectedAgentId = "coding"
    state.appendMessage(role: "user", content: "q")
    state.appendMessage(role: "assistant", content: "a")

    let session = state.buildSessionFromConversation()

    #expect(session?.agentId == "coding")
}

// MARK: - saveCurrentSession / loadSessionHistory

@Test func saveCurrentSessionIncludesInFlightResponse() throws {
    let (state, base) = makeAppStateWithTempStore()
    defer { cleanup(base) }

    // Simulate: user sent prompt (archived), response streamed into responseText
    // but completeTurn() was never called (draft mode — user dismisses or clicks Insert)
    state.appendMessage(role: "user", content: "Write me a poem")
    state.responseText = "Roses are red, violets are blue"

    state.saveCurrentSession()

    let sessions = state.sessionStore.loadSessions()
    #expect(sessions.count == 1)
    #expect(sessions[0].messages.count == 2)
    #expect(sessions[0].messages[1].role == "assistant")
    #expect(sessions[0].messages[1].content == "Roses are red, violets are blue")
}

@Test func saveCurrentSessionWritesToDisk() throws {
    let (state, base) = makeAppStateWithTempStore()
    defer { cleanup(base) }

    state.appendMessage(role: "user", content: "Hello")
    state.appendMessage(role: "assistant", content: "Hi there")

    state.saveCurrentSession()

    let sessions = state.sessionStore.loadSessions()
    #expect(sessions.count == 1)
    #expect(sessions[0].title == "Hello")
}

@Test func saveCurrentSessionSkipsEmptyConversation() {
    let (state, base) = makeAppStateWithTempStore()
    defer { cleanup(base) }

    state.saveCurrentSession()

    let sessions = state.sessionStore.loadSessions()
    #expect(sessions.isEmpty)
}

@Test func loadSessionHistoryPopulatesList() throws {
    let (state, base) = makeAppStateWithTempStore()
    defer { cleanup(base) }

    // Simulate two saved sessions
    state.appendMessage(role: "user", content: "First chat")
    state.appendMessage(role: "assistant", content: "Response 1")
    state.saveCurrentSession()
    state.conversationMessages = []

    state.appendMessage(role: "user", content: "Second chat")
    state.appendMessage(role: "assistant", content: "Response 2")
    state.saveCurrentSession()

    state.sessionHistory = []
    state.loadSessionHistory()

    #expect(state.sessionHistory.count == 2)
}

@Test func clearConversationAutoSavesSession() throws {
    let (state, base) = makeAppStateWithTempStore()
    defer { cleanup(base) }

    state.appendMessage(role: "user", content: "Before clear")
    state.appendMessage(role: "assistant", content: "Answer")

    state.clearConversation()

    let sessions = state.sessionStore.loadSessions()
    #expect(sessions.count == 1)
    #expect(sessions[0].title == "Before clear")
}

// MARK: - restoreSession

@Test func restoreSessionPopulatesConversationMessages() {
    let state = makeAppState()
    let session = Session(
        id: "s1",
        title: "Test",
        createdAt: Date(),
        updatedAt: Date(),
        mode: "chat",
        agentId: "general",
        modelId: "test-model",
        messages: [
            SessionMessage(id: "m1", role: "user", content: "Hello", timestamp: Date(), context: nil, screenshotFilename: nil),
            SessionMessage(id: "m2", role: "assistant", content: "Hi there", timestamp: Date(), context: nil, screenshotFilename: nil),
            SessionMessage(id: "m3", role: "user", content: "How are you?", timestamp: Date(), context: nil, screenshotFilename: nil),
            SessionMessage(id: "m4", role: "assistant", content: "I'm fine!", timestamp: Date(), context: nil, screenshotFilename: nil),
        ]
    )

    state.restoreSession(session)

    // All messages except last assistant go into conversationMessages
    #expect(state.conversationMessages.count == 3)
    #expect(state.conversationMessages[0].role == "user")
    #expect(state.conversationMessages[0].content == "Hello")
    #expect(state.conversationMessages[1].role == "assistant")
    #expect(state.conversationMessages[1].content == "Hi there")
    #expect(state.conversationMessages[2].role == "user")
    #expect(state.conversationMessages[2].content == "How are you?")
    // Last assistant response goes into responseText
    #expect(state.responseText == "I'm fine!")
}

@Test func restoreSessionSetsConversationMode() {
    let state = makeAppState()
    let session = Session(
        id: "s1",
        title: "Test",
        createdAt: Date(),
        updatedAt: Date(),
        mode: "chat",
        agentId: nil,
        modelId: "m",
        messages: [
            SessionMessage(id: "m1", role: "user", content: "q", timestamp: Date(), context: nil, screenshotFilename: nil),
            SessionMessage(id: "m2", role: "assistant", content: "a", timestamp: Date(), context: nil, screenshotFilename: nil),
        ]
    )

    state.restoreSession(session)

    #expect(state.conversationMode == .chat)
}

@Test func restoreSessionSetsDraftMode() {
    let state = makeAppState()
    let session = Session(
        id: "s1",
        title: "Test",
        createdAt: Date(),
        updatedAt: Date(),
        mode: "draft",
        agentId: nil,
        modelId: "m",
        messages: [
            SessionMessage(id: "m1", role: "user", content: "q", timestamp: Date(), context: nil, screenshotFilename: nil),
            SessionMessage(id: "m2", role: "assistant", content: "a", timestamp: Date(), context: nil, screenshotFilename: nil),
        ]
    )

    state.restoreSession(session)

    #expect(state.conversationMode == .draft)
}

@Test func restoreSessionSetsAgentId() {
    let state = makeAppState()
    let session = Session(
        id: "s1",
        title: "Test",
        createdAt: Date(),
        updatedAt: Date(),
        mode: "chat",
        agentId: "coding",
        modelId: "m",
        messages: [
            SessionMessage(id: "m1", role: "user", content: "q", timestamp: Date(), context: nil, screenshotFilename: nil),
            SessionMessage(id: "m2", role: "assistant", content: "a", timestamp: Date(), context: nil, screenshotFilename: nil),
        ]
    )

    state.restoreSession(session)

    #expect(state.selectedAgentId == "coding")
}

@Test func restoreSessionEmptySessionIsNoOp() {
    let state = makeAppState()
    state.conversationMode = .draft
    state.promptText = "existing"

    let emptySession = Session(
        id: "s1",
        title: "Empty",
        createdAt: Date(),
        updatedAt: Date(),
        mode: "chat",
        agentId: nil,
        modelId: "m",
        messages: []
    )

    state.restoreSession(emptySession)

    // Nothing should change
    #expect(state.conversationMode == .draft)
    #expect(state.promptText == "existing")
    #expect(state.conversationMessages.isEmpty)
}

@Test func restoreSessionSavesCurrentConversationFirst() throws {
    let (state, base) = makeAppStateWithTempStore()
    defer { cleanup(base) }

    // Set up an existing conversation
    state.appendMessage(role: "user", content: "Old question")
    state.appendMessage(role: "assistant", content: "Old answer")

    let session = Session(
        id: "s1",
        title: "New",
        createdAt: Date(),
        updatedAt: Date(),
        mode: "chat",
        agentId: nil,
        modelId: "m",
        messages: [
            SessionMessage(id: "m1", role: "user", content: "q", timestamp: Date(), context: nil, screenshotFilename: nil),
            SessionMessage(id: "m2", role: "assistant", content: "a", timestamp: Date(), context: nil, screenshotFilename: nil),
        ]
    )

    state.restoreSession(session)

    // The old conversation should have been saved
    let sessions = state.sessionStore.loadSessions()
    #expect(sessions.count >= 1)
    let saved = sessions.first(where: { $0.title == "Old question" })
    #expect(saved != nil)
}

@Test func deleteSessionRemovesAndRefreshes() throws {
    let (state, base) = makeAppStateWithTempStore()
    defer { cleanup(base) }

    state.appendMessage(role: "user", content: "To delete")
    state.appendMessage(role: "assistant", content: "Response")
    state.saveCurrentSession()
    state.loadSessionHistory()

    #expect(state.sessionHistory.count == 1)
    let sessionId = state.sessionHistory[0].id

    state.deleteSession(id: sessionId)

    #expect(state.sessionHistory.isEmpty)
}
