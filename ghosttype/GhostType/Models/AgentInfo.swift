import Foundation

/// Agent definition returned from the backend's GET /agents endpoint.
struct AgentInfo: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let description: String
    let supportedModes: [String]
    let isDefault: Bool
    let appMappings: [String]

    enum CodingKeys: String, CodingKey {
        case id, name, description
        case supportedModes = "supported_modes"
        case isDefault = "is_default"
        case appMappings = "app_mappings"
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
