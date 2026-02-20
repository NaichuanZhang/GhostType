import Cocoa
import SwiftUI
import Combine
import WebKit

/// WKWebView subclass that refuses first-responder status to prevent focus theft.
class NonInteractiveWebView: WKWebView {
    override var acceptsFirstResponder: Bool { false }
}

/// Manages the floating prompt panel — creation, positioning, show/hide.
class PanelManager {
    private var panel: FloatingPanel?
    private var hostingView: NSView?
    private let appState: AppState
    private var dismissObserver: NSObjectProtocol?
    private var escapeMonitor: Any?
    private var stateChangeObserver: AnyCancellable?
    private var previousApp: NSRunningApplication?

    // Avatar panel views
    private var avatarWebView: NonInteractiveWebView?
    private var avatarContainer: NSView?
    private var avatarWidthConstraint: NSLayoutConstraint?
    private var avatarGapConstraint: NSLayoutConstraint?
    private var avatarObserver: AnyCancellable?
    private var loadedAvatarURL: String?

    init(appState: AppState) {
        self.appState = appState

        dismissObserver = NotificationCenter.default.addObserver(
            forName: .ghostTypeDismissPanel,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.hide()
        }

        // Reactively resize the panel when AppState properties change.
        //
        // The 200ms debounce ensures we only fire after all @Published
        // mutations have settled (e.g. completeTurn() changes messages,
        // promptText, responseText in rapid succession).
        //
        // The !isGenerating guard is critical: during token streaming,
        // reading intrinsicContentSize triggers SwiftUI layout, and if
        // SwiftUI is mid-update from a token flush, the non-reentrant
        // layout engine deadlocks.  By gating on !isGenerating we
        // guarantee zero intrinsicContentSize reads / setFrame() calls
        // during streaming.  The panel stays at its current size while
        // tokens stream, and snaps to the correct height once generation
        // (and the debounce window) completes.
        stateChangeObserver = appState.objectWillChange
            .debounce(for: .milliseconds(200), scheduler: RunLoop.main)
            .sink { [weak self] _ in
                guard let self = self,
                      self.panel?.isVisible == true,
                      !self.appState.isGenerating else { return }
                self.resizePanelToFit()
            }
    }

