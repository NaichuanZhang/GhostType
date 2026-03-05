import SwiftUI

/// Displays active tool calls as compact chips (collapsed) or detailed list (expanded).
struct ToolCallsView: View {
    let toolCalls: [ToolCallInfo]
    @Binding var isExpanded: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if isExpanded {
                expandedView
            } else {
                collapsedView
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
    }

    // MARK: - Collapsed: Horizontal chip row

    private var collapsedView: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(toolCalls) { call in
                    toolChip(call)
                }
            }
        }
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                isExpanded = true
            }
        }
    }

    private func toolChip(_ call: ToolCallInfo) -> some View {
        HStack(spacing: 4) {
            statusIcon(call.status)
            Text(call.displayName)
                .font(.system(size: 11, weight: .medium))
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.quaternary.opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    // MARK: - Expanded: Detailed list

    private var expandedView: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header with collapse toggle
            HStack {
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                Text("Tools used (\(toolCalls.count))")
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    isExpanded = false
                }
            }

            // Tool details
            ForEach(toolCalls) { call in
                toolDetailRow(call)
            }
        }
        .background(.quaternary.opacity(0.15))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func toolDetailRow(_ call: ToolCallInfo) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(timeString(call.startTime))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)

                Text(call.name)
                    .font(.system(size: 11, weight: .medium, design: .monospaced))

                Spacer()

                statusIcon(call.status)
                Text(call.status == .running ? "running" : "done")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            if let input = call.toolInput, !input.isEmpty {
                Text("args: \(input)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(2)
                    .padding(.leading, 60)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    // MARK: - Helpers

    @ViewBuilder
    private func statusIcon(_ status: ToolStatus) -> some View {
        switch status {
        case .running:
            ProgressView()
                .scaleEffect(0.5)
                .frame(width: 12, height: 12)
        case .completed:
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11))
                .foregroundStyle(.green)
        }
    }

    private func timeString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}
