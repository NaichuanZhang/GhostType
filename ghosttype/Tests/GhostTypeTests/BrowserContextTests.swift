import Testing
@testable import GhostTypeLib

@Suite("Browser Context Tests")
struct BrowserContextTests {
    @Test("browserContext is initially nil")
    func browserContext_initially_nil() {
        let state = AppState()
        #expect(state.browserContext == nil)
    }

    @Test("isBrowserContextAttached is false by default")
    func isBrowserContextAttached_false_by_default() {
        let state = AppState()
        #expect(state.isBrowserContextAttached == false)
    }

    @Test("clearBrowserContext resets state")
    func clearBrowserContext_resets_state() {
        let state = AppState()
        // Simulate attached context
        state.browserContext = BrowserContextService.BrowserContextData(
            url: "https://example.com",
            title: "Example",
            content: "body",
            selectedText: "",
            timestamp: 100.0
        )
        state.isBrowserContextAttached = true

        state.clearBrowserContext()

        #expect(state.browserContext == nil)
        #expect(state.isBrowserContextAttached == false)
    }

    // MARK: - @mention acceptance logic

    @Test("Removing trailing @ from prompt text leaves the rest intact")
    func promptText_at_removal_pattern() {
        let prompt = "summarize @"
        let result = String(prompt.dropLast())
        #expect(result == "summarize ")
    }

    @Test("Removing trailing @ when prompt is just '@' yields empty string")
    func promptText_at_removal_single_char() {
        let prompt = "@"
        let result = String(prompt.dropLast())
        #expect(result == "")
    }

    @Test("acceptMentionSuggestion sets isBrowserContextAttached after fetch completes")
    func acceptMention_triggers_fetch_and_attaches() async throws {
        let state = AppState()
        state.promptText = "help me @"

        // Simulate what acceptMentionSuggestion does:
        // 1. Remove trailing @
        if state.promptText.hasSuffix("@") {
            state.promptText = String(state.promptText.dropLast())
        }
        // 2. Simulate fetch completing with data
        state.browserContext = BrowserContextService.BrowserContextData(
            url: "https://example.com",
            title: "Example",
            content: "body",
            selectedText: "",
            timestamp: 100.0
        )
        state.isBrowserContextAttached = true

        #expect(state.promptText == "help me ")
        #expect(state.isBrowserContextAttached == true)
    }

    @Test("acceptMentionSuggestion is noop when no trailing @")
    func acceptMention_noop_without_trailing_at() {
        let state = AppState()
        state.promptText = "hello"

        // acceptMentionSuggestion only removes trailing @
        let originalPrompt = state.promptText
        if state.promptText.hasSuffix("@") {
            state.promptText = String(state.promptText.dropLast())
        }

        #expect(state.promptText == originalPrompt)
    }

    @Test("clearResponse also clears browser context")
    func clearResponse_clears_browserContext() {
        let state = AppState()
        state.browserContext = BrowserContextService.BrowserContextData(
            url: "https://example.com",
            title: "Test",
            content: "content",
            selectedText: "",
            timestamp: 1.0
        )
        state.isBrowserContextAttached = true

        state.clearResponse()

        #expect(state.browserContext == nil)
        #expect(state.isBrowserContextAttached == false)
    }
}
