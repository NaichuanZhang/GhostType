import Cocoa
import SwiftUI

/// Actions that a key event in the panel can resolve to.
enum KeyAction: Equatable {
    case dismiss          // Escape
    case insertNewline    // Shift+Enter
    case handleEnter      // Enter (response ready, no modifiers)
    case submit           // Cmd+Enter
    case passThrough      // Let event reach TextField
}

/// Manages the floating prompt panel — creation, positioning, show/hide.
class PanelManager {
    private var panel: FloatingPanel?
    private var hostingView: NSView?
    private let appState: AppState
    private var dismissObserver: NSObjectProtocol?
    private var escapeMonitor: Any?
    private var previousApp: NSRunningApplication?

    init(appState: AppState) {
        self.appState = appState

        dismissObserver = NotificationCenter.default.addObserver(
            forName: .ghostTypeDismissPanel,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.hide()
        }

    }

    // MARK: - Key Event Routing

    /// Pure function that determines the action for a key event.
    /// Extracted from the event monitor closure to enable unit testing.
    static func routeKeyEvent(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        hasResponse: Bool,
        isGenerating: Bool
    ) -> KeyAction {
        if keyCode == 53 { // Escape
            return .dismiss
        }
        if keyCode == 36 { // Enter / Return
            let deviceFlags = modifierFlags.intersection(.deviceIndependentFlagsMask)
            if deviceFlags == .command {
                return .submit
            }
            if deviceFlags.contains(.shift) {
                return .insertNewline
            }
            if deviceFlags.isEmpty && hasResponse && !isGenerating {
                return .handleEnter
            }
            if deviceFlags.isEmpty {
                return .passThrough
            }
        }
        return .passThrough
    }

