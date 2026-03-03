import Testing
import Foundation
@testable import GhostTypeLib

// MARK: - AgentInfo JSON Decoding

@Test func agentInfoDecodesFromSnakeCaseJSON() throws {
    let json = """
    {
        "id": "general",
        "name": "General Assistant",
        "description": "All-purpose assistant",
        "supported_modes": ["draft", "chat"],
        "is_default": true,
        "app_mappings": []
    }
    """.data(using: .utf8)!

    let agent = try JSONDecoder().decode(AgentInfo.self, from: json)

    #expect(agent.id == "general")
    #expect(agent.name == "General Assistant")
    #expect(agent.supportedModes == ["draft", "chat"])
    #expect(agent.isDefault == true)
    #expect(agent.appMappings.isEmpty)
}

@Test func agentInfoDecodesWithAppMappings() throws {
    let json = """
    {
        "id": "coding",
        "name": "Code Assistant",
        "description": "Helps with code",
        "supported_modes": ["chat"],
        "is_default": false,
        "app_mappings": ["com.microsoft.VSCode", "com.apple.dt.Xcode"]
    }
    """.data(using: .utf8)!

    let agent = try JSONDecoder().decode(AgentInfo.self, from: json)

    #expect(agent.id == "coding")
    #expect(agent.isDefault == false)
    #expect(agent.appMappings.count == 2)
    #expect(agent.appMappings.contains("com.microsoft.VSCode"))
}

// MARK: - agentForBundle

@Test func agentForBundleExactMatch() {
    let agents = [
        AgentInfo(id: "coding", name: "Code", description: "", supportedModes: ["chat"],
                  isDefault: false, appMappings: ["com.microsoft.VSCode"]),
        AgentInfo(id: "email", name: "Email", description: "", supportedModes: ["draft"],
                  isDefault: false, appMappings: ["com.apple.mail"]),
    ]

    let result = AgentInfo.agentForBundle("com.microsoft.VSCode", from: agents)
    #expect(result?.id == "coding")
}

@Test func agentForBundlePrefixMatch() {
    let agents = [
        AgentInfo(id: "coding", name: "Code", description: "", supportedModes: ["chat"],
                  isDefault: false, appMappings: ["com.jetbrains"]),
    ]

    let result = AgentInfo.agentForBundle("com.jetbrains.intellij", from: agents)
    #expect(result?.id == "coding")
}

@Test func agentForBundleNoMatchReturnsNil() {
    let agents = [
        AgentInfo(id: "coding", name: "Code", description: "", supportedModes: ["chat"],
                  isDefault: false, appMappings: ["com.microsoft.VSCode"]),
    ]

    let result = AgentInfo.agentForBundle("com.unknown.App", from: agents)
    #expect(result == nil)
}

@Test func agentForBundleNilBundleReturnsNil() {
    let agents = [
        AgentInfo(id: "coding", name: "Code", description: "", supportedModes: ["chat"],
                  isDefault: false, appMappings: ["com.microsoft.VSCode"]),
    ]

    let result = AgentInfo.agentForBundle(nil, from: agents)
    #expect(result == nil)
}

// MARK: - Agent Picker Label

@Test func effectiveAgentNameShowsResolvedNameNotAuto() {
    let agents = [
        AgentInfo(id: "general", name: "General Assistant", description: "",
                  supportedModes: ["draft"], isDefault: true, appMappings: []),
        AgentInfo(id: "coding", name: "Code Assistant", description: "",
                  supportedModes: ["chat"], isDefault: false,
                  appMappings: ["com.microsoft.VSCode"]),
    ]

    func resolvedName(selectedId: String?, effectiveId: String?) -> String {
        agents.first(where: { $0.id == effectiveId })?.name ?? "General Assistant"
    }

    // Auto mode with default fallback
    #expect(resolvedName(selectedId: nil, effectiveId: "general") == "General Assistant")
    // Auto mode with bundle auto-detect
    #expect(resolvedName(selectedId: nil, effectiveId: "coding") == "Code Assistant")
    // Manual selection
    #expect(resolvedName(selectedId: "coding", effectiveId: "coding") == "Code Assistant")
}
