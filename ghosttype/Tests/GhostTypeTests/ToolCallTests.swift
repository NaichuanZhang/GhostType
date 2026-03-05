import Testing
@testable import GhostTypeLib

// MARK: - ToolCallInfo creation

@Test func toolCallInfoCreation() {
    let info = ToolCallInfo(id: "t1", name: "rewrite_text")
    #expect(info.id == "t1")
    #expect(info.name == "rewrite_text")
    #expect(info.status == .running)
    #expect(info.toolInput == nil)
}

// MARK: - Display name mapping

@Test func displayNameKnownTools() {
    #expect(ToolCallInfo.displayName(for: "rewrite_text") == "Rewriting text")
    #expect(ToolCallInfo.displayName(for: "fix_grammar") == "Fixing grammar")
    #expect(ToolCallInfo.displayName(for: "translate_text") == "Translating")
    #expect(ToolCallInfo.displayName(for: "count_words") == "Counting words")
    #expect(ToolCallInfo.displayName(for: "extract_key_points") == "Extracting key points")
    #expect(ToolCallInfo.displayName(for: "change_tone") == "Changing tone")
    #expect(ToolCallInfo.displayName(for: "save_memory") == "Saving to memory")
    #expect(ToolCallInfo.displayName(for: "recall_memories") == "Recalling memories")
    #expect(ToolCallInfo.displayName(for: "forget_memory") == "Forgetting memory")
}

@Test func displayNameUnknownTool() {
    // Unknown tools get title-cased with underscores replaced
    #expect(ToolCallInfo.displayName(for: "some_custom_tool") == "Some Custom Tool")
    #expect(ToolCallInfo.displayName(for: "mcp_weather") == "Mcp Weather")
}

@Test func displayNameComputedProperty() {
    let info = ToolCallInfo(id: "t2", name: "fix_grammar")
    #expect(info.displayName == "Fixing grammar")
}

// MARK: - Tool status transitions (immutable)

@Test func toolStatusCompleted() {
    let info = ToolCallInfo(id: "t3", name: "count_words")
    let completed = info.withStatus(.completed)

    // Original unchanged
    #expect(info.status == .running)
    // New copy is completed
    #expect(completed.status == .completed)
    #expect(completed.id == "t3")
    #expect(completed.name == "count_words")
}

@Test func toolStatusWithInput() {
    let info = ToolCallInfo(id: "t4", name: "rewrite_text")
    let withInput = info.withInput("{\"style\": \"formal\"}")

    #expect(info.toolInput == nil)
    #expect(withInput.toolInput == "{\"style\": \"formal\"}")
    #expect(withInput.id == "t4")
}

// MARK: - AppState tool call handling

@Test func appStateHandleToolStart() {
    let state = AppState()
    state.handleToolStart(name: "rewrite_text", id: "t5")

    #expect(state.activeToolCalls.count == 1)
    #expect(state.activeToolCalls[0].id == "t5")
    #expect(state.activeToolCalls[0].name == "rewrite_text")
    #expect(state.activeToolCalls[0].status == .running)
}

@Test func appStateHandleToolDone() {
    let state = AppState()
    state.handleToolStart(name: "rewrite_text", id: "t6")
    state.handleToolDone(name: "rewrite_text", id: "t6", input: "{\"style\": \"casual\"}")

    #expect(state.activeToolCalls.count == 1)
    #expect(state.activeToolCalls[0].status == .completed)
    #expect(state.activeToolCalls[0].toolInput == "{\"style\": \"casual\"}")
}

@Test func appStateHandleToolDoneUnknownId() {
    let state = AppState()
    // Done for unknown ID should not crash
    state.handleToolDone(name: "rewrite_text", id: "nonexistent", input: nil)
    #expect(state.activeToolCalls.isEmpty)
}

@Test func appStateMultipleToolCalls() {
    let state = AppState()
    state.handleToolStart(name: "count_words", id: "t7")
    state.handleToolStart(name: "rewrite_text", id: "t8")

    #expect(state.activeToolCalls.count == 2)
    #expect(state.activeToolCalls[0].name == "count_words")
    #expect(state.activeToolCalls[1].name == "rewrite_text")
}

@Test func appStateClearResponseResetsToolCalls() {
    let state = AppState()
    state.handleToolStart(name: "count_words", id: "t9")
    state.clearResponse()

    #expect(state.activeToolCalls.isEmpty)
}
