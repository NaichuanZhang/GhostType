import Foundation

/// Agent definition returned from the backend's GET /agents endpoint.
struct AgentInfo: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let description: String
    let tools: [String]
    let supportedModes: [String]
    let isDefault: Bool
    let appMappings: [String]

    enum CodingKeys: String, CodingKey {
        case id, name, description, tools
        case supportedModes = "supported_modes"
        case isDefault = "is_default"
        case appMappings = "app_mappings"
    }

    /// Creates an AgentInfo from a raw dictionary (used by SubprocessManager).
    static func fromDict(_ dict: [String: Any]) -> AgentInfo? {
        guard let id = dict["id"] as? String,
              let name = dict["name"] as? String else { return nil }
        return AgentInfo(
            id: id,
            name: name,
            description: dict["description"] as? String ?? "",
            tools: dict["tools"] as? [String] ?? [],
            supportedModes: dict["supported_modes"] as? [String] ?? ["draft", "chat"],
            isDefault: dict["is_default"] as? Bool ?? false,
            appMappings: dict["app_mappings"] as? [String] ?? []
        )
    }

    /// Returns the agent whose appMappings match the given bundle ID (exact or prefix match).
    static func agentForBundle(_ bundleID: String?, from agents: [AgentInfo]) -> AgentInfo? {
        guard let bundleID else { return nil }
        for agent in agents {
            for mapping in agent.appMappings {
                if bundleID == mapping || bundleID.hasPrefix(mapping + ".") {
                    return agent
                }
            }
        }
        return nil
    }
}
