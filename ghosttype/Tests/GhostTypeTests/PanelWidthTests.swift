import Testing
@testable import GhostTypeLib

// MARK: - panelWidth is a static constant

@Test func panelWidthIsStaticConstant() {
    let state = AppState()
    #expect(state.panelWidth == 480)
}

// MARK: - panelWidth unchanged by state operations

@Test func panelWidthUnchangedAfterClearConversation() {
    let state = AppState()
    state.clearConversation()
    #expect(state.panelWidth == 480)
}

@Test func panelWidthUnchangedAfterClearResponse() {
    let state = AppState()
    state.clearResponse()
    #expect(state.panelWidth == 480)
}

@Test func panelWidthUnchangedAfterClearCurrentResponse() {
    let state = AppState()
    state.clearCurrentResponse()
    #expect(state.panelWidth == 480)
}

@Test func panelWidthUnchangedAfterCompleteTurn() {
    let state = AppState()
    state.responseText = "answer"
    state.promptText = "follow-up"
    _ = state.completeTurn()
    #expect(state.panelWidth == 480)
}
