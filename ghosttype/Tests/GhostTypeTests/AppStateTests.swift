import Testing
@testable import GhostTypeLib

private func makeAppState() -> AppState {
    AppState()
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
