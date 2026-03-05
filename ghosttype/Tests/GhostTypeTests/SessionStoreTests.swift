import Testing
import Foundation
@testable import GhostTypeLib

/// Creates a SessionStore backed by a unique temp directory.
private func makeTempStore() -> (SessionStore, URL) {
    let base = FileManager.default.temporaryDirectory
        .appendingPathComponent("ghosttype-tests-\(UUID().uuidString)")
    return (SessionStore(baseDirectory: base), base)
}

/// Builds a minimal valid session for testing.
private func makeSession(
    id: String = UUID().uuidString,
    title: String = "Test Session",
    messageCount: Int = 2
) -> Session {
    var messages: [SessionMessage] = []
    let now = Date()
    for i in 0..<messageCount {
        messages.append(SessionMessage(
            id: "m\(i)",
            role: i % 2 == 0 ? "user" : "assistant",
            content: "Message \(i)",
            timestamp: now.addingTimeInterval(Double(i)),
            context: i == 0 ? "some context" : nil,
            screenshotFilename: nil
        ))
    }
    return Session(
        id: id,
        title: title,
        createdAt: now,
        updatedAt: now.addingTimeInterval(Double(messageCount)),
        mode: "chat",
        agentId: "general",
        modelId: "claude-opus",
        messages: messages
    )
}

private func cleanup(_ url: URL) {
    try? FileManager.default.removeItem(at: url)
}

// MARK: - Save & Load Round-Trip

@Test func saveAndLoadSessionRoundTrip() throws {
    let (store, base) = makeTempStore()
    defer { cleanup(base) }

    let session = makeSession(id: "s1", title: "Round trip test")
    try store.saveSession(session)

    let loaded = store.loadSession(id: "s1")
    #expect(loaded != nil)
    #expect(loaded?.id == "s1")
    #expect(loaded?.title == "Round trip test")
    #expect(loaded?.messages.count == 2)
    #expect(loaded?.messages[0].role == "user")
    #expect(loaded?.messages[1].role == "assistant")
    #expect(loaded?.agentId == "general")
    #expect(loaded?.modelId == "claude-opus")
}

@Test func saveSessionCreatesDirectories() throws {
    let (store, base) = makeTempStore()
    defer { cleanup(base) }

    let session = makeSession()
    try store.saveSession(session)

    let sessionsDir = base
    #expect(FileManager.default.fileExists(atPath: sessionsDir.path))

    let screenshotsDir = base.appendingPathComponent("screenshots")
    #expect(FileManager.default.fileExists(atPath: screenshotsDir.path))
}

@Test func saveSessionOverwritesExisting() throws {
    let (store, base) = makeTempStore()
    defer { cleanup(base) }

    let original = makeSession(id: "s1", title: "Original")
    try store.saveSession(original)

    let updated = Session(
        id: "s1",
        title: "Updated",
        createdAt: original.createdAt,
        updatedAt: Date(),
        mode: "chat",
        agentId: nil,
        modelId: "claude-3",
        messages: original.messages
    )
    try store.saveSession(updated)

    let loaded = store.loadSession(id: "s1")
    #expect(loaded?.title == "Updated")
}

// MARK: - Load Sessions (List)

@Test func loadSessionsReturnsNewestFirst() throws {
    let (store, base) = makeTempStore()
    defer { cleanup(base) }

    let now = Date()
    let older = Session(
        id: "old", title: "Older",
        createdAt: now.addingTimeInterval(-100),
        updatedAt: now.addingTimeInterval(-100),
        mode: "draft", agentId: nil, modelId: "m1",
        messages: []
    )
    let newer = Session(
        id: "new", title: "Newer",
        createdAt: now,
        updatedAt: now,
        mode: "chat", agentId: nil, modelId: "m1",
        messages: []
    )

    try store.saveSession(older)
    try store.saveSession(newer)

    let all = store.loadSessions()
    #expect(all.count == 2)
    #expect(all[0].id == "new")
    #expect(all[1].id == "old")
}

