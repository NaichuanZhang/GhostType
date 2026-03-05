import Testing
import Foundation
@testable import GhostTypeLib

// MARK: - SessionMessage

@Test func sessionMessageRoundTrip() throws {
    let msg = SessionMessage(
        id: "msg-1",
        role: "user",
        content: "Hello world",
        timestamp: Date(timeIntervalSince1970: 1709500000),
        context: "selected text",
        screenshotFilename: "abc_0.jpg"
    )

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = .sortedKeys
    let data = try encoder.encode(msg)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode(SessionMessage.self, from: data)

    #expect(decoded.id == "msg-1")
    #expect(decoded.role == "user")
    #expect(decoded.content == "Hello world")
    #expect(decoded.context == "selected text")
    #expect(decoded.screenshotFilename == "abc_0.jpg")
    #expect(decoded.timestamp == Date(timeIntervalSince1970: 1709500000))
}

@Test func sessionMessageOmitsNilOptionals() throws {
    let msg = SessionMessage(
        id: "msg-2",
        role: "assistant",
        content: "Response",
        timestamp: Date(timeIntervalSince1970: 1709500000),
        context: nil,
        screenshotFilename: nil
    )

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(msg)
    let json = String(data: data, encoding: .utf8)!

    #expect(!json.contains("context"))
    #expect(!json.contains("screenshot_filename"))
}

@Test func sessionMessageDecodesSnakeCaseKeys() throws {
    let json = """
    {
        "id": "m1",
        "role": "user",
        "content": "test",
        "timestamp": "2024-03-03T10:00:00Z",
        "screenshot_filename": "shot.jpg"
    }
    """

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let msg = try decoder.decode(SessionMessage.self, from: Data(json.utf8))

    #expect(msg.screenshotFilename == "shot.jpg")
    #expect(msg.context == nil)
}

// MARK: - Session

@Test func sessionRoundTrip() throws {
    let messages = [
        SessionMessage(id: "m1", role: "user", content: "Hi", timestamp: Date(timeIntervalSince1970: 1709500000), context: nil, screenshotFilename: nil),
        SessionMessage(id: "m2", role: "assistant", content: "Hello!", timestamp: Date(timeIntervalSince1970: 1709500001), context: nil, screenshotFilename: nil),
    ]
    let session = Session(
        id: "sess-1",
        title: "Hi",
        createdAt: Date(timeIntervalSince1970: 1709500000),
        updatedAt: Date(timeIntervalSince1970: 1709500001),
        mode: "chat",
        agentId: "general",
        modelId: "claude-opus",
        messages: messages
    )

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(session)

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let decoded = try decoder.decode(Session.self, from: data)

    #expect(decoded.id == "sess-1")
    #expect(decoded.title == "Hi")
    #expect(decoded.mode == "chat")
    #expect(decoded.agentId == "general")
    #expect(decoded.modelId == "claude-opus")
    #expect(decoded.messages.count == 2)
    #expect(decoded.messages[0].role == "user")
    #expect(decoded.messages[1].role == "assistant")
}

@Test func sessionDecodesSnakeCaseKeys() throws {
    let json = """
    {
        "id": "s1",
        "title": "Test",
        "created_at": "2024-03-03T10:00:00Z",
        "updated_at": "2024-03-03T10:01:00Z",
        "mode": "draft",
        "agent_id": "coding",
        "model_id": "claude-3",
        "messages": []
    }
    """

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let session = try decoder.decode(Session.self, from: Data(json.utf8))

    #expect(session.agentId == "coding")
    #expect(session.modelId == "claude-3")
    #expect(session.messages.isEmpty)
}

@Test func sessionNilAgentId() throws {
    let json = """
    {
        "id": "s1",
        "title": "Test",
        "created_at": "2024-03-03T10:00:00Z",
        "updated_at": "2024-03-03T10:01:00Z",
        "mode": "draft",
        "model_id": "claude-3",
        "messages": []
    }
    """

    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    let session = try decoder.decode(Session.self, from: Data(json.utf8))

    #expect(session.agentId == nil)
}

// MARK: - Title Generation

@Test func sessionTitleFromShortMessage() {
    let title = Session.generateTitle(from: "Fix the bug")
    #expect(title == "Fix the bug")
}

@Test func sessionTitleTruncatesAt60Chars() {
    let longMessage = String(repeating: "a", count: 100)
    let title = Session.generateTitle(from: longMessage)
    #expect(title.count == 63) // 60 chars + "..."
    #expect(title.hasSuffix("..."))
}

@Test func sessionTitleExactly60Chars() {
    let msg = String(repeating: "b", count: 60)
    let title = Session.generateTitle(from: msg)
    #expect(title == msg)
    #expect(title.count == 60)
}

@Test func sessionTitleStripsLeadingWhitespace() {
    let title = Session.generateTitle(from: "  \n  Hello world  ")
    #expect(title == "Hello world")
}

@Test func sessionTitleEmptyMessage() {
    let title = Session.generateTitle(from: "")
    #expect(title == "Untitled Session")
}

@Test func sessionTitleWhitespaceOnlyMessage() {
    let title = Session.generateTitle(from: "   \n\t  ")
    #expect(title == "Untitled Session")
}

@Test func sessionTitleFirstLineOnly() {
    let title = Session.generateTitle(from: "First line\nSecond line\nThird line")
    #expect(title == "First line")
}
