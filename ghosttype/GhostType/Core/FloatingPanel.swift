import Cocoa

/// Custom NSPanel that can become key (for text input) while remaining non-activating.
///
/// Two overrides are critical:
/// 1. `canBecomeKey → true` — allows keyboard input in the panel.
/// 2. `becomesKeyOnlyIfNeeded = false` — makes the panel become key on
///    `makeKeyAndOrderFront` WITHOUT requiring the user to click a text
///    field first. The default for .nonactivatingPanel is `true`, which
///    defeats programmatic focus.
class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override init(
        contentRect: NSRect,
        styleMask: NSWindow.StyleMask,
        backing: NSWindow.BackingStoreType,
        defer flag: Bool
    ) {
        super.init(contentRect: contentRect, styleMask: styleMask, backing: backing, defer: flag)
        self.becomesKeyOnlyIfNeeded = false
    }
}
