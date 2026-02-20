import Foundation

/// HTTP client for communicating with a GhostType AgentCore backend.
/// Unlike WebSocketClient, this uses synchronous HTTP POST to /invocations
/// and receives the full response at once (no token streaming).
class AgentCoreClient: ObservableObject {
    @Published var isAvailable = false

    var onComplete: ((String) -> Void)?
    var onError: ((String) -> Void)?

    private var currentTask: URLSessionDataTask?

    // MARK: - Health Check

    /// Checks if the AgentCore endpoint is reachable via /ping.
    func checkHealth(endpoint: String, completion: ((Bool) -> Void)? = nil) {
        let pingURL: URL?

        if endpoint.hasPrefix("http://") || endpoint.hasPrefix("https://") {
            // HTTP endpoint — use /ping path
            pingURL = URL(string: endpoint)?.deletingLastPathComponent().appendingPathComponent("ping")
            // If endpoint is just base URL (no path component to delete), try appending directly
            ?? URL(string: endpoint.hasSuffix("/") ? "\(endpoint)ping" : "\(endpoint)/ping")
        } else {
            // ARN or other format — not directly pingable via HTTP
            // Mark as available optimistically (AgentCore manages health internally)
            DispatchQueue.main.async { [weak self] in
                self?.isAvailable = !endpoint.isEmpty
                completion?(!endpoint.isEmpty)
            }
            return
        }

        guard let url = pingURL else {
            DispatchQueue.main.async { [weak self] in
                self?.isAvailable = false
                completion?(false)
            }
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        URLSession.shared.dataTask(with: request) { [weak self] _, response, _ in
            let ok = (response as? HTTPURLResponse)?.statusCode == 200
            DispatchQueue.main.async {
                self?.isAvailable = ok
                completion?(ok)
            }
        }.resume()
    }

    // MARK: - Generate

    /// Sends a generation request to the AgentCore /invocations endpoint.
    /// The response arrives as a single JSON payload (no streaming).
    func generate(
        endpoint: String,
        prompt: String,
        context: String = "",
        mode: String = "generate",
        modeType: String? = nil,
        config: [String: String]? = nil,
        screenshot: String? = nil
    ) {
        let invocationsURL: URL?

        if endpoint.hasPrefix("http://") || endpoint.hasPrefix("https://") {
            // HTTP endpoint — POST to /invocations
            invocationsURL = URL(string: endpoint.hasSuffix("/invocations") ? endpoint
                                 : (endpoint.hasSuffix("/") ? "\(endpoint)invocations" : "\(endpoint)/invocations"))
        } else {
            // ARN-based endpoint — would need AWS SDK invoke
            // For now, treat the endpoint as a direct URL
            NSLog("[GhostType][AgentCore] ARN endpoints not yet supported: %@", endpoint)
            DispatchQueue.main.async { [weak self] in
                self?.onError?("ARN-based AgentCore endpoints are not yet supported. Use an HTTP URL.")
            }
            return
        }

        guard let url = invocationsURL else {
            NSLog("[GhostType][AgentCore] Invalid endpoint URL: %@", endpoint)
            DispatchQueue.main.async { [weak self] in
                self?.onError?("Invalid AgentCore endpoint URL")
            }
            return
        }

        // Build request body (same format as WebSocket protocol)
        var body: [String: Any] = [
            "prompt": prompt,
            "context": context,
            "mode": mode,
        ]

        if let modeType = modeType {
            body["mode_type"] = modeType
        }

        if let config = config {
            body["config"] = config
        }

        if let screenshot = screenshot {
            body["screenshot"] = screenshot
        }

        guard let jsonData = try? JSONSerialization.data(withJSONObject: body) else {
            NSLog("[GhostType][AgentCore] Failed to serialize request body")
            DispatchQueue.main.async { [weak self] in
                self?.onError?("Failed to serialize request")
            }
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = jsonData
        request.timeoutInterval = 120 // Match backend GENERATION_TIMEOUT

        NSLog("[GhostType][AgentCore] Sending POST to %@: mode=%@, prompt_len=%d",
              url.absoluteString, mode, prompt.count)

        currentTask = URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            if let error = error {
                NSLog("[GhostType][AgentCore] Request error: %@", error.localizedDescription)
                DispatchQueue.main.async {
                    self?.onError?("AgentCore request failed: \(error.localizedDescription)")
                }
                return
            }

            guard let data = data else {
                NSLog("[GhostType][AgentCore] Empty response")
                DispatchQueue.main.async {
                    self?.onError?("Empty response from AgentCore")
                }
                return
            }

            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            NSLog("[GhostType][AgentCore] Response: status=%d, bytes=%d", statusCode, data.count)

            guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                NSLog("[GhostType][AgentCore] Failed to parse response JSON")
                DispatchQueue.main.async {
                    self?.onError?("Invalid response from AgentCore")
                }
                return
            }

            let type = json["type"] as? String ?? ""
            let content = json["content"] as? String ?? json["result"] as? String ?? ""

            DispatchQueue.main.async {
                if type == "error" || statusCode >= 400 {
                    let errorMsg = json["error"] as? String ?? content
                    NSLog("[GhostType][AgentCore] Server error: %@", errorMsg)
                    self?.onError?(errorMsg.isEmpty ? "Unknown AgentCore error" : errorMsg)
                } else {
                    NSLog("[GhostType][AgentCore] Generation complete, response_len=%d", content.count)
                    self?.onComplete?(content)
                }
            }
        }
        currentTask?.resume()
    }

    // MARK: - Cancel

    /// Cancels the in-flight HTTP request (best-effort — server continues processing).
    func cancel() {
        NSLog("[GhostType][AgentCore] Cancelling in-flight request")
        currentTask?.cancel()
        currentTask = nil
    }
}
