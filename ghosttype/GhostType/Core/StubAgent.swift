import Foundation

/// Stub agent that simulates streaming AI responses.
/// Replace with WebSocketClient calls to the real Strands Agent backend.
enum StubAgent {
    /// Simulates a streaming text generation response.
    /// Calls `onToken` with word-by-word chunks, then `completion` when done.
    static func generate(
        prompt: String,
        context: String,
        onToken: @escaping (String) -> Void,
        completion: @escaping () -> Void
    ) {
        let response = buildStubResponse(prompt: prompt, context: context)
        let words = response.split(separator: " ", omittingEmptySubsequences: false)

        // Stream words with a small delay to simulate real streaming
        let queue = DispatchQueue(label: "com.ghosttype.stub-agent")
        queue.async {
            for (index, word) in words.enumerated() {
                let chunk = (index == 0) ? String(word) : " " + String(word)
                let delay = Double.random(in: 0.02...0.06)
                Thread.sleep(forTimeInterval: delay)
                onToken(chunk)
            }
            completion()
        }
    }

    private static func buildStubResponse(prompt: String, context: String) -> String {
        let lower = prompt.lowercased()

        if lower.contains("email") {
            return """
            Hi,

            Thank you for reaching out. I wanted to follow up on our earlier conversation and share a few thoughts.

            First, I think the proposed timeline works well for our team. We can commit to delivering the initial draft by end of next week.

            Second, regarding the budget concerns you raised — I've reviewed the numbers and believe we can optimize costs by consolidating two of the vendor contracts.

            Would you be available for a quick 15-minute call tomorrow to discuss the details?

            Best regards
            """
        }

        if lower.contains("fix") || lower.contains("grammar") {
            if !context.isEmpty {
                return context
                    .replacingOccurrences(of: "teh", with: "the")
                    .replacingOccurrences(of: "recieve", with: "receive")
                    .replacingOccurrences(of: "definately", with: "definitely")
                    .replacingOccurrences(of: "occured", with: "occurred")
                    .replacingOccurrences(of: "seperate", with: "separate")
            }
            return "The corrected text would appear here. Select some text before invoking GhostType to provide context."
        }

        if lower.contains("rewrite") || lower.contains("professional") || lower.contains("friendly") || lower.contains("casual") {
            if !context.isEmpty {
                return "I'd like to share an update on the project status. Our team has made significant progress this quarter, and we're on track to meet our milestones. I'll send a detailed breakdown in our next status report."
            }
            return "Please select some text to rewrite. GhostType works best when it has context to work with."
        }

        if lower.contains("shorter") || lower.contains("concise") {
            return "Here's a concise version of the text. Select content before using GhostType for better results."
        }

        if lower.contains("expand") {
            return "The expanded version would elaborate on the key points with additional context, examples, and supporting details to make the writing more comprehensive and informative."
        }

        // Default response
        return """
        Thank you for your prompt! In production, this response would come from the AI model via the Strands Agent backend.

        GhostType currently supports these modes:
        - Generate: Create new text from a prompt
        - Rewrite: Transform selected text
        - Fix Grammar: Correct spelling and grammar
        - Translate: Convert text to another language

        Try selecting some text in any app, then press Ctrl+K to use GhostType with context.
        """
    }
}
