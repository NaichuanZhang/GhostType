import Foundation

/// Fetches available agents from the backend's GET /agents endpoint.
enum AgentService {
    /// Response shape from GET /agents.
    private struct AgentsResponse: Codable {
        let agents: [AgentInfo]
        let defaultAgentId: String

        enum CodingKeys: String, CodingKey {
            case agents
            case defaultAgentId = "default_agent_id"
        }
    }

    /// Fetches available agents from the backend.
    /// Calls completion on main queue with (agents, defaultAgentId) or empty on failure.
    static func fetchAgents(
        host: String = "127.0.0.1",
        port: Int = 8420,
        completion: @escaping ([AgentInfo], String?) -> Void
    ) {
        guard let url = URL(string: "http://\(host):\(port)/agents") else {
            NSLog("[GhostType][AgentService] Invalid agents URL")
            DispatchQueue.main.async { completion([], nil) }
            return
        }

        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        URLSession.shared.dataTask(with: request) { data, response, error in
            guard let data,
                  (response as? HTTPURLResponse)?.statusCode == 200 else {
                let errMsg = error?.localizedDescription ?? "unknown"
                NSLog("[GhostType][AgentService] Failed to fetch agents: %@", errMsg)
                DispatchQueue.main.async { completion([], nil) }
                return
            }

            do {
                let decoder = JSONDecoder()
                let resp = try decoder.decode(AgentsResponse.self, from: data)
                NSLog("[GhostType][AgentService] Loaded %d agent(s), default=%@",
                      resp.agents.count, resp.defaultAgentId)
                DispatchQueue.main.async {
                    completion(resp.agents, resp.defaultAgentId)
                }
            } catch {
                NSLog("[GhostType][AgentService] JSON decode error: %@", error.localizedDescription)
                DispatchQueue.main.async { completion([], nil) }
            }
        }.resume()
    }
}
