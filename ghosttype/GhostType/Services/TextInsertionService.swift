import Cocoa
import ApplicationServices

/// Handles text insertion into the target app via AX API or simulated paste.
/// Extracted from PromptPanelView to enable testing and reuse.
enum TextInsertionService {

    /// Insert text at the current cursor position in the target app.
    /// Dismisses the panel first, then attempts insertion with retries.
    static func insert(
        text: String,
        targetElement: AXUIElement?,
        targetBundleID: String?,
        selectedTextRange: CFRange?,
        hasSelectedContext: Bool,
        dismissPanel: @escaping () -> Void
    ) {
        guard !text.isEmpty else {
            NSLog("[GhostType][Insert] insertText called but text is empty, aborting")
            return
        }

        NSLog("[GhostType][Insert] insertText — text length: %d, savedElement: %@, replace: %@",
              text.count, targetElement != nil ? "yes" : "nil",
              hasSelectedContext ? "yes" : "no")

        // Dismiss panel first — this deactivates GhostType and returns
        // focus to the previous app, which is required for AX text insertion
        dismissPanel()

        if hasSelectedContext, let range = selectedTextRange {
            NSLog("[GhostType][Insert] Panel dismissed, starting replacement (range: %d+%d)",
                  range.location, range.length)
            attemptReplacement(text: text, targetElement: targetElement, targetBundleID: targetBundleID, range: range, attempt: 1)
        } else {
            NSLog("[GhostType][Insert] Panel dismissed, starting insertion")
            attemptInsertion(text: text, targetElement: targetElement, targetBundleID: targetBundleID, attempt: 1)
        }
    }

    // MARK: - Insertion with Retries

    static func attemptInsertion(text: String, targetElement: AXUIElement?, targetBundleID: String?, attempt: Int) {
        // Web-based apps: AX returns success but silently drops text.
        // Skip retries and paste directly after a brief delay.
        if let bid = targetBundleID, isWebBasedApp(bid) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
                NSLog("[GhostType][Insert] Web app (%@), using simulatePaste", bid)
                AccessibilityEngine.simulatePaste(text)
            }
            return
        }

        let delays: [Double] = [0.15, 0.30, 0.50]
        guard attempt <= delays.count else {
            NSLog("[GhostType][Insert] AX exhausted after %d attempts. Trying direct paste.", delays.count)
            AccessibilityEngine.simulatePaste(text)
            return
        }

        let delay = delays[attempt - 1]
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            do {
                if let element = targetElement {
                    do {
                        try AccessibilityEngine.insertText(text, into: element)
                        NSLog("[GhostType][Insert] Success on attempt %d (delay: %.2fs) via saved element", attempt, delay)
                        return
                    } catch {
                        NSLog("[GhostType][Insert] Saved element AX failed, trying system-wide (attempt %d)", attempt)
                    }
                }
                try AccessibilityEngine.insertText(text)
                NSLog("[GhostType][Insert] Success on attempt %d (delay: %.2fs) via system query", attempt, delay)
            } catch {
                NSLog("[GhostType][Insert] Attempt %d failed (delay: %.2fs): %@",
                      attempt, delay, error.localizedDescription)
                attemptInsertion(text: text, targetElement: targetElement, targetBundleID: targetBundleID, attempt: attempt + 1)
            }
        }
    }

    // MARK: - Replacement with Retries

    static func attemptReplacement(text: String, targetElement: AXUIElement?, targetBundleID: String?, range: CFRange, attempt: Int) {
        if let bid = targetBundleID, isWebBasedApp(bid) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.30) {
                NSLog("[GhostType][Replace] Web app (%@), using simulatePaste", bid)
                AccessibilityEngine.simulatePaste(text)
            }
            return
        }

        let delays: [Double] = [0.15, 0.30, 0.50]
        guard attempt <= delays.count else {
            NSLog("[GhostType][Replace] All attempts exhausted, falling back to simulatePaste")
            AccessibilityEngine.simulatePaste(text)
            return
        }

        let delay = delays[attempt - 1]
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            if let element = targetElement,
               AccessibilityEngine.replaceTextInRange(range, with: text, on: element) {
                NSLog("[GhostType][Replace] Success on attempt %d (delay: %.2fs)", attempt, delay)
                return
            }
            NSLog("[GhostType][Replace] Attempt %d failed (delay: %.2fs)", attempt, delay)
            attemptReplacement(text: text, targetElement: targetElement, targetBundleID: targetBundleID, range: range, attempt: attempt + 1)
        }
    }

    // MARK: - Web App Detection

    /// Returns true for apps where AX text insertion silently fails (Chrome, Electron, etc.).
    static func isWebBasedApp(_ bundleID: String) -> Bool {
        bundleID.hasPrefix("com.google.Chrome") ||
        bundleID.hasPrefix("com.microsoft.VSCode") ||
        bundleID.hasPrefix("com.brave.Browser") ||
        bundleID.hasPrefix("com.operasoftware.Opera") ||
        bundleID.hasPrefix("com.tinyspeck.slackmacgap") ||
        bundleID.hasPrefix("com.hnc.Discord") ||
        bundleID.hasPrefix("com.microsoft.teams") ||
        bundleID.hasPrefix("notion.id") ||
        bundleID.hasPrefix("com.figma.Desktop") ||
        bundleID.hasPrefix("com.linear") ||
        bundleID.contains(".electron.")
    }
}
