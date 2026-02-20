import Cocoa
import ApplicationServices
import ScreenCaptureKit

/// Handles all macOS Accessibility API interactions:
/// - Getting the focused text element in any app
/// - Reading cursor/caret screen position
/// - Reading selected text
/// - Inserting text via AX API or simulated paste
class AccessibilityEngine {

    enum AccessibilityError: Error, LocalizedError {
        case notTrusted
        case noFocusedElement
        case notATextElement
        case cannotGetPosition
        case cannotInsertText
        case axError(AXError)

        var errorDescription: String? {
            switch self {
            case .notTrusted: return "Accessibility permission not granted"
            case .noFocusedElement: return "No focused UI element found"
            case .notATextElement: return "Focused element is not a text field"
            case .cannotGetPosition: return "Cannot determine cursor position"
            case .cannotInsertText: return "Cannot insert text into this application"
            case .axError(let err): return "AXError: \(err.rawValue)"
            }
        }
    }

    struct CursorInfo {
        /// Position in Cocoa screen coordinates (origin at bottom-left of primary screen).
        let screenPosition: CGPoint
        let selectedText: String
        let element: AXUIElement
        /// Window frame in Cocoa coords; set when AX caret bounds are unavailable (Chrome/Electron).
        let windowFrame: CGRect?
        /// The text range of the selection (location + length), used to restore selection for replacement.
        let selectedRange: CFRange?
    }

    // MARK: - Permission Check

    static func isAccessibilityEnabled() -> Bool {
        return AXIsProcessTrusted()
    }

