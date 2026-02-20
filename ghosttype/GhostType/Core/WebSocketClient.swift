import Foundation

/// WebSocket client for communicating with the Strands Agent backend.
/// Handles streaming token delivery for real-time response display.
class WebSocketClient: ObservableObject {
    private var webSocket: URLSessionWebSocketTask?
    private let session = URLSession(configuration: .default)
    private let baseURL: String
    private let healthURL: String
    private var reconnectAttempt = 0
    private let maxReconnectAttempts = 5
    private var healthTimer: Timer?

    @Published var isConnected = false
    @Published var backendAvailable = false

    var onToken: ((String) -> Void)?
    var onComplete: ((String) -> Void)?
    var onError: ((String) -> Void)?
    var onCancelled: (() -> Void)?

    init(host: String = "127.0.0.1", port: Int = 8420) {
        self.baseURL = "ws://\(host):\(port)"
        self.healthURL = "http://\(host):\(port)/health"
    }

    // MARK: - Health Check

    /// Checks if the backend server is reachable via /health endpoint.
    func checkHealth(completion: ((Bool) -> Void)? = nil) {
        guard let url = URL(string: healthURL) else {
            completion?(false)
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 3

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            let ok = (response as? HTTPURLResponse)?.statusCode == 200
            DispatchQueue.main.async {
                self?.backendAvailable = ok
                completion?(ok)
            }
        }.resume()
    }

    /// Starts periodic health checks every `interval` seconds.
    func startHealthChecks(interval: TimeInterval = 10) {
        stopHealthChecks()
        // Initial check
        checkHealth()
        healthTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.checkHealth()
        }
    }

    func stopHealthChecks() {
        healthTimer?.invalidate()
        healthTimer = nil
    }

    // MARK: - Connection

    func connect() {
        guard let url = URL(string: "\(baseURL)/generate") else {
            NSLog("[GhostType][WS] Invalid WebSocket URL")
            return
        }

        NSLog("[GhostType][WS] Connecting to %@", url.absoluteString)
        webSocket = session.webSocketTask(with: url)
        webSocket?.resume()

        DispatchQueue.main.async { [weak self] in
            self?.isConnected = true
            self?.reconnectAttempt = 0
        }
        listenForMessages()
    }

    func disconnect() {
        NSLog("[GhostType][WS] Disconnecting")
        webSocket?.cancel(with: .goingAway, reason: nil)
        webSocket = nil
        DispatchQueue.main.async { [weak self] in
            self?.isConnected = false
        }
    }

    /// Ensures there's an active WebSocket connection, reconnecting if needed.
    func ensureConnected() {
        if webSocket == nil || !isConnected {
            connect()
        }
    }

    // MARK: - Send Request

    func generate(prompt: String, context: String = "", mode: String = "generate",
                   modeType: String? = nil, config: [String: String]? = nil,
                   screenshot: String? = nil) {
        ensureConnected()

        var request: [String: Any] = [
            "prompt": prompt,
            "context": context,
            "mode": mode
        ]

        if let modeType = modeType {
            request["mode_type"] = modeType
        }

        if let config = config {
            request["config"] = config
        }

        if let screenshot = screenshot {
            request["screenshot"] = screenshot
        }

        guard let data = try? JSONSerialization.data(withJSONObject: request),
              let jsonString = String(data: data, encoding: .utf8) else {
            NSLog("[GhostType][WS] Failed to serialize request")
            return
        }

        NSLog("[GhostType][WS] Sending generate: mode=%@, mode_type=%@, prompt_len=%d, context_len=%d, has_screenshot=%@",
              mode, modeType ?? "auto", prompt.count, context.count, screenshot != nil ? "YES" : "NO")

        webSocket?.send(.string(jsonString)) { [weak self] error in
            if let error = error {
                NSLog("[GhostType][WS] Send error: %@", error.localizedDescription)
                DispatchQueue.main.async {
                    self?.onError?("Send failed: \(error.localizedDescription)")
                }
            }
        }
    }

    /// Sends a new_conversation message to reset the backend agent's history.
    func sendNewConversation() {
        ensureConnected()

        let message: [String: Any] = ["type": "new_conversation"]
        guard let data = try? JSONSerialization.data(withJSONObject: message),
              let jsonString = String(data: data, encoding: .utf8) else { return }

        NSLog("[GhostType][WS] Sending new_conversation")
        webSocket?.send(.string(jsonString)) { _ in }
    }

    // MARK: - Cancel

    func cancelGeneration() {
        let cancel = ["type": "cancel"]
        if let data = try? JSONSerialization.data(withJSONObject: cancel),
           let jsonString = String(data: data, encoding: .utf8) {
            NSLog("[GhostType][WS] Sending cancel")
            webSocket?.send(.string(jsonString)) { _ in }
        }
    }

    // MARK: - Receive Messages

    private func listenForMessages() {
        webSocket?.receive { [weak self] result in
            switch result {
            case .success(let message):
                switch message {
                case .string(let text):
                    self?.handleMessage(text)
                case .data(let data):
                    if let text = String(data: data, encoding: .utf8) {
                        self?.handleMessage(text)
                    }
                @unknown default:
                    break
                }
                // Continue listening
                self?.listenForMessages()

            case .failure(let error):
                NSLog("[GhostType][WS] Connection error: %@", error.localizedDescription)
                DispatchQueue.main.async {
                    self?.isConnected = false
                    self?.onError?("Connection lost: \(error.localizedDescription)")
                }
                self?.attemptReconnect()
            }
        }
    }

    private func handleMessage(_ text: String) {
        guard let data = text.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            NSLog("[GhostType][WS] Failed to parse message: %@", text.prefix(200).description)
            return
        }

        let content = json["content"] as? String ?? ""

        DispatchQueue.main.async { [weak self] in
            switch type {
            case "token":
                self?.onToken?(content)
            case "done":
                self?.onComplete?(content)
            case "error":
                NSLog("[GhostType][WS] Server error: %@", content)
                self?.onError?(content)
            case "cancelled":
                NSLog("[GhostType][WS] Generation cancelled by server")
                self?.onCancelled?()
            case "conversation_reset":
                NSLog("[GhostType][WS] Conversation reset confirmed by server")
            default:
                NSLog("[GhostType][WS] Unknown message type: %@", type)
            }
        }
    }

    // MARK: - Reconnection

    private func attemptReconnect() {
        guard reconnectAttempt < maxReconnectAttempts else {
            NSLog("[GhostType][WS] Max reconnect attempts (%d) reached", maxReconnectAttempts)
            return
        }

        reconnectAttempt += 1
        let delay = min(pow(2.0, Double(reconnectAttempt)), 16.0) // Exponential backoff, max 16s
        NSLog("[GhostType][WS] Reconnecting in %.0fs (attempt %d/%d)",
              delay, reconnectAttempt, maxReconnectAttempts)

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self, !self.isConnected else { return }
            // Check if backend is reachable before reconnecting
            self.checkHealth { available in
                if available {
                    self.connect()
                } else {
                    NSLog("[GhostType][WS] Backend not available, skipping reconnect")
                    self.attemptReconnect()
                }
            }
        }
    }
}
