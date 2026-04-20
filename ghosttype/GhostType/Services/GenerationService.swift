import Foundation

/// Handles AI text generation via the Python subprocess.
class GenerationService {
    private let subprocess: SubprocessManager
    private var eventTask: Task<Void, Never>?

    init(subprocess: SubprocessManager) {
        self.subprocess = subprocess
    }

    /// Starts generation and streams events to the AppState.
    func generate(
        prompt: String,
        context: String,
        mode: String,
        modeType: String,
        config: [String: String],
        screenshot: String? = nil,
        agent: String? = nil,
        browserContext: String? = nil,
        appState: AppState
    ) {
        guard subprocess.isRunning else {
            NSLog("[GhostType][Gen] Subprocess not running, reporting error to user")
            subprocess.start()
            DispatchQueue.main.async { [weak appState] in
                appState?.errorMessage = "Backend not available. Retrying startup — please try again in a moment."
                appState?.isGenerating = false
            }
            return
        }

        let request = SubprocessRequest(
            type: "generate",
            prompt: prompt,
            context: context,
            mode: mode,
            modeType: modeType,
            agent: agent,
            screenshot: screenshot,
            browserContext: browserContext,
            config: config
        )

        subprocess.send(request)

        // Listen for events and update appState
        eventTask?.cancel()
        eventTask = Task { @MainActor [weak appState] in
            guard let appState = appState else { return }

            do { for try await event in subprocess.events() {
                switch event {
                case .token(let text):
                    appState.appendToken(text)

                case .done(let fullResponse):
                    appState.stopTokenBatching()
                    appState.completeAllToolCalls()
                    let streamedLen = appState.responseText.count
                    NSLog("[GhostType][Gen] Done, response_len=%d, streamed_len=%d",
                          fullResponse.count, streamedLen)
                    if appState.responseText.isEmpty && !fullResponse.isEmpty {
                        NSLog("[GhostType][Gen] No tokens streamed — using full response")
                        appState.responseText = fullResponse
                    }
                    appState.isGenerating = false
                    return  // Generation complete

                case .error(let message):
                    appState.stopTokenBatching()
                    NSLog("[GhostType][Gen] Error: %@", message)
                    appState.errorMessage = message
                    appState.isGenerating = false
                    return

                case .cancelled:
                    appState.stopTokenBatching()
                    appState.completeAllToolCalls()
                    NSLog("[GhostType][Gen] Cancelled")
                    appState.isGenerating = false
                    return

                case .toolStart(let name, let id):
                    appState.handleToolStart(name: name, id: id)

                case .toolDone(let name, let id, let input):
                    appState.handleToolDone(name: name, id: id, input: input)

                case .conversationReset, .historyRestored, .agents, .browserContext:
                    break  // Not expected during generation
                }
            } } catch {
                NSLog("[GhostType][Gen] Event stream error: %@", error.localizedDescription)
            }
        }
    }

    /// Cancels the current generation.
    func cancel() {
        subprocess.send(SubprocessRequest(type: "cancel"))
    }

    /// Resets the conversation in the backend.
    func newConversation() {
        subprocess.send(SubprocessRequest(type: "new_conversation"))
    }

    /// Restores conversation history in the backend.
    func restoreHistory(messages: [[String: String]], config: [String: String], modeType: String, agent: String?) {
        subprocess.send(SubprocessRequest(
            type: "restore_history",
            modeType: modeType,
            agent: agent,
            config: config,
            messages: messages
        ))
    }

    /// Fetches available agents from the backend.
    func fetchAgents(completion: @escaping ([AgentInfo], String?) -> Void) {
        subprocess.send(SubprocessRequest(type: "get_agents"))

        Task {
            do {
                for try await event in subprocess.events() {
                    if case .agents(let agents, let defaultId) = event {
                        await MainActor.run {
                            completion(agents, defaultId)
                        }
                        return
                    }
                }
            } catch {
                NSLog("[GhostType][Gen] Agent fetch error: %@", error.localizedDescription)
            }
        }
    }

    /// Fetches browser context from the backend.
    func fetchBrowserContext(completion: @escaping (BrowserContextService.BrowserContextData?) -> Void) {
        subprocess.send(SubprocessRequest(type: "get_browser_context"))

        Task {
            do {
                for try await event in subprocess.events() {
                    if case .browserContext(let data) = event {
                        await MainActor.run {
                            completion(data)
                        }
                        return
                    }
                }
            } catch {
                NSLog("[GhostType][Gen] Browser context fetch error: %@", error.localizedDescription)
                await MainActor.run { completion(nil) }
            }
        }
    }

    func stop() {
        eventTask?.cancel()
        subprocess.stop()
    }
}