    static func requestPermission() {
        let options: NSDictionary = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ]
        _ = AXIsProcessTrustedWithOptions(options)
    }

    // MARK: - Get Cursor Info

    /// Returns the screen position of the text cursor and any selected text
    /// in the currently focused application.
    ///
    /// The returned `screenPosition` is in Cocoa coordinates (origin at
    /// bottom-left of primary screen), ready for NSWindow positioning.
    static func getCursorInfo() throws -> CursorInfo {
        guard isAccessibilityEnabled() else {
            throw AccessibilityError.notTrusted
        }

        let systemWide = AXUIElementCreateSystemWide()

        // 1. Get focused element
        var focusedRef: CFTypeRef?
        let focusErr = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        )
        guard focusErr == .success, let focused = focusedRef else {
            throw AccessibilityError.noFocusedElement
        }
        let element = focused as! AXUIElement

        // 2. Get selected text and its range (may be empty)
        let selectedText = getSelectedText(from: element)
        let selectedRange = selectedText.isEmpty ? nil : getSelectedTextRange(from: element)

        // 3. Get cursor screen position in Cocoa coordinates
        let position = getCaretPositionCocoa(from: element)

        // If AX text range succeeded we don't need the window frame;
        // otherwise attach it so PanelManager can position within the window.
        let windowFrame: CGRect? = (getCaretFromTextRangeCocoa(element) != nil)
            ? nil
            : getFocusedWindowFrame()

        return CursorInfo(
            screenPosition: position,
            selectedText: selectedText,
            element: element,
            windowFrame: windowFrame,
            selectedRange: selectedRange
        )
    }

    // MARK: - Caret Position (Cocoa Coordinates)

    /// Returns the best estimate of the text caret position in Cocoa coordinates.
    ///
    /// Strategy:
    /// 1. AX text range bounds — exact caret position (native macOS text views)
    /// 2. Focused window bottom-right — predictable fallback for Chrome/Electron
    /// 3. Mouse cursor position — universal last resort
    ///
    /// Chrome/Electron don't expose kAXBoundsForRangeParameterizedAttribute,
    /// so the focused window corner is used for those apps.
    private static func getCaretPositionCocoa(from element: AXUIElement) -> CGPoint {
        // Strategy 1: Exact caret position from AX text range bounds.
        // Works with native macOS apps (TextEdit, Notes, Mail, Xcode, etc.)
        if let cocoaPos = getCaretFromTextRangeCocoa(element) {
            NSLog("[GhostType] Caret position: AX text range → (%.0f, %.0f)", cocoaPos.x, cocoaPos.y)
            return cocoaPos
        }

        // Strategy 2: Bottom-right of focused app window.
        // Chrome/Electron don't expose caret bounds via AX — use the window
        // corner so the panel appears in a predictable location.
        if let windowFrame = getFocusedWindowFrame() {
            let windowPos = CGPoint(x: windowFrame.maxX, y: windowFrame.minY)
            NSLog("[GhostType] Caret position: window bottom-right → (%.0f, %.0f)", windowPos.x, windowPos.y)
            return windowPos
        }

        // Strategy 3: Mouse cursor position (already in Cocoa coordinates).
        let mouse = NSEvent.mouseLocation
        NSLog("[GhostType] Caret position: mouse fallback → (%.0f, %.0f)", mouse.x, mouse.y)
        return mouse
    }

    /// Get the caret position from AX text range bounds, returned in Cocoa coordinates.
    private static func getCaretFromTextRangeCocoa(_ element: AXUIElement) -> CGPoint? {
        guard let cgPos = getCaretFromTextRange(element) else { return nil }
        guard let primaryScreen = NSScreen.screens.first else { return nil }
        return CGPoint(x: cgPos.x, y: primaryScreen.frame.height - cgPos.y)
    }

    /// Get the caret position from AX text range bounds (CG coordinates, top-left origin).
    private static func getCaretFromTextRange(_ element: AXUIElement) -> CGPoint? {
        var rangeRef: CFTypeRef?
        let rangeErr = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeRef
        )
        guard rangeErr == .success, let range = rangeRef else { return nil }

        var boundsRef: CFTypeRef?
        let boundsErr = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXBoundsForRangeParameterizedAttribute as CFString,
            range,
            &boundsRef
        )
        guard boundsErr == .success, let bounds = boundsRef else { return nil }

        var rect = CGRect.zero
        if AXValueGetValue(bounds as! AXValue, .cgRect, &rect) {
            // Return the bottom of the selection rect in CG coords (below the text line).
            // CG origin is top-left, so bottom = origin.y + height.
            return CGPoint(x: rect.origin.x, y: rect.origin.y + rect.size.height)
        }
        return nil
    }

    // MARK: - Window Position Fallback

    /// Returns the focused window's frame in Cocoa coordinates (bottom-left origin).
    /// Used when AX caret bounds are unavailable (Chrome/Electron).
    static func getFocusedWindowFrame(for pid: pid_t? = nil) -> CGRect? {
        let resolvedPid: pid_t
        if let pid = pid {
            resolvedPid = pid
        } else {
            guard let frontApp = NSWorkspace.shared.frontmostApplication else { return nil }
            resolvedPid = frontApp.processIdentifier
        }
        let appElement = AXUIElementCreateApplication(resolvedPid)

        var windowRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXFocusedWindowAttribute as CFString, &windowRef) == .success,
              let window = windowRef else { return nil }
        let windowElement = window as! AXUIElement

        var posRef: CFTypeRef?
        var sizeRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(windowElement, kAXPositionAttribute as CFString, &posRef) == .success,
              AXUIElementCopyAttributeValue(windowElement, kAXSizeAttribute as CFString, &sizeRef) == .success,
              let posValue = posRef, let sizeValue = sizeRef else { return nil }

        var pos = CGPoint.zero
        var size = CGSize.zero
        guard AXValueGetValue(posValue as! AXValue, .cgPoint, &pos),
              AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) else { return nil }

        guard let primaryHeight = NSScreen.screens.first?.frame.height else { return nil }

        // Convert from CG (top-left origin) to Cocoa (bottom-left origin).
        let cocoaY = primaryHeight - (pos.y + size.height)
        return CGRect(x: pos.x, y: cocoaY, width: size.width, height: size.height)
    }

    // MARK: - Get Selected Text & Range

    private static func getSelectedTextRange(from element: AXUIElement) -> CFRange? {
        var rangeRef: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &rangeRef
        )
        guard err == .success, let rangeValue = rangeRef else { return nil }
        var range = CFRange(location: 0, length: 0)
        guard AXValueGetValue(rangeValue as! AXValue, .cfRange, &range) else { return nil }
        return range
    }

    private static func getSelectedText(from element: AXUIElement) -> String {
        var valueRef: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            &valueRef
        )
        guard err == .success, let value = valueRef as? String else {
            return ""
        }
        return value
    }

    // MARK: - Insert Text

    /// Insert text at the current cursor position in the focused application.
    /// Tries AX API first, falls back to simulated paste.
    static func insertText(_ text: String) throws {
        guard isAccessibilityEnabled() else {
            throw AccessibilityError.notTrusted
        }

        let systemWide = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        let err = AXUIElementCopyAttributeValue(
            systemWide,
            kAXFocusedUIElementAttribute as CFString,
            &focusedRef
        )
        guard err == .success, let focused = focusedRef else {
            throw AccessibilityError.noFocusedElement
        }
        let element = focused as! AXUIElement

        // Attempt 1: AX API direct insertion
        if tryAXInsert(text, into: element) {
            return
        }

        // Attempt 2: Simulated paste (Cmd+V)
        simulatePaste(text)
    }

    /// Insert text directly into a specific AXUIElement via AX API only.
    /// Throws if AX insert fails — caller should fall back to system-wide insertion.
    static func insertText(_ text: String, into element: AXUIElement) throws {
        guard isAccessibilityEnabled() else {
            throw AccessibilityError.notTrusted
        }
        guard tryAXInsert(text, into: element) else {
            throw AccessibilityError.cannotInsertText
        }
    }

    /// Re-selects a saved text range on the element, then replaces the selection with new text.
    /// Used to replace originally-selected text after a rewrite.
    static func replaceTextInRange(_ range: CFRange, with text: String, on element: AXUIElement) -> Bool {
        var mutableRange = range
        guard let rangeValue = AXValueCreate(.cfRange, &mutableRange) else { return false }
        let rangeErr = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            rangeValue
        )
        guard rangeErr == .success else {
            NSLog("[GhostType] replaceTextInRange: failed to restore selection range")
            return false
        }
        let textErr = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )
        return textErr == .success
    }

    private static func tryAXInsert(_ text: String, into element: AXUIElement) -> Bool {
        let result = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )
        return result == .success
    }

    // MARK: - Screenshot Capture

    /// Captures a screenshot of the frontmost application's main window.
    /// Returns JPEG data (compressed for smaller payload) or nil on failure.
    /// The image is resized to max 1024px on the longest side.
    /// Requires macOS 14.0+ and screen recording permission.
    static func captureAppScreenshot(for targetApp: NSRunningApplication? = nil) async -> Data? {
        guard #available(macOS 14.0, *) else {
            NSLog("[GhostType] Screenshot: requires macOS 14.0+")
            return nil
        }

        // Check screen recording permission without prompting
        guard CGPreflightScreenCaptureAccess() else {
            NSLog("[GhostType] Screenshot: screen recording permission not granted")
            return nil
        }

        let frontApp: NSRunningApplication
        if let provided = targetApp {
            frontApp = provided
        } else if let queried = NSWorkspace.shared.frontmostApplication {
            frontApp = queried
        } else {
            NSLog("[GhostType] Screenshot: no frontmost application")
            return nil
        }

        // Guard against capturing GhostType itself
        if frontApp.bundleIdentifier == Bundle.main.bundleIdentifier {
            NSLog("[GhostType] Screenshot: skipping self-capture")
            return nil
        }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true
            )

            // Find the main window of the frontmost app (prefer titled windows)
            let appWindows = content.windows.filter {
                $0.owningApplication?.processID == frontApp.processIdentifier
            }
            guard let window = appWindows.first(where: { ($0.title ?? "").count > 0 })
                    ?? appWindows.first else {
                NSLog("[GhostType] Screenshot: no window for %@", frontApp.bundleIdentifier ?? "unknown")
                return nil
            }

            let filter = SCContentFilter(desktopIndependentWindow: window)
            let config = SCStreamConfiguration()

            // Resize to max 1024px on longest side
            let maxDim: CGFloat = 1024
            let scale = min(maxDim / window.frame.width, maxDim / window.frame.height, 1.0)
            config.width = Int(window.frame.width * scale)
            config.height = Int(window.frame.height * scale)

            let cgImage = try await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: config
            )

            // Convert CGImage to JPEG
            let nsImage = NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
            guard let tiffData = nsImage.tiffRepresentation,
                  let bitmap = NSBitmapImageRep(data: tiffData),
                  let jpegData = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.7]) else {
                NSLog("[GhostType] Screenshot: JPEG conversion failed")
                return nil
            }

            NSLog("[GhostType] Screenshot: captured %dx%d (%.0f KB)",
                  config.width, config.height, Double(jpegData.count) / 1024.0)
            return jpegData
        } catch {
            NSLog("[GhostType] Screenshot: capture failed: %@", error.localizedDescription)
            return nil
        }
    }

    // MARK: - Paste Simulation

    static func simulatePaste(_ text: String) {
        let pasteboard = NSPasteboard.general

        // Save current clipboard
        let previousContents = pasteboard.string(forType: .string)

        // Set our text
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        // Simulate Cmd+V
        let source = CGEventSource(stateID: .hidSystemState)

        let keyVDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true) // V key
        keyVDown?.flags = .maskCommand
        let keyVUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        keyVUp?.flags = .maskCommand

        keyVDown?.post(tap: .cghidEventTap)
        keyVUp?.post(tap: .cghidEventTap)

        // Restore clipboard after a brief delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            pasteboard.clearContents()
            if let prev = previousContents {
                pasteboard.setString(prev, forType: .string)
            }
        }
    }
}
