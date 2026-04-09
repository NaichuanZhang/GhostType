import Foundation

// MARK: - Session Persistence & Resume

extension AppState {
    /// Returns true when the previous session should be restored (dismissed recently + has messages).
    func shouldResumeSession(now: Date = Date()) -> Bool {
        guard let dismissTime = lastPanelDismissTime else { return false }
        guard !conversationMessages.isEmpty else { return false }
        return now.timeIntervalSince(dismissTime) < Self.sessionResumeTimeout
    }

    /// Records the current time as the panel dismiss timestamp.
    func recordPanelDismiss(at date: Date = Date()) {
        lastPanelDismissTime = date
    }

    /// Builds a Session from the current conversation state.
    /// Returns nil if fewer than 2 messages (need at least 1 user + 1 assistant).
    func buildSessionFromConversation(messages: [ConversationMessage]? = nil) -> Session? {
        let msgs = messages ?? conversationMessages
        guard msgs.count >= 2 else { return nil }

        let firstUserContent = msgs.first(where: { $0.role == "user" })?.content ?? ""
        let title = Session.generateTitle(from: firstUserContent)
        let now = Date()

        let sessionMessages = msgs.enumerated().map { index, msg in
            SessionMessage(
                id: msg.id.uuidString,
                role: msg.role,
                content: msg.content,
                timestamp: msg.timestamp,
                context: index == 0 ? (selectedContext.isEmpty ? nil : selectedContext) : nil,
                screenshotFilename: nil
            )
        }

        return Session(
            id: UUID().uuidString,
            title: title,
            createdAt: msgs.first?.timestamp ?? now,
            updatedAt: msgs.last?.timestamp ?? now,
            mode: conversationMode == .chat ? "chat" : "draft",
            agentId: effectiveAgentId(),
            modelId: modelId,
            messages: sessionMessages
        )
    }

    /// Saves the current conversation as a session (if it has enough messages).
    /// Also saves any attached screenshot.
    func saveCurrentSession() {
        // Build messages for saving without mutating conversationMessages
        var messagesForSave = conversationMessages
        if !responseText.isEmpty {
            messagesForSave.append(ConversationMessage(role: "assistant", content: responseText))
        }
        guard var session = buildSessionFromConversation(messages: messagesForSave) else { return }

        // Save screenshot if present
        if let base64 = screenshotBase64, let data = Data(base64Encoded: base64) {
            let filename = "\(session.id)_0.jpg"
            do {
                try sessionStore.saveScreenshot(data: data, filename: filename)
                // Update the first user message with the screenshot filename
                var updatedMessages = session.messages
                if !updatedMessages.isEmpty {
                    let first = updatedMessages[0]
                    updatedMessages[0] = SessionMessage(
                        id: first.id,
                        role: first.role,
                        content: first.content,
                        timestamp: first.timestamp,
                        context: first.context,
                        screenshotFilename: filename
                    )
                }
                session = Session(
                    id: session.id,
                    title: session.title,
                    createdAt: session.createdAt,
                    updatedAt: session.updatedAt,
                    mode: session.mode,
                    agentId: session.agentId,
                    modelId: session.modelId,
                    messages: updatedMessages
                )
            } catch {
                NSLog("[GhostType][AppState] Failed to save screenshot: %@", error.localizedDescription)
            }
        }

        do {
            try sessionStore.saveSession(session)
            NSLog("[GhostType][AppState] Saved session %@ (%d messages)", session.id, session.messages.count)
            loadSessionHistory()
        } catch {
            NSLog("[GhostType][AppState] Failed to save session: %@", error.localizedDescription)
        }
    }

    /// Loads a saved session into the active chat for continuation.
    func restoreSession(_ session: Session) {
        guard !session.messages.isEmpty else { return }

        // Save current conversation before replacing
        clearConversation()

        // Set mode from session
        conversationMode = session.mode == "chat" ? .chat : .draft

        // Set agent from session
        selectedAgentId = session.agentId

        // Convert session messages to conversation messages.
        // All messages except the last assistant go into conversationMessages.
        // The last assistant message goes into responseText so the UI renders it
        // as the current (most recent) response.
        let allMessages = session.messages
        let lastAssistantIndex = allMessages.lastIndex(where: { $0.role == "assistant" })

        for (index, msg) in allMessages.enumerated() {
            if index == lastAssistantIndex {
                responseText = msg.content
            } else {
                conversationMessages.append(
                    ConversationMessage(role: msg.role, content: msg.content)
                )
            }
        }

        // Sync history to backend agent via subprocess
        let simplifiedMessages = allMessages.map { ["role": $0.role, "content": $0.content] }
        generationService.restoreHistory(
            messages: simplifiedMessages,
            config: modelConfigForRequest(),
            modeType: session.mode == "chat" ? "chat" : "draft",
            agent: session.agentId
        )

        NSLog("[GhostType][AppState] Restored session %@ (%d messages)", session.id, session.messages.count)
    }

    /// Populates sessionHistory from disk.
    func loadSessionHistory() {
        sessionHistory = sessionStore.loadSessions()
    }

    /// Deletes a session by ID and refreshes the list.
    func deleteSession(id: String) {
        do {
            try sessionStore.deleteSession(id: id)
        } catch {
            NSLog("[GhostType][AppState] Failed to delete session %@: %@", id, error.localizedDescription)
        }
        loadSessionHistory()
    }
}
