import Testing
import Foundation
@testable import GhostTypeLib

// MARK: - SubprocessRequest encoding

@Test func subprocessRequestEncodesGenerateType() throws {
    let request = SubprocessRequest(
        type: "generate",
        prompt: "Hello",
        context: "some context",
        mode: "generate",
        modeType: "chat",
        agent: "general",
        config: ["provider": "bedrock"]
    )

    let encoder = JSONEncoder()
    let data = try encoder.encode(request)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

    #expect(json["type"] as? String == "generate")
    #expect(json["prompt"] as? String == "Hello")
    #expect(json["context"] as? String == "some context")
    #expect(json["mode"] as? String == "generate")
    #expect(json["mode_type"] as? String == "chat")
    #expect(json["agent"] as? String == "general")
}

@Test func subprocessRequestEncodesCancelType() throws {
    let request = SubprocessRequest(type: "cancel")

    let encoder = JSONEncoder()
    let data = try encoder.encode(request)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

    #expect(json["type"] as? String == "cancel")
    #expect(json["prompt"] == nil)
}

@Test func subprocessRequestEncodesNewConversationType() throws {
    let request = SubprocessRequest(type: "new_conversation")

    let encoder = JSONEncoder()
    let data = try encoder.encode(request)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

    #expect(json["type"] as? String == "new_conversation")
}

@Test func subprocessRequestEncodesRestoreHistory() throws {
    let request = SubprocessRequest(
        type: "restore_history",
        modeType: "draft",
        agent: "coding",
        config: ["provider": "bedrock"],
        messages: [["role": "user", "content": "hello"]]
    )

    let encoder = JSONEncoder()
    let data = try encoder.encode(request)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

    #expect(json["type"] as? String == "restore_history")
    #expect(json["mode_type"] as? String == "draft")
    #expect(json["agent"] as? String == "coding")
    let messages = json["messages"] as? [[String: String]]
    #expect(messages?.count == 1)
    #expect(messages?[0]["role"] == "user")
}

@Test func subprocessRequestOmitsNilFields() throws {
    let request = SubprocessRequest(type: "generate", prompt: "test")

    let encoder = JSONEncoder()
    let data = try encoder.encode(request)
    let json = try JSONSerialization.jsonObject(with: data) as! [String: Any]

    #expect(json["type"] as? String == "generate")
    #expect(json["prompt"] as? String == "test")
    // Nil fields should not be present
    #expect(json["screenshot"] == nil)
    #expect(json["browser_context"] == nil)
    #expect(json["agent"] == nil)
}

// MARK: - AgentInfo.fromDict

@Test func agentInfoFromDictParsesValidDict() {
    let dict: [String: Any] = [
        "id": "coding",
        "name": "Coding Agent",
        "description": "For code",
        "supported_modes": ["draft", "chat"],
        "is_default": false,
        "app_mappings": ["com.microsoft.VSCode"],
    ]

    let agent = AgentInfo.fromDict(dict)

    #expect(agent != nil)
    #expect(agent?.id == "coding")
    #expect(agent?.name == "Coding Agent")
    #expect(agent?.description == "For code")
    #expect(agent?.supportedModes == ["draft", "chat"])
    #expect(agent?.isDefault == false)
    #expect(agent?.appMappings == ["com.microsoft.VSCode"])
}

@Test func agentInfoFromDictReturnsNilForMissingId() {
    let dict: [String: Any] = ["name": "Test"]
    #expect(AgentInfo.fromDict(dict) == nil)
}

@Test func agentInfoFromDictReturnsNilForMissingName() {
    let dict: [String: Any] = ["id": "test"]
    #expect(AgentInfo.fromDict(dict) == nil)
}

@Test func agentInfoFromDictUsesDefaults() {
    let dict: [String: Any] = ["id": "test", "name": "Test"]

    let agent = AgentInfo.fromDict(dict)

    #expect(agent != nil)
    #expect(agent?.description == "")
    #expect(agent?.supportedModes == ["draft", "chat"])
    #expect(agent?.isDefault == false)
    #expect(agent?.appMappings == [])
}