@Test func loadSessionsEmptyDirectory() {
    let (store, base) = makeTempStore()
    defer { cleanup(base) }

    let sessions = store.loadSessions()
    #expect(sessions.isEmpty)
}

@Test func loadSessionsSkipsCorruptJSON() throws {
    let (store, base) = makeTempStore()
    defer { cleanup(base) }

    // Save a valid session
    let valid = makeSession(id: "valid")
    try store.saveSession(valid)

    // Write corrupt JSON directly
    let corruptPath = base.appendingPathComponent("corrupt.json")
    try "{ not valid json!!".write(to: corruptPath, atomically: true, encoding: .utf8)

    let sessions = store.loadSessions()
    #expect(sessions.count == 1)
    #expect(sessions[0].id == "valid")
}

@Test func loadSessionsSkipsNonJSONFiles() throws {
    let (store, base) = makeTempStore()
    defer { cleanup(base) }

    let session = makeSession(id: "s1")
    try store.saveSession(session)

    // Create a non-JSON file in the directory
    let txtPath = base.appendingPathComponent("readme.txt")
    try "hello".write(to: txtPath, atomically: true, encoding: .utf8)

    let sessions = store.loadSessions()
    #expect(sessions.count == 1)
}

// MARK: - Delete

@Test func deleteSessionRemovesFile() throws {
    let (store, base) = makeTempStore()
    defer { cleanup(base) }

    let session = makeSession(id: "to-delete")
    try store.saveSession(session)

    #expect(store.loadSession(id: "to-delete") != nil)

    try store.deleteSession(id: "to-delete")

    #expect(store.loadSession(id: "to-delete") == nil)
    #expect(store.loadSessions().isEmpty)
}

@Test func deleteSessionRemovesScreenshots() throws {
    let (store, base) = makeTempStore()
    defer { cleanup(base) }

    let session = Session(
        id: "s1", title: "With screenshot",
        createdAt: Date(), updatedAt: Date(),
        mode: "chat", agentId: nil, modelId: "m1",
        messages: [
            SessionMessage(id: "m1", role: "user", content: "Hi",
                          timestamp: Date(), context: nil,
                          screenshotFilename: "s1_0.jpg"),
        ]
    )
    try store.saveSession(session)

    // Write a fake screenshot file
    let screenshotData = Data([0xFF, 0xD8, 0xFF, 0xE0]) // JPEG magic bytes
    try store.saveScreenshot(data: screenshotData, filename: "s1_0.jpg")

    let screenshotPath = store.screenshotURL(filename: "s1_0.jpg")
    #expect(FileManager.default.fileExists(atPath: screenshotPath.path))

    try store.deleteSession(id: "s1")

    #expect(!FileManager.default.fileExists(atPath: screenshotPath.path))
}

@Test func deleteNonexistentSessionDoesNotThrow() throws {
    let (store, base) = makeTempStore()
    defer { cleanup(base) }

    // Should not throw
    try store.deleteSession(id: "nonexistent")
}

// MARK: - Screenshots

@Test func saveScreenshotWritesFile() throws {
    let (store, base) = makeTempStore()
    defer { cleanup(base) }

    let data = Data([0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10])
    try store.saveScreenshot(data: data, filename: "test_0.jpg")

    let url = store.screenshotURL(filename: "test_0.jpg")
    #expect(FileManager.default.fileExists(atPath: url.path))

    let loaded = try Data(contentsOf: url)
    #expect(loaded == data)
}

@Test func screenshotURLReturnsCorrectPath() {
    let (store, base) = makeTempStore()
    defer { cleanup(base) }

    let url = store.screenshotURL(filename: "abc_0.jpg")
    #expect(url.lastPathComponent == "abc_0.jpg")
    #expect(url.deletingLastPathComponent().lastPathComponent == "screenshots")
}

// MARK: - Load Single Session

@Test func loadSessionReturnsNilForMissing() {
    let (store, base) = makeTempStore()
    defer { cleanup(base) }

    #expect(store.loadSession(id: "nonexistent") == nil)
}
