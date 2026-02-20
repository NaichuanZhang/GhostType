import Cocoa
import Carbon

/// Manages global keyboard shortcut registration (Ctrl+K by default).
///
/// Uses a CGEventTap to intercept the hotkey before it reaches the focused app.
/// This prevents conflicts — the target app never sees the keystroke.
/// Falls back to NSEvent monitors if the event tap can't be created.
class HotkeyManager {
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private let onTrigger: () -> Void

    // Default hotkey: Ctrl+K
    private static let hotkeyCode: UInt16 = 0x28 // kVK_ANSI_K
    private static let hotkeyModifiers: CGEventFlags = .maskControl

    init(onTrigger: @escaping () -> Void) {
        self.onTrigger = onTrigger

        if !registerEventTap() {
            // Fallback: NSEvent monitors (cannot intercept, only observe)
            NSLog("[GhostType] CGEventTap unavailable, falling back to NSEvent monitors")
            registerGlobalMonitor()
        }
        registerLocalMonitor()

        NSLog("[GhostType] HotkeyManager initialized (Ctrl+K)")
    }

    deinit {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            if let source = runLoopSource {
                CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
            }
        }
        if let monitor = globalMonitor {
            NSEvent.removeMonitor(monitor)
        }
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
        }
    }

    // MARK: - CGEventTap (primary — intercepts the event)

    private func registerEventTap() -> Bool {
        // Store a reference to self for the C callback
        let refcon = Unmanaged.passUnretained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,  // Can modify/suppress events
            eventsOfInterest: CGEventMask(1 << CGEventType.keyDown.rawValue),
            callback: { (proxy, type, event, refcon) -> Unmanaged<CGEvent>? in
                guard let refcon = refcon else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                return manager.handleCGEvent(proxy: proxy, type: type, event: event)
            },
            userInfo: refcon
        ) else {
            return false
        }

        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let source = runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    private func handleCGEvent(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        // Re-enable tap if it gets disabled (system can disable taps under load)
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let flags = event.flags

        // Check for Ctrl+K (only Ctrl, no Cmd/Shift/Option)
        let hasCtrl = flags.contains(.maskControl)
        let hasCmd = flags.contains(.maskCommand)
        let hasShift = flags.contains(.maskShift)
        let hasOpt = flags.contains(.maskAlternate)

        if hasCtrl && !hasCmd && !hasShift && !hasOpt && keyCode == Self.hotkeyCode {
            DispatchQueue.main.async { [weak self] in
                self?.onTrigger()
            }
            // Return nil to consume the event — the focused app never sees it
            return nil
        }

        return Unmanaged.passUnretained(event)
    }

    // MARK: - NSEvent Monitors (fallback)

    private func registerGlobalMonitor() {
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleNSEvent(event)
        }
    }

    private func registerLocalMonitor() {
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.handleNSEvent(event) == true {
                return nil
            }
            return event
        }
    }

    @discardableResult
    private func handleNSEvent(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .control && event.keyCode == Self.hotkeyCode {
            DispatchQueue.main.async { [weak self] in
                self?.onTrigger()
            }
            return true
        }
        return false
    }
}
