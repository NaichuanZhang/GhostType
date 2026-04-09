import Foundation

/// Determines the generation mode based on prompt content and context.
enum ModeDetector {
    /// Returns the generation mode string: "generate", "rewrite", "fix", or "translate".
    static func detect(prompt: String, hasContext: Bool) -> String {
        let lower = prompt.lowercased()

        if lower.contains("fix") || lower.contains("grammar") || lower.contains("spelling") {
            return "fix"
        }
        if lower.contains("translat") {
            return "translate"
        }
        if hasContext && (lower.contains("rewrite") || lower.contains("rephrase") ||
                         lower.contains("shorter") || lower.contains("expand") ||
                         lower.contains("professional") || lower.contains("friendly") ||
                         lower.contains("casual") || lower.contains("formal") ||
                         lower.contains("concise") || lower.contains("tone")) {
            return "rewrite"
        }
        return "generate"
    }
}
