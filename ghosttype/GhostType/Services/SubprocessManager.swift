import Foundation

/// Events emitted by the Python subprocess (parsed from stdout JSON lines).
enum SubprocessEvent {
    case token(String)
    case toolStart(name: String, id: String)
    case toolDone(name: String, id: String, input: String?)
    case done(String)
    case error(String)
    case cancelled
    case conversationReset
    case historyRestored
    case agents([AgentInfo], defaultAgentId: String?)
}

/// Requests sent to the Python subprocess (serialized as JSON lines to stdin).
struct SubprocessRequest: Encodable {
    let type: String
    var prompt: String?
    var context: String?
    var mode: String?
    var modeType: String?
    var agent: String?
    var screenshot: String?
    var browserContext: String?
    var config: [String: String]?
    var messages: [[String: String]]?

    enum CodingKeys: String, CodingKey {
        case type, prompt, context, mode, agent, screenshot, config, messages
        case modeType = "mode_type"
        case browserContext = "browser_context"
    }
}

/// Manages a Python subprocess communicating via stdin/stdout JSON lines.
/// Replaces WebSocketClient with a simpler, more reliable architecture.
class SubprocessManager: ObservableObject {
    private var process: Process?
    private var stdinPipe: Pipe?
    private var stdoutPipe: Pipe?
    private var stderrPipe: Pipe?
    private var readTask: Task<Void, Never>?

    @Published var isRunning = false

    /// Continuation for the current event stream consumer.
    private var eventContinuation: AsyncThrowingStream<SubprocessEvent, Error>.Continuation?

    /// Path to the Python executable inside the backend venv.
    private let pythonPath: String
    /// Path to stdio_server.py.
    private let serverPath: String

    init(backendDir: String? = nil) {
        let base = backendDir ?? {
            // Resolve relative to the app bundle or working directory
            let candidates = [
                Bundle.main.bundlePath + "/../../../backend",
                FileManager.default.currentDirectoryPath + "/backend",
                NSString("~/personal/cursor/ghosttype/backend").expandingTildeInPath,
            ]
            return candidates.first { FileManager.default.fileExists(atPath: $0 + "/stdio_server.py") }
                ?? candidates.last!
        }()

        self.pythonPath = base + "/.venv/bin/python3"
        self.serverPath = base + "/stdio_server.py"
    }

    // MARK: - Lifecycle

    func start() {
        guard process == nil else { return }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: pythonPath)
        proc.arguments = ["-u", serverPath]  // -u for unbuffered stdout
        proc.currentDirectoryURL = URL(fileURLWithPath: serverPath).deletingLastPathComponent()

        // Set up environment (inherit current + ensure PATH)
        var env = ProcessInfo.processInfo.environment
        env["PYTHONUNBUFFERED"] = "1"
        proc.environment = env

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        proc.standardInput = stdin
        proc.standardOutput = stdout
        proc.standardError = stderr

        self.stdinPipe = stdin
        self.stdoutPipe = stdout
        self.stderrPipe = stderr
        self.process = proc

        // Forward stderr to system log
        stderr.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            for line in text.split(separator: "\n") {
                NSLog("[GhostType][Python] %@", String(line))
            }
        }

        proc.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                self?.isRunning = false
                self?.eventContinuation?.finish()
                NSLog("[GhostType][Subprocess] Process terminated (exit code: %d)", proc.terminationStatus)
            }
        }

        do {
            try proc.run()
            DispatchQueue.main.async { [weak self] in
                self?.isRunning = true
            }
            NSLog("[GhostType][Subprocess] Started (PID: %d)", proc.processIdentifier)
        } catch {
            NSLog("[GhostType][Subprocess] Failed to start: %@", error.localizedDescription)
        }
    }

    func stop() {
        readTask?.cancel()
        readTask = nil
        eventContinuation?.finish()
        eventContinuation = nil

        stderrPipe?.fileHandleForReading.readabilityHandler = nil

        if let proc = process, proc.isRunning {
            proc.terminate()
            NSLog("[GhostType][Subprocess] Terminated")
        }
        process = nil
        stdinPipe = nil
        stdoutPipe = nil
        stderrPipe = nil
    }

    // MARK: - Send

    func send(_ request: SubprocessRequest) {
        guard let stdinPipe = stdinPipe else {
            NSLog("[GhostType][Subprocess] Cannot send — subprocess not running")
            return
        }

        do {
            let encoder = JSONEncoder()
            encoder.keyEncodingStrategy = .convertToSnakeCase
            var data = try encoder.encode(request)
            data.append(0x0A) // newline
            stdinPipe.fileHandleForWriting.write(data)
            NSLog("[GhostType][Subprocess] Sent: type=%@", request.type)
        } catch {
            NSLog("[GhostType][Subprocess] Failed to encode request: %@", error.localizedDescription)
        }
    }

    // MARK: - Receive

    /// Returns an async stream of events read from the subprocess stdout.
    /// Only one consumer can be active at a time.
    func events() -> AsyncThrowingStream<SubprocessEvent, Error> {
        // Cancel previous stream if any
        eventContinuation?.finish()

        return AsyncThrowingStream { continuation in
            self.eventContinuation = continuation

            continuation.onTermination = { @Sendable _ in
                // Clean up on cancellation
            }

            // Start reading stdout in a background task
            readTask?.cancel()
            readTask = Task.detached { [weak self] in
                guard let self = self, let stdout = self.stdoutPipe else {
                    continuation.finish()
                    return
                }

                let handle = stdout.fileHandleForReading

                while !Task.isCancelled {
                    let data = handle.availableData
                    guard !data.isEmpty else {
                        // EOF — process ended
                        continuation.finish()
                        return
                    }

                    guard let text = String(data: data, encoding: .utf8) else { continue }

                    // Process each line (may receive multiple lines in one read)
                    for line in text.split(separator: "\n") {
                        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { continue }

                        if let event = self.parseEvent(trimmed) {
                            continuation.yield(event)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Parsing

    private func parseEvent(_ jsonString: String) -> SubprocessEvent? {
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = json["type"] as? String else {
            NSLog("[GhostType][Subprocess] Failed to parse: %@", String(jsonString.prefix(200)))
            return nil
        }

        let content = json["content"] as? String ?? ""

        switch type {
        case "token":
            return .token(content)
        case "done":
            return .done(content)
        case "error":
            NSLog("[GhostType][Subprocess] Error: %@", content)
            return .error(content)
        case "cancelled":
            return .cancelled
        case "conversation_reset":
            return .conversationReset
        case "history_restored":
            return .historyRestored
        case "tool_start":
            let name = json["tool_name"] as? String ?? "unknown"
            let id = json["tool_id"] as? String ?? ""
            return .toolStart(name: name, id: id)
        case "tool_done":
            let name = json["tool_name"] as? String ?? "unknown"
            let id = json["tool_id"] as? String ?? ""
            let input = json["tool_input"] as? String
            return .toolDone(name: name, id: id, input: input)
        case "agents":
            let agentDicts = json["agents"] as? [[String: Any]] ?? []
            let defaultId = json["default_agent_id"] as? String
            let agents = agentDicts.compactMap { AgentInfo.fromDict($0) }
            return .agents(agents, defaultAgentId: defaultId)
        default:
            NSLog("[GhostType][Subprocess] Unknown event type: %@", type)
            return nil
        }
    }
}