    deinit {
        if let observer = dismissObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let monitor = escapeMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    func toggle() {
        if panel?.isVisible == true {
            hide()
        } else {
            show()
        }
    }

    func show() {
        // Detect whether GhostType is the frontmost app (rapid re-open race)
        let frontApp = NSWorkspace.shared.frontmostApplication
        let isSelf = frontApp?.bundleIdentifier == Bundle.main.bundleIdentifier

        // Determine the effective target app
        let effectiveApp: NSRunningApplication?
        if isSelf {
            // Rapid re-open: GhostType is still frontmost from previous show().
            // Fall back to previousApp if available.
            effectiveApp = previousApp
            NSLog("[GhostType][Show] Frontmost is self, using previousApp: %@ (pid: %d)",
                  effectiveApp?.localizedName ?? "nil",
                  effectiveApp?.processIdentifier ?? -1)
        } else {
            effectiveApp = frontApp
        }
        let effectiveBundleID = effectiveApp?.bundleIdentifier

        // Gather AX context only when a real target app is frontmost.
        // When self is frontmost, getCursorInfo() would return GhostType's own
        // AX elements — skip it and let positioning fall back to window frame.
        let cursorInfo: AccessibilityEngine.CursorInfo?
        if isSelf {
            cursorInfo = nil
        } else {
            cursorInfo = try? AccessibilityEngine.getCursorInfo()
        }

        // Capture screenshot asynchronously (will be ready before user submits a prompt)
        if let app = effectiveApp {
            Task {
                if let data = await AccessibilityEngine.captureAppScreenshot(for: app) {
                    let base64 = data.base64EncodedString()
                    let image = NSImage(data: data)
                    await MainActor.run { [weak self] in
                        self?.appState.screenshotBase64 = base64
                        self?.appState.screenshotImage = image
                        NSLog("[GhostType] Screenshot stored: %d chars base64", base64.count)
                    }
                }
            }
        }

        // For web apps, AX caret position is unreliable — always get window frame
        let windowFrameOverride: CGRect?
        if let bid = effectiveBundleID, PromptPanelView.isWebBasedApp(bid) {
            windowFrameOverride = cursorInfo?.windowFrame
                ?? AccessibilityEngine.getFocusedWindowFrame(for: effectiveApp?.processIdentifier)
        } else {
            windowFrameOverride = nil
        }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            self.appState.targetElement = cursorInfo?.element
            self.appState.targetBundleID = effectiveBundleID

            let isResume = self.appState.shouldResumeSession()
            if isResume {
                // Quick re-invoke: keep conversation, clear stale screenshot
                self.appState.refreshScreenshot()
                NSLog("[GhostType][Show] Resuming previous session (%d messages)",
                      self.appState.conversationMessages.count)
            } else {
                self.appState.clearConversation()
                // Reset backend agent history for fresh conversation
                self.appState.wsClient.sendNewConversation()
            }

            // Set context AFTER resume/clear decision (clearConversation resets selectedContext)
            self.appState.selectedContext = cursorInfo?.selectedText ?? ""
            self.appState.selectedTextRange = cursorInfo?.selectedRange
            self.appState.isPromptVisible = true

            let panel = self.getOrCreatePanel()

            // Positioning priority:
            // 1. Web-app window frame override (always center for known web apps)
            // 2. cursorInfo.windowFrame (AX caret range failed → center in window)
            // 3. Focused window frame fallback (cursorInfo nil → still try centering)
            // 4. AX caret / mouse position (native apps with working caret)
            if let windowFrame = windowFrameOverride ?? cursorInfo?.windowFrame {
                NSLog("[GhostType] Panel anchor: window frame (%.0f, %.0f, %.0f, %.0f)",
                      windowFrame.origin.x, windowFrame.origin.y,
                      windowFrame.size.width, windowFrame.size.height)
                self.positionPanelInWindow(panel, windowFrame: windowFrame)
            } else if cursorInfo == nil,
                      let windowFrame = AccessibilityEngine.getFocusedWindowFrame(for: effectiveApp?.processIdentifier) {
                // cursorInfo failed entirely — center in focused window as fallback
                NSLog("[GhostType] Panel anchor: fallback window frame (%.0f, %.0f, %.0f, %.0f)",
                      windowFrame.origin.x, windowFrame.origin.y,
                      windowFrame.size.width, windowFrame.size.height)
                self.positionPanelInWindow(panel, windowFrame: windowFrame)
            } else {
                let anchor = cursorInfo?.screenPosition ?? NSEvent.mouseLocation
                NSLog("[GhostType] Panel anchor: (%.0f, %.0f), cursorInfo: %@",
                      anchor.x, anchor.y,
                      cursorInfo != nil ? "yes" : "nil (using mouse)")
                self.positionPanel(panel, below: anchor)
            }

            // Only update previousApp when we have a real (non-self) target
            if let app = effectiveApp {
                self.previousApp = app
            }
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)

            self.startEscapeMonitor()

            // Drive focus into the actual NSTextField inside the SwiftUI hierarchy.
            // Uses retry because SwiftUI lazily creates AppKit views.
            self.focusTextField(in: panel, attempt: 1)
        }
    }

    func hide() {
        panel?.orderOut(nil)
        appState.isPromptVisible = false
        appState.saveCurrentSession()
        appState.recordPanelDismiss()
        stopEscapeMonitor()

        if let prev = previousApp {
            NSLog("[GhostType][Hide] Reactivating previous app: %@ (pid: %d)",
                  prev.localizedName ?? "unknown", prev.processIdentifier)
            NSApp.deactivate()
            prev.activate()
        } else {
            NSLog("[GhostType][Hide] No previous app saved, falling back to NSApp.deactivate()")
            NSApp.deactivate()
        }
    }

    // MARK: - Escape Key Monitor

    private func startEscapeMonitor() {
        guard escapeMonitor == nil else { return }
        escapeMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let hasResponse = !(self?.appState.responseText.isEmpty ?? true)
            let isGenerating = self?.appState.isGenerating ?? false

            let action = PanelManager.routeKeyEvent(
                keyCode: event.keyCode,
                modifierFlags: event.modifierFlags,
                hasResponse: hasResponse,
                isGenerating: isGenerating
            )

            switch action {
            case .dismiss:
                self?.hide()
                return nil
            case .insertNewline:
                NSLog("[GhostType][KeyMonitor] Shift+Enter — inserting newline")
                DispatchQueue.main.async {
                    self?.appState.promptText.append("\n")
                }
                return nil
            case .handleEnter:
                NSLog("[GhostType][KeyMonitor] Enter — response ready, posting ghostTypeEnterPressed")
                NotificationCenter.default.post(name: .ghostTypeEnterPressed, object: nil)
                return nil
            case .submit:
                NSLog("[GhostType][KeyMonitor] Cmd+Enter — posting ghostTypeSubmitPressed")
                NotificationCenter.default.post(name: .ghostTypeSubmitPressed, object: nil)
                return nil
            case .passThrough:
                return event
            }
        }
    }

    private func stopEscapeMonitor() {
        if let monitor = escapeMonitor {
            NSEvent.removeMonitor(monitor)
            escapeMonitor = nil
        }
    }

    // MARK: - Static Panel Sizing

    private static let promptWidth: CGFloat = 480
    private static let panelHeight: CGFloat = 640

    // MARK: - Panel Creation

    private func getOrCreatePanel() -> FloatingPanel {
        if let existing = panel {
            return existing
        }

        let panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.promptWidth, height: Self.panelHeight),
            styleMask: [.nonactivatingPanel, .titled, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        panel.level = .floating
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false

        let visualEffect = NSVisualEffectView()
        visualEffect.state = .active
        visualEffect.material = .popover
        visualEffect.blendingMode = .behindWindow
        visualEffect.wantsLayer = true
        visualEffect.layer?.cornerRadius = 12
        visualEffect.layer?.masksToBounds = true
        visualEffect.translatesAutoresizingMaskIntoConstraints = false

        let hostingView = NSHostingView(
            rootView: PromptPanelView()
                .environmentObject(appState)
        )
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        visualEffect.addSubview(hostingView)
        self.hostingView = hostingView

        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: visualEffect.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: visualEffect.bottomAnchor),
            hostingView.leadingAnchor.constraint(equalTo: visualEffect.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: visualEffect.trailingAnchor),
        ])

        panel.contentView = visualEffect

        self.panel = panel
        return panel
    }

    // MARK: - TextField Focus

    /// Attempts to find and focus the NSTextField inside the SwiftUI hosting view.
    /// Retries up to 5 times with increasing delays to handle layout timing.
    private func focusTextField(in panel: FloatingPanel, attempt: Int) {
        let maxAttempts = 5
        let delay = 0.05 * Double(attempt)

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self = self else { return }
            guard panel.isVisible else {
                NSLog("[GhostType][Focus] Panel hidden, aborting attempt %d", attempt)
                return
            }

            NSLog("[GhostType][Focus] Attempt %d/%d — isKey: %@, isActive: %@, firstResponder: %@",
                  attempt, maxAttempts,
                  panel.isKeyWindow ? "YES" : "NO",
                  NSApp.isActive ? "YES" : "NO",
                  String(describing: type(of: panel.firstResponder as Any)))

            if !panel.isKeyWindow {
                panel.makeKey()
            }

            if let textField = self.findTextField(in: panel.contentView) {
                let ok = panel.makeFirstResponder(textField)
                NSLog("[GhostType][Focus] Found NSTextField, makeFirstResponder: %@", ok ? "YES" : "NO")
                if ok { return }
            } else {
                NSLog("[GhostType][Focus] NSTextField not found in view hierarchy")
            }

            if attempt < maxAttempts {
                self.focusTextField(in: panel, attempt: attempt + 1)
            } else {
                NSLog("[GhostType][Focus] All %d attempts exhausted. View hierarchy:", maxAttempts)
                self.dumpViewHierarchy(panel.contentView, indent: 0)
            }
        }
    }

    /// Recursively searches for an editable NSTextField in the view tree.
    private func findTextField(in view: NSView?) -> NSView? {
        guard let view = view else { return nil }
        if let tf = view as? NSTextField, tf.isEditable {
            return tf
        }
        for sub in view.subviews {
            if let found = findTextField(in: sub) {
                return found
            }
        }
        return nil
    }

    /// Dumps the view hierarchy to Console for debugging.
    private func dumpViewHierarchy(_ view: NSView?, indent: Int) {
        guard let view = view else { return }
        let prefix = String(repeating: "  ", count: indent)
        NSLog("[GhostType][ViewTree] %@%@ frame:(%.0f,%.0f,%.0f,%.0f) acceptsFirstResponder:%@",
              prefix, String(describing: type(of: view)),
              view.frame.origin.x, view.frame.origin.y,
              view.frame.size.width, view.frame.size.height,
              view.acceptsFirstResponder ? "YES" : "NO")
        for sub in view.subviews {
            dumpViewHierarchy(sub, indent: indent + 1)
        }
    }

    // MARK: - Positioning

    /// Position the panel at the center of a window (Cocoa coordinates).
    /// Used when AX caret bounds are unavailable (Chrome/Electron).
    private func positionPanelInWindow(_ panel: FloatingPanel, windowFrame: CGRect) {
        let panelSize = panel.frame.size

        // Center of window in Cocoa coords
        var x = windowFrame.midX - panelSize.width / 2
        var y = windowFrame.midY - panelSize.height / 2

        // Screen-clamp for safety
        if let vis = (NSScreen.screens.first(where: { $0.frame.intersects(windowFrame) })
                      ?? NSScreen.main)?.visibleFrame {
            x = min(max(x, vis.minX + 8), vis.maxX - panelSize.width - 8)
            y = min(max(y, vis.minY + 8), vis.maxY - panelSize.height - 8)
        }

        panel.setFrameOrigin(NSPoint(x: x, y: y))
        NSLog("[GhostType] Panel placed at center (%.0f, %.0f) in window (%.0f, %.0f, %.0f, %.0f)",
              x, y,
              windowFrame.origin.x, windowFrame.origin.y,
              windowFrame.size.width, windowFrame.size.height)
    }

    /// Position the panel below the given anchor point (Cocoa coordinates).
    /// Finds the screen containing the anchor and clamps to its visible area.
    private func positionPanel(_ panel: FloatingPanel, below anchor: CGPoint) {
        let panelSize = panel.frame.size

        // Find the screen containing the anchor point
        let screen = NSScreen.screens.first(where: { $0.frame.contains(anchor) })
            ?? NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let targetScreen = screen else { return }
        let vis = targetScreen.visibleFrame

        // Position below the anchor with a small gap
        var x = anchor.x
        var y = anchor.y - panelSize.height - 4

        // Clamp horizontally
        if x + panelSize.width > vis.maxX {
            x = vis.maxX - panelSize.width - 8
        }
        if x < vis.minX {
            x = vis.minX + 8
        }

        // If panel goes below visible area, show above anchor instead
        if y < vis.minY {
            y = anchor.y + 4
        }
        // If panel goes above visible area, clamp to top
        if y + panelSize.height > vis.maxY {
            y = vis.maxY - panelSize.height - 4
        }

        panel.setFrameOrigin(NSPoint(x: x, y: y))
        NSLog("[GhostType] Panel placed at (%.0f, %.0f) on screen '%@' visibleFrame: (%.0f, %.0f, %.0f, %.0f)",
              x, y,
              targetScreen.localizedName,
              vis.origin.x, vis.origin.y, vis.size.width, vis.size.height)
    }
}
