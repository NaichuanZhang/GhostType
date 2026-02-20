import Testing
@testable import GhostTypeLib

// MARK: - panelWidth default

@Test func panelWidthDefaultIs420() {
    let state = AppState()
    #expect(state.panelWidth == 420)
}

// MARK: - panelWidth survives state clears

/// Regression: clearConversation() must NOT reset panelWidth — it is set
/// from the active app's window frame at panel-open time and must persist
/// across conversation resets within the same panel session.
@Test func clearConversationPreservesPanelWidth() {
    let state = AppState()
    state.panelWidth = 700

    state.clearConversation()

    #expect(state.panelWidth == 700)
}

@Test func clearResponsePreservesPanelWidth() {
    let state = AppState()
    state.panelWidth = 550

    state.clearResponse()

    #expect(state.panelWidth == 550)
}

@Test func clearCurrentResponsePreservesPanelWidth() {
    let state = AppState()
    state.panelWidth = 600

    state.clearCurrentResponse()

    #expect(state.panelWidth == 600)
}

@Test func completeTurnPreservesPanelWidth() {
    let state = AppState()
    state.panelWidth = 500
    state.responseText = "answer"
    state.promptText = "follow-up"

    _ = state.completeTurn()

    #expect(state.panelWidth == 500)
}

// MARK: - panelWidth can be set to arbitrary values

@Test func panelWidthCanBeSetToCustomValue() {
    let state = AppState()
    state.panelWidth = 380
    #expect(state.panelWidth == 380)

    state.panelWidth = 900
    #expect(state.panelWidth == 900)
}
