import Foundation

/// Browser context data model — shared between AppState, tests, and subprocess communication.
/// The Chrome extension POSTs context to the backend's HTTP listener; the frontend
/// requests it via subprocess `get_browser_context` message.
enum BrowserContextService {
    /// Data shape for browser page context.
    struct BrowserContextData: Codable, Equatable {
        let url: String
        let title: String
        let content: String
        let selectedText: String
        let timestamp: Double

        enum CodingKeys: String, CodingKey {
            case url, title, content
            case selectedText = "selected_text"
            case timestamp
        }
    }
}
