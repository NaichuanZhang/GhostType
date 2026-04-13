import SwiftUI

/// Header bar with app title, status indicator, agent picker, and controls.
struct HeaderBar: View {
    @EnvironmentObject var appState: AppState
    @Binding var showHistorySidebar: Bool
    let onCancel: () -> Void
    let onNewConversation: () -> Void

    private var hasConversationHistory: Bool {
        !appState.conversationMessages.isEmpty
    }

    private var effectiveAgentTools: [String] {
        guard let agentId = appState.effectiveAgentId(),
              let agent = appState.availableAgents.first(where: { $0.id == agentId }) else {
            return []
        }
        return agent.tools
    }

    var body: some View {
        VStack(spacing: 0) {
        HStack {
            Image(systemName: "text.cursor")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
            Text("GhostType")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)

            // Subprocess status indicator
            Circle()
                .fill(appState.subprocess.isRunning ? .green : .orange)
                .frame(width: 6, height: 6)

            // Mode indicator (after first turn)
            if hasConversationHistory {
                Text(appState.conversationMode == .chat ? "Chat" : "Draft")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(.quaternary.opacity(0.5))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            // Agent picker (when agents are available)
            if appState.availableAgents.count > 1 {
                AgentPickerView()
            }

            // History sidebar toggle
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showHistorySidebar.toggle()
                }
            }) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(showHistorySidebar ? .purple : .secondary)
            }
            .buttonStyle(.plain)
            .help("Session History")

            Spacer()

            if appState.isGenerating {
                Button(action: onCancel) {
                    HStack(spacing: 3) {
                        Image(systemName: "stop.fill")
                            .font(.system(size: 8))
                        Text("Stop")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            } else {
                if hasConversationHistory {
                    Button(action: onNewConversation) {
                        HStack(spacing: 3) {
                            Image(systemName: "plus.circle")
                                .font(.system(size: 10))
                            Text("New")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .padding(.trailing, 6)
                }

                Text("Esc to close")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)

            // Available tools row
            if !effectiveAgentTools.isEmpty && !appState.isGenerating {
                AvailableToolsRow(tools: effectiveAgentTools)
            }
        }
    }
}

// MARK: - Available Tools

struct AvailableToolsRow: View {
    let tools: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.system(size: 9))
                    .foregroundStyle(.tertiary)
                ForEach(tools, id: \.self) { tool in
                    Text(ToolCallInfo.displayName(for: tool))
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(.quaternary.opacity(0.3))
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 6)
        }
    }
}

// MARK: - Agent Picker

struct AgentPickerView: View {
    @EnvironmentObject var appState: AppState

    private var effectiveAgentName: String {
        let agentId = appState.effectiveAgentId()
        return appState.availableAgents.first(where: { $0.id == agentId })?.name ?? "Auto"
    }

    var body: some View {
        Menu {
            Button(action: { appState.selectedAgentId = nil }) {
                HStack {
                    Text("Auto")
                    if appState.selectedAgentId == nil {
                        Image(systemName: "checkmark")
                    }
                }
            }
            Divider()
            ForEach(appState.availableAgents) { agent in
                Button(action: { appState.selectedAgentId = agent.id }) {
                    HStack {
                        Text(agent.name)
                        if appState.selectedAgentId == agent.id {
                            Image(systemName: "checkmark")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "person.2.circle")
                    .font(.system(size: 9))
                Text(effectiveAgentName)
                    .font(.system(size: 9, weight: .medium))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.quaternary.opacity(0.5))
            .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}
