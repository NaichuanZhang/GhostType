import Foundation

/// Persists conversation sessions as JSON files in ~/.config/ghosttype/sessions/.
/// Screenshots are stored separately as .jpg files in a screenshots/ subdirectory.
class SessionStore {
    let baseDirectory: URL
    private let screenshotsDirectory: URL
    private let fileManager = FileManager.default

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    init(baseDirectory: URL? = nil) {
        let base = baseDirectory ?? {
            let path = NSString("~/.config/ghosttype/sessions").expandingTildeInPath
            return URL(fileURLWithPath: path)
        }()
        self.baseDirectory = base
        self.screenshotsDirectory = base.appendingPathComponent("screenshots")
    }

    // MARK: - Save

    func saveSession(_ session: Session) throws {
        ensureDirectories()
        let data = try encoder.encode(session)
        let url = sessionURL(id: session.id)
        try data.write(to: url, options: .atomic)
    }

    func saveScreenshot(data: Data, filename: String) throws {
        ensureDirectories()
        let url = screenshotURL(filename: filename)
        try data.write(to: url, options: .atomic)
    }

    // MARK: - Load

    /// Loads all sessions sorted by createdAt descending (newest first).
    /// Skips corrupt or unreadable files without failing.
    func loadSessions() -> [Session] {
        ensureDirectories()
        let contents: [URL]
        do {
            contents = try fileManager.contentsOfDirectory(
                at: baseDirectory,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            )
        } catch {
            NSLog("[GhostType][SessionStore] Failed to list sessions directory: %@", error.localizedDescription)
            return []
        }

        let sessions = contents
            .filter { $0.pathExtension == "json" }
            .compactMap { url -> Session? in
                do {
                    let data = try Data(contentsOf: url)
                    return try decoder.decode(Session.self, from: data)
                } catch {
                    NSLog("[GhostType][SessionStore] Skipping corrupt file %@: %@",
                          url.lastPathComponent, error.localizedDescription)
                    return nil
                }
            }
            .sorted { $0.createdAt > $1.createdAt }

        return sessions
    }

    func loadSession(id: String) -> Session? {
        let url = sessionURL(id: id)
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode(Session.self, from: data)
        } catch {
            NSLog("[GhostType][SessionStore] Failed to load session %@: %@",
                  id, error.localizedDescription)
            return nil
        }
    }

    // MARK: - Delete

    func deleteSession(id: String) throws {
        // Load session first to find screenshot filenames
        if let session = loadSession(id: id) {
            for message in session.messages {
                if let filename = message.screenshotFilename {
                    let screenshotPath = screenshotURL(filename: filename)
                    try? fileManager.removeItem(at: screenshotPath)
                }
            }
        }

        let url = sessionURL(id: id)
        if fileManager.fileExists(atPath: url.path) {
            try fileManager.removeItem(at: url)
        }
    }

    // MARK: - URLs

    func screenshotURL(filename: String) -> URL {
        screenshotsDirectory.appendingPathComponent(filename)
    }

    private func sessionURL(id: String) -> URL {
        baseDirectory.appendingPathComponent("\(id).json")
    }

    // MARK: - Private

    private func ensureDirectories() {
        if !fileManager.fileExists(atPath: baseDirectory.path) {
            try? fileManager.createDirectory(at: baseDirectory, withIntermediateDirectories: true)
        }
        if !fileManager.fileExists(atPath: screenshotsDirectory.path) {
            try? fileManager.createDirectory(at: screenshotsDirectory, withIntermediateDirectories: true)
        }
    }
}
