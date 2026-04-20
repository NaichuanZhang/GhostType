import Testing
import Foundation
@testable import GhostTypeLib

// MARK: - Conversation State Tests

@Suite("Conversation State Tests")
struct ConversationStateTests {
    @Test("appendMessage adds to conversation")
    func appendMessage() {
        let state = AppState()
        state.appendMessage(role: "user", content: "hello")
        state.appendMessage(role: "assistant", content: "hi there")
        #expect(state.conversationMessages.count == 2)
        #expect(state.conversationMessages[0].role == "user")
        #expect(state.conversationMessages[1].content == "hi there")
    }

    @Test("completeTurn archives response and returns pending prompt")
    func completeTurnWithPending() {
        let state = AppState()
        state.responseText = "assistant response"
        state.promptText = "follow up"

        let pending = state.completeTurn()

        #expect(pending == "follow up")
        #expect(state.conversationMessages.last?.role == "assistant")
        #expect(state.conversationMessages.last?.content == "assistant response")
        #expect(state.responseText == "")
        #expect(state.promptText == "")
    }

    @Test("completeTurn returns nil when no pending prompt")
    func completeTurnNoPending() {
        let state = AppState()
        state.responseText = "response"
        state.promptText = ""

        let pending = state.completeTurn()
        #expect(pending == nil)
    }

    @Test("completeTurn with whitespace-only prompt returns nil")
    func completeTurnWhitespacePrompt() {
        let state = AppState()
        state.responseText = "response"
        state.promptText = "   \n  "

        let pending = state.completeTurn()
        #expect(pending == nil)
    }

    @Test("clearConversation resets all conversation state")
    func clearConversation() {
        let state = AppState()
        state.appendMessage(role: "user", content: "test")
        state.conversationMode = .chat
        state.responseText = "some text"

        state.clearConversation()

        #expect(state.conversationMessages.isEmpty)
        #expect(state.conversationMode == .draft)
        #expect(state.responseText == "")
    }

    @Test("clearCurrentResponse preserves conversation history")
    func clearCurrentResponsePreservesHistory() {
        let state = AppState()
        state.appendMessage(role: "user", content: "kept")
        state.responseText = "cleared"
        state.promptText = "also cleared"

        state.clearCurrentResponse()

        #expect(state.conversationMessages.count == 1)
        #expect(state.responseText == "")
        #expect(state.promptText == "")
    }
}
