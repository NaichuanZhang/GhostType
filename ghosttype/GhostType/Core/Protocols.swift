import Cocoa
import ApplicationServices

// MARK: - Protocols for Dependency Injection & Testing

/// Provides accessibility operations — cursor info, text insertion, screenshots.
/// Default implementation delegates to AccessibilityEngine's static methods.
protocol AccessibilityProvider {
    func getCursorInfo() throws -> AccessibilityEngine.CursorInfo
    func getFocusedWindowFrame(for pid: pid_t?) -> CGRect?
    func insertText(_ text: String, into element: AXUIElement) throws
    func captureAppScreenshot(for app: NSRunningApplication) async -> Data?
    func requestPermission()
}

/// Default AccessibilityProvider that wraps the static AccessibilityEngine methods.
struct DefaultAccessibilityProvider: AccessibilityProvider {
    func getCursorInfo() throws -> AccessibilityEngine.CursorInfo {
        try AccessibilityEngine.getCursorInfo()
    }

    func getFocusedWindowFrame(for pid: pid_t?) -> CGRect? {
        AccessibilityEngine.getFocusedWindowFrame(for: pid)
    }

    func insertText(_ text: String, into element: AXUIElement) throws {
        try AccessibilityEngine.insertText(text, into: element)
    }

    func captureAppScreenshot(for app: NSRunningApplication) async -> Data? {
        await AccessibilityEngine.captureAppScreenshot(for: app)
    }

    func requestPermission() {
        AccessibilityEngine.requestPermission()
    }
}

/// Manages the Python subprocess lifecycle and communication.
protocol SubprocessProvider: AnyObject {
    var isRunning: Bool { get }
    func start()
    func stop()
    func send(_ request: SubprocessRequest)
    func events() -> AsyncThrowingStream<SubprocessEvent, Error>
}

/// Persists and loads conversation sessions.
protocol SessionStorage {
    func loadSessions() -> [Session]
    func saveSession(_ session: Session) throws
    func deleteSession(id: String) throws
    func saveScreenshot(data: Data, filename: String) throws
}

// MARK: - Default Conformances

extension SubprocessManager: SubprocessProvider {}

extension SessionStore: SessionStorage {}