    deinit {
        if let observer = dismissObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let monitor = escapeMonitor {
            NSEvent.removeMonitor(monitor)
        }
        stateChangeObserver?.cancel()
        avatarObserver?.cancel()
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
            self.appState.clearConversation()
            // Set context AFTER clearConversation (which clears selectedContext)
            self.appState.selectedContext = cursorInfo?.selectedText ?? ""
            self.appState.selectedTextRange = cursorInfo?.selectedRange
            self.appState.isPromptVisible = true

            // Calculate panel width as 70% of the active app's window width
            let activeWindowFrame = cursorInfo?.windowFrame
                ?? AccessibilityEngine.getFocusedWindowFrame(for: effectiveApp?.processIdentifier)
            if let windowWidth = activeWindowFrame?.width, windowWidth > 0 {
                let desired = windowWidth * 0.7
                // Clamp between 380 (minimum usable) and 900 (maximum reasonable)
                self.appState.panelWidth = min(max(desired, 380), 900)
                NSLog("[GhostType] Panel width: %.0f (70%% of window %.0f)", self.appState.panelWidth, windowWidth)
            }

            // Reset backend agent history for fresh conversation
            self.appState.wsClient.sendNewConversation()

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

            // Initial resize after SwiftUI has laid out the view tree.
            DispatchQueue.main.async { [weak self] in
                self?.resizePanelToFit()
            }

            // Drive focus into the actual NSTextField inside the SwiftUI hierarchy.
            // Uses retry because SwiftUI lazily creates AppKit views.
            self.focusTextField(in: panel, attempt: 1)
        }
    }

    func hide() {
        panel?.orderOut(nil)
        appState.isPromptVisible = false
        appState.clearConversation()
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
            if event.keyCode == 53 { // Escape
                self?.hide()
                return nil
            }
            // Enter key (keyCode 36) with no modifiers — route through handleEnterKey
            if event.keyCode == 36,
               event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
                let hasResponse = !(self?.appState.responseText.isEmpty ?? true)
                let isGenerating = self?.appState.isGenerating ?? false
                NSLog("[GhostType][KeyMonitor] Enter pressed — hasResponse: %@, isGenerating: %@",
                      hasResponse ? "YES" : "NO", isGenerating ? "YES" : "NO")
                if hasResponse && !isGenerating {
                    NSLog("[GhostType][KeyMonitor] Consuming Enter, posting ghostTypeEnterPressed")
                    NotificationCenter.default.post(name: .ghostTypeEnterPressed, object: nil)
                    return nil // Consume — don't let .onSubmit also fire
                }
                // No response ready — let Enter pass through to TextField's .onSubmit
                NSLog("[GhostType][KeyMonitor] Passing Enter through to TextField")
            }
            return event
        }
    }

    private func stopEscapeMonitor() {
        if let monitor = escapeMonitor {
            NSEvent.removeMonitor(monitor)
            escapeMonitor = nil
        }
    }

    // MARK: - Panel Resize

    /// Total panel width including avatar panel (if visible) and gap.
    private func totalPanelWidth() -> CGFloat {
        if appState.showAvatarPanel {
            return appState.avatarPanelWidth + 6 + appState.panelWidth
        }
        return appState.panelWidth
    }

    /// Reads the SwiftUI hosting view's intrinsic content size and sets the
    /// panel frame to match.  Must NEVER be called while `isGenerating` is
    /// true — reading `intrinsicContentSize` triggers SwiftUI layout, which
    /// deadlocks if SwiftUI is mid-update from a token flush.
    private func resizePanelToFit() {
        guard let panel = panel, panel.isVisible,
              let hostingView = self.hostingView else { return }

        let idealHeight = hostingView.intrinsicContentSize.height
        guard idealHeight > 0 else { return }

        let screen = panel.screen ?? NSScreen.main
        let maxHeight = min((screen?.visibleFrame.height ?? 800) - 40, 900)
        let newHeight = min(max(idealHeight, 120), maxHeight)
        let newWidth = totalPanelWidth()
        let currentFrame = panel.frame

        let heightChanged = abs(currentFrame.height - newHeight) > 2
        let widthChanged = abs(currentFrame.width - newWidth) > 2

        // Only resize if something changed meaningfully
        guard heightChanged || widthChanged else { return }

        NSLog("[GhostType][Resize] Panel: %.0fx%.0f → %.0fx%.0f",
              currentFrame.width, currentFrame.height, newWidth, newHeight)

        // Keep top edge fixed — grow/shrink downward
        var newY = currentFrame.maxY - newHeight

        // Clamp to screen visible area
        if let vis = screen?.visibleFrame {
            if newY < vis.minY {
                newY = vis.minY
            }
            if newY + newHeight > vis.maxY {
                newY = vis.maxY - newHeight
            }
        }

        panel.setFrame(NSRect(x: currentFrame.origin.x, y: newY,
                              width: newWidth, height: newHeight),
                       display: true, animate: false)
    }

    /// Returns an HTML wrapper that scales the given URL's iframe to fit the container.
    private func centeredIframeHTML(for urlString: String) -> String {
        return """
        <!DOCTYPE html>
        <html><head><meta charset="utf-8">
        <style>
          html, body {
            margin: 0; padding: 0; width: 100%; height: 100%;
            overflow: hidden; background: transparent;
          }
          .wrapper {
            width: 100%; height: 100%;
            display: flex; justify-content: center; align-items: center;
            overflow: hidden;
          }
          .scaler {
            width: 1024px; height: 1024px;
            transform-origin: center center;
            flex-shrink: 0;
          }
          iframe {
            border: none; width: 100%; height: 100%; display: block;
          }
        </style>
        <script>
          function fitIframe() {
            var w = document.documentElement.clientWidth;
            var h = document.documentElement.clientHeight;
            var scaler = document.querySelector('.scaler');
            var scale = Math.min(w / 1024, h / 1024);
            scaler.style.transform = 'scale(' + scale + ')';
          }
          window.addEventListener('resize', fitIframe);
          window.addEventListener('load', fitIframe);
        </script>
        </head><body>
        <div class="wrapper">
          <div class="scaler">
            <iframe src="\(urlString)" allow="autoplay" scrolling="no"></iframe>
          </div>
        </div>
        </body></html>
        """
    }

    /// Updates avatar container visibility and adjusts panel width.
    private func updateAvatarVisibility() {
        let show = appState.showAvatarPanel
        avatarContainer?.isHidden = !show
        avatarWidthConstraint?.constant = show ? appState.avatarPanelWidth : 0
        avatarGapConstraint?.constant = show ? 6 : 0
        resizePanelToFit()
    }

    // MARK: - Panel Creation

    private func getOrCreatePanel() -> FloatingPanel {
        if let existing = panel {
            // Resize existing panel to match new dynamic width
            let desiredWidth = totalPanelWidth()
            let currentFrame = existing.frame
            if abs(currentFrame.width - desiredWidth) > 2 {
                existing.setFrame(NSRect(x: currentFrame.origin.x, y: currentFrame.origin.y,
                                         width: desiredWidth, height: currentFrame.height),
                                  display: false)
            }
            // Reload avatar URL if it changed
            if let webView = avatarWebView,
               loadedAvatarURL != appState.avatarURL {
                webView.loadHTMLString(centeredIframeHTML(for: appState.avatarURL), baseURL: nil)
                loadedAvatarURL = appState.avatarURL
            }
            updateAvatarVisibility()
            return existing
        }

        let fullWidth = totalPanelWidth()
        let panelHeight: CGFloat = 320

        let panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: fullWidth, height: panelHeight),
            styleMask: [.nonactivatingPanel, .titled, .fullSizeContentView],
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

        // Root container — transparent, holds avatar + prompt side by side
        let rootContainer = NSView(frame: NSRect(x: 0, y: 0, width: fullWidth, height: panelHeight))
        rootContainer.wantsLayer = true
        rootContainer.translatesAutoresizingMaskIntoConstraints = false

        // --- Avatar container (left) ---
        let avatarContainer = NSView()
        avatarContainer.wantsLayer = true
        avatarContainer.layer?.cornerRadius = 12
        avatarContainer.layer?.masksToBounds = true
        avatarContainer.translatesAutoresizingMaskIntoConstraints = false

        let webConfig = WKWebViewConfiguration()
        let webView = NonInteractiveWebView(frame: .zero, configuration: webConfig)
        webView.translatesAutoresizingMaskIntoConstraints = false
        webView.setValue(false, forKey: "drawsBackground")
        webView.underPageBackgroundColor = .clear
        webView.loadHTMLString(centeredIframeHTML(for: appState.avatarURL), baseURL: nil)
        self.loadedAvatarURL = appState.avatarURL
        avatarContainer.addSubview(webView)
        NSLayoutConstraint.activate([
            webView.topAnchor.constraint(equalTo: avatarContainer.topAnchor),
            webView.bottomAnchor.constraint(equalTo: avatarContainer.bottomAnchor),
            webView.leadingAnchor.constraint(equalTo: avatarContainer.leadingAnchor),
            webView.trailingAnchor.constraint(equalTo: avatarContainer.trailingAnchor),
        ])
        self.avatarWebView = webView
        self.avatarContainer = avatarContainer

        // --- Prompt visual effect (right) ---
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

        // --- Layout: [avatar] - gap - [prompt] ---
        rootContainer.addSubview(avatarContainer)
        rootContainer.addSubview(visualEffect)

        let avatarWidth = avatarContainer.widthAnchor.constraint(
            equalToConstant: appState.showAvatarPanel ? appState.avatarPanelWidth : 0)
        let gapConstraint = visualEffect.leadingAnchor.constraint(
            equalTo: avatarContainer.trailingAnchor,
            constant: appState.showAvatarPanel ? 6 : 0)
        self.avatarWidthConstraint = avatarWidth
        self.avatarGapConstraint = gapConstraint

        NSLayoutConstraint.activate([
            // Avatar: pinned left, full height
            avatarContainer.topAnchor.constraint(equalTo: rootContainer.topAnchor),
            avatarContainer.bottomAnchor.constraint(equalTo: rootContainer.bottomAnchor),
            avatarContainer.leadingAnchor.constraint(equalTo: rootContainer.leadingAnchor),
            avatarWidth,

            // Prompt: pinned right, full height, gap from avatar
            gapConstraint,
            visualEffect.topAnchor.constraint(equalTo: rootContainer.topAnchor),
            visualEffect.bottomAnchor.constraint(equalTo: rootContainer.bottomAnchor),
            visualEffect.trailingAnchor.constraint(equalTo: rootContainer.trailingAnchor),
        ])

        avatarContainer.isHidden = !appState.showAvatarPanel

        panel.contentView = rootContainer

        // Observe showAvatarPanel changes
        avatarObserver = appState.$showAvatarPanel
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateAvatarVisibility()
            }

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
