import Testing
import Foundation
@testable import GhostTypeLib

// MARK: - Generation State Tests (token batching, tool calls)

@Suite("Generation State Tests")
struct GenerationStateTests {
    @Test("appendToken buffers without immediate flush")
    func appendTokenBuffers() {
        let state = AppState()
        state.appendToken("hello")
        state.appendToken(" world")
        // Tokens are buffered, not yet in responseText
        #expect(state.responseText == "")
    }

    @Test("flushTokenBuffer moves buffer to responseText")
    func flushTokenBuffer() {
        let state = AppState()
        state.appendToken("hello")
        state.appendToken(" world")
        state.flushTokenBuffer()
        #expect(state.responseText == "hello world")
    }

    @Test("flushTokenBuffer is idempotent when buffer is empty")
    func flushEmptyBuffer() {
        let state = AppState()
        state.responseText = "existing"
        state.flushTokenBuffer()
        #expect(state.responseText == "existing")
    }

    @Test("stopTokenBatching flushes remaining buffer")
    func stopBatchingFlushes() {
        let state = AppState()
        state.appendToken("partial")
        state.stopTokenBatching()
        #expect(state.responseText == "partial")
    }

    @Test("handleToolStart adds to activeToolCalls")
    func toolStart() {
        let state = AppState()
        state.handleToolStart(name: "rewrite_text", id: "t1")
        #expect(state.activeToolCalls.count == 1)
        #expect(state.activeToolCalls[0].name == "rewrite_text")
        #expect(state.activeToolCalls[0].status == .running)
    }

    @Test("handleToolDone updates status to completed")
    func toolDone() {
        let state = AppState()
        state.handleToolStart(name: "rewrite_text", id: "t1")
        state.handleToolDone(name: "rewrite_text", id: "t1", input: "{}")
        #expect(state.activeToolCalls[0].status == .completed)
        #expect(state.activeToolCalls[0].toolInput == "{}")
    }

    @Test("completeAllToolCalls marks all running as completed")
    func completeAll() {
        let state = AppState()
        state.handleToolStart(name: "tool1", id: "t1")
        state.handleToolStart(name: "tool2", id: "t2")
        state.handleToolDone(name: "tool1", id: "t1", input: nil)
        state.completeAllToolCalls()
        #expect(state.activeToolCalls.allSatisfy { $0.status == .completed })
    }

    @Test("multiple flushes accumulate correctly")
    func multipleFlushes() {
        let state = AppState()
        state.appendToken("a")
        state.flushTokenBuffer()
        state.appendToken("b")
        state.flushTokenBuffer()
        #expect(state.responseText == "ab")
    }
}
