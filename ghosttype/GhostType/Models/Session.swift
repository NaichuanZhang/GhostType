import Foundation

struct SessionMessage: Codable, Identifiable, Equatable {
    let id: String
    let role: String
    let content: String
    let timestamp: Date
    let context: String?
    let screenshotFilename: String?

    enum CodingKeys: String, CodingKey {
        case id, role, content, timestamp, context
        case screenshotFilename = "screenshot_filename"
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(role, forKey: .role)
        try container.encode(content, forKey: .content)
        try container.encode(timestamp, forKey: .timestamp)
        try container.encodeIfPresent(context, forKey: .context)
        try container.encodeIfPresent(screenshotFilename, forKey: .screenshotFilename)
    }
}

struct Session: Codable, Identifiable, Equatable {
    let id: String
    let title: String
    let createdAt: Date
    let updatedAt: Date
    let mode: String
    let agentId: String?
    let modelId: String
    let messages: [SessionMessage]

    enum CodingKeys: String, CodingKey {
        case id, title, mode, messages
        case createdAt = "created_at"
        case updatedAt = "updated_at"
        case agentId = "agent_id"
        case modelId = "model_id"
    }

    /// Generates a display title from the first user message.
    /// Truncates to 60 characters with ellipsis, uses first line only.
    static func generateTitle(from message: String) -> String {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return "Untitled Session" }

        let firstLine = trimmed.components(separatedBy: .newlines).first ?? trimmed
        let clean = firstLine.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return "Untitled Session" }

        if clean.count <= 60 {
            return clean
        }
        return String(clean.prefix(60)) + "..."
    }
}
