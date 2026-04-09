import Foundation

// MARK: - Token Batching & Generation State

extension AppState {
    /// Start batching tokens for smoother UI updates during streaming.
    /// Timer runs in RunLoop.common mode so it fires even during scroll tracking
    /// (the run loop switches to .tracking mode during scroll gestures, which would
    /// starve a .default-mode timer and freeze the UI).
    func startTokenBatching() {
        NSLog("[GhostType][TokenBatch] Started")
        tokenBuffer = ""
        tokenFlushTimer?.invalidate()
        let timer = Timer(timeInterval: 0.15, repeats: true) { [weak self] _ in
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
    internal func flushTokenBuffer() {
        guard !tokenBuffer.isEmpty else { return }
        let flushed = tokenBuffer
        tokenBuffer = ""
        responseText += flushed
    }

    // MARK: - Tool Call Handling

    /// Called when a tool invocation starts.
    func handleToolStart(name: String, id: String) {
        let info = ToolCallInfo(id: id, name: name)
        activeToolCalls = activeToolCalls + [info]
    }

    /// Called when a tool invocation completes.
    func handleToolDone(name: String, id: String, input: String?) {
        activeToolCalls = activeToolCalls.map { call in
            guard call.id == id else { return call }
            return call.withStatus(.completed).withInput(input)
        }
    }

    /// Mark all remaining running tools as completed (e.g. on generation finish).
    func completeAllToolCalls() {
        activeToolCalls = activeToolCalls.map { call in
            call.status == .running ? call.withStatus(.completed) : call
        }
    }
}
