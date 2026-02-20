import Cocoa
import SwiftUI

public class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    private var statusItem: NSStatusItem!
    private var hotkeyManager: HotkeyManager!
    private var panelManager: PanelManager!
    private var settingsWindow: NSWindow?

    public override init() {
        super.init()
    }

    public func applicationDidFinishLaunching(_ notification: Notification) {
        NSLog("[GhostType] App launching...")

        // Hide dock icon — menu bar only
        NSApp.setActivationPolicy(.accessory)

        setupMainMenu()
        setupMenuBar()
        setupHotkey()
        setupPanel()
        setupBackend()
        requestAccessibilityPermission()

        NSLog("[GhostType] App ready. Menu bar icon active. Press Ctrl+K to open panel.")
    }

    public func applicationWillTerminate(_ notification: Notification) {
        appState.wsClient.stopHealthChecks()
        appState.wsClient.disconnect()
    }

    // MARK: - Main Menu (enables Cmd+C/V/X/A/Z in the floating panel)

    private func setupMainMenu() {
        let mainMenu = NSMenu()

        let editMenu = NSMenu(title: "Edit")
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let editMenuItem = NSMenuItem(title: "Edit", action: nil, keyEquivalent: "")
        editMenuItem.submenu = editMenu
        mainMenu.addItem(editMenuItem)

        NSApp.mainMenu = mainMenu
    }

    // MARK: - Menu Bar

    private func setupMenuBar() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            if let iconData = Data(base64Encoded: Self.menuIconBase64),
               let icon = NSImage(data: iconData) {
                icon.isTemplate = false
                icon.size = NSSize(width: 18, height: 18)
                button.image = icon
            }
        }

        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show GhostType (Ctrl+K)", action: #selector(showPanel), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit GhostType", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    // MARK: - Hotkey

    private func setupHotkey() {
        hotkeyManager = HotkeyManager { [weak self] in
            self?.togglePanel()
        }
    }

    // MARK: - Panel

    private func setupPanel() {
        panelManager = PanelManager(appState: appState)
    }

    @objc private func showPanel() {
        panelManager.show()
    }

    private func togglePanel() {
        panelManager.toggle()
    }

    // MARK: - Backend

    private func setupBackend() {
        NSLog("[GhostType] Starting backend health checks...")
        appState.wsClient.startHealthChecks(interval: 10)
    }

    // MARK: - Accessibility

    private func requestAccessibilityPermission() {
        let options: NSDictionary = [
            kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true
        ]
        let accessEnabled = AXIsProcessTrustedWithOptions(options)
        appState.accessibilityGranted = accessEnabled
    }

    // MARK: - Settings Window

    @objc private func openSettings() {
        if let existing = settingsWindow, existing.isVisible {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsView = SettingsView()
            .environmentObject(appState)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 520),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "GhostType Settings"
        window.contentView = NSHostingView(rootView: settingsView)
        window.center()
        window.isReleasedWhenClosed = false
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow = window
    }


    // MARK: - Menu Bar Icon (embedded PNG)

    // swiftlint:disable:next line_length
    private static let menuIconBase64 = "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"

    // MARK: - Actions

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }
}
