import Foundation

/// Fetches browser context from the backend's GET /browser-context endpoint.
enum BrowserContextService {
    /// Data returned by GET /browser-context when available.
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

    /// Response shape from GET /browser-context.
    private struct Response: Codable {
        let available: Bool
        let context: BrowserContextData?
    }

    /// Fetches the current browser context from the backend.
    /// Calls completion on main queue with the context data, or nil if unavailable.
    static func fetchBrowserContext(
        host: String = "127.0.0.1",
        port: Int = 8420,
        completion: @escaping (BrowserContextData?) -> Void
    ) {
        guard let url = URL(string: "http://\(host):\(port)/browser-context") else {
            NSLog("[GhostType][BrowserContext] Invalid URL")
            DispatchQueue.main.async { completion(nil) }
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data,
                  (response as? HTTPURLResponse)?.statusCode == 200 else {
                let errMsg = error?.localizedDescription ?? "unknown"
                NSLog("[GhostType][BrowserContext] Failed to fetch: %@", errMsg)
                DispatchQueue.main.async { completion(nil) }
                return
            }

            do {
                let resp = try JSONDecoder().decode(Response.self, from: data)
                NSLog("[GhostType][BrowserContext] available=%@, title=%@",
                      resp.available ? "true" : "false",
                      resp.context?.title ?? "n/a")
                DispatchQueue.main.async {
                    completion(resp.available ? resp.context : nil)
                }
            } catch {
                NSLog("[GhostType][BrowserContext] Decode error: %@", error.localizedDescription)
                DispatchQueue.main.async { completion(nil) }
            }
        }.resume()
    }
}
