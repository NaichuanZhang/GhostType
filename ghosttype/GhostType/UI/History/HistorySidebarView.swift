import SwiftUI

/// Sidebar listing saved conversation sessions, newest first.
/// Slides in from the left edge of the prompt panel.
struct HistorySidebarView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedSessionId: String?
    @State private var showDeleteAllAlert = false

    var body: some View {
        VStack(spacing: 0) {
            if let sessionId = selectedSessionId,
               let session = appState.sessionHistory.first(where: { $0.id == sessionId }) {
                SessionDetailView(
                    session: session,
                    onBack: { selectedSessionId = nil }
                )
            } else {
                sessionList
            }
        }
        .frame(width: 260)
        .background(.ultraThinMaterial)
    }

    // MARK: - Session List

    private var sessionList: some View {
        VStack(spacing: 0) {
            listHeader
            Divider()

            if appState.sessionHistory.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(appState.sessionHistory) { session in
                            sessionRow(session)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }

    private var listHeader: some View {
        HStack {
            Text("History")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.primary)

            Spacer()

            if !appState.sessionHistory.isEmpty {
                Button(action: { showDeleteAllAlert = true }) {
                    Text("Clear All")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.red.opacity(0.8))
                }
                .buttonStyle(.plain)
                .alert("Clear All History?", isPresented: $showDeleteAllAlert) {
                    Button("Cancel", role: .cancel) {}
                    Button("Clear All", role: .destructive) {
                        deleteAllSessions()
                    }
                } message: {
                    Text("This will permanently delete all saved sessions.")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "clock")
                .font(.system(size: 24))
                .foregroundStyle(.tertiary)
            Text("No sessions yet")
                .font(.system(size: 12))
                .foregroundStyle(.tertiary)
            Text("Conversations are saved\nwhen you start a new one.")
                .font(.system(size: 10))
                .foregroundStyle(.quaternary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Session Row

    private func sessionRow(_ session: Session) -> some View {
        Button(action: { selectedSessionId = session.id }) {
            VStack(alignment: .leading, spacing: 4) {
                Text(session.title)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                HStack(spacing: 6) {
                    Text(relativeDate(session.createdAt))
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)

                    Text("\(session.messages.count) msgs")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)

                    Text(session.mode)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(.quaternary.opacity(0.5))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button(role: .destructive) {
                appState.deleteSession(id: session.id)
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    // MARK: - Helpers

    private func deleteAllSessions() {
        let ids = appState.sessionHistory.map(\.id)
        for id in ids {
            appState.deleteSession(id: id)
        }
    }

    private func relativeDate(_ date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}
