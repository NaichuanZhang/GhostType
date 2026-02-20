# GhostType - macOS AI Writing Assistant

## Vision
A native macOS app that brings AI-powered text generation to any application.
Press Cmd+K anywhere, a floating popup appears at your cursor, type a prompt,
and the AI-generated text streams directly into wherever you're typing.

Think: Spotlight for AI writing, or Cursor's Cmd+K — but system-wide.

---

## Architecture Overview

```
+------------------------------------------------------------------+
|                        macOS (System-Wide)                        |
|                                                                   |
|  +------------------+     +-----------------------------------+   |
|  |  Any App         |     |  GhostType.app (Swift/SwiftUI)    |   |
|  |  (Notes, Mail,   |     |                                   |   |
|  |   Chrome, Slack,  |     |  +-----------------------------+  |   |
|  |   VS Code, etc.) |     |  | Global Hotkey Monitor       |  |   |
|  |                  |     |  | (NSEvent.addGlobalMonitor)   |  |   |
|  |  [cursor here]   |     |  +-----------------------------+  |   |
|  |       |          |     |                |                   |   |
|  +-------|----------+     |  +-----------------------------+  |   |
|          |                |  | Accessibility Engine         |  |   |
|          | AX API         |  | - Get cursor screen position |  |   |
|          |                |  | - Get focused element        |  |   |
|          |                |  | - Insert text (AX / Paste)   |  |   |
|          |                |  +-----------------------------+  |   |
|          |                |                |                   |   |
|          |                |  +-----------------------------+  |   |
|          |                |  | Floating Panel (NSPanel)     |  |   |
|          |                |  | - Prompt input field         |  |   |
|          |                |  | - Streaming response view    |  |   |
|          |                |  | - Action buttons             |  |   |
|          |                |  +-----------------------------+  |   |
|          |                |                |                   |   |
|          |                +----------------|------------------+   |
|          |                                 |                      |
+----------|-------- macOS ------------------|----------------------+
           |                                 | HTTP/WebSocket
           |                                 | (localhost)
           |                                 |
     +-----|------ Backend Process ----------|----+
     |     |                                 |    |
     |  +--|---------------------------------|-+  |
     |  |  v     Strands Agent Server        v |  |
     |  |                                      |  |
     |  |  FastAPI / WebSocket Server          |  |
     |  |  +---------------------------------+ |  |
     |  |  | Strands Agent                   | |  |
     |  |  | - System prompt (context-aware) | |  |
     |  |  | - Custom tools (@tool)          | |  |
     |  |  | - Streaming callback handler    | |  |
     |  |  +---------------------------------+ |  |
     |  |  |  Model Provider (configurable)  | |  |
     |  |  |  - Anthropic Claude             | |  |
     |  |  |  - Amazon Bedrock               | |  |
     |  |  |  - OpenAI                       | |  |
     |  |  |  - Ollama (local)               | |  |
     |  |  +---------------------------------+ |  |
     |  +--------------------------------------+  |
     +--------------------------------------------+
```

---

## Frontend: Native Swift/SwiftUI (Recommended)

### Why Swift/SwiftUI over alternatives

| Criteria                  | Swift/SwiftUI | Tauri v2    | Electron     |
|--------------------------|---------------|-------------|--------------|
| App size                 | ~5-10 MB      | ~15-30 MB   | ~100+ MB     |
| Memory usage             | ~20-40 MB     | ~50-80 MB   | ~150-300 MB  |
| Accessibility API access | Native/Direct | Rust plugin | Node addon   |
| Floating window support  | NSPanel native| Private API | BrowserWindow|
| Cursor position tracking | AX API direct | Complex     | Very complex |
| Text insertion           | AX API direct | Complex     | Very complex |
| macOS feel               | Perfect       | Good        | Poor         |
| Global shortcut          | NSEvent       | Plugin      | globalShortcut|
| Startup time             | Instant       | Fast        | Slow         |

**Verdict: Swift/SwiftUI is the clear winner** for this use case because:

1. **Accessibility APIs are critical** — Getting cursor position and inserting
   text into arbitrary apps requires `AXUIElement` APIs. These are native C/ObjC
   APIs that Swift can call directly. Tauri/Electron need FFI bridges.

2. **NSPanel provides true floating windows** — A `NSPanel` with
   `.nonactivatingPanel` style mask and `.floating` level sits above all apps
   without stealing focus. This is exactly what Spotlight, Raycast, and InlineAI use.

3. **The app is a utility, not a content app** — It should feel like part of
   macOS itself. Native is the only way to achieve this.

### Key macOS APIs Used

#### 1. Global Hotkey (Cmd+K)
```swift
// Register system-wide keyboard shortcut
NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { event in
    if event.modifierFlags.contains(.command) && event.keyCode == 40 { // 'K'
        showPromptPanel()
    }
}
```

#### 2. Get Cursor Screen Position (Accessibility API)
```swift
let systemWide = AXUIElementCreateSystemWide()
var focusedElement: CFTypeRef?
AXUIElementCopyAttributeValue(systemWide, kAXFocusedUIElementAttribute as CFString, &focusedElement)

// Get selected text range
var selectedRange: CFTypeRef?
AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &selectedRange)

// Get screen bounds of that range
var bounds: CFTypeRef?
AXUIElementCopyParameterizedAttributeValue(
    element,
    kAXBoundsForRangeParameterizedAttribute as CFString,
    selectedRange!,
    &bounds
)
// bounds now contains the CGRect in screen coordinates
```

#### 3. Floating Panel (Non-Activating)
```swift
class PromptPanel: NSPanel {
    init() {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
            styleMask: [.nonactivatingPanel, .fullSizeContentView, .borderless],
            backing: .buffered,
            defer: false
        )
        self.level = .floating
        self.isOpaque = false
        self.backgroundColor = .clear
        self.hasShadow = true
        self.isMovableByWindowBackground = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
    }
}
```

#### 4. Insert Text into Active App
Two approaches (use both with fallback):

**Approach A: Accessibility API (preferred, no clipboard pollution)**
```swift
AXUIElementSetAttributeValue(
    focusedElement,
    kAXSelectedTextAttribute as CFString,
    generatedText as CFTypeRef
)
```

**Approach B: Simulated Paste (fallback for Electron apps, web apps)**
```swift
let pasteboard = NSPasteboard.general
let previousContents = pasteboard.string(forType: .string)
pasteboard.clearContents()
pasteboard.setString(generatedText, forType: .string)

// Simulate Cmd+V
let source = CGEventSource(stateID: .hidSystemState)
let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true) // V
keyDown?.flags = .maskCommand
let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
keyUp?.flags = .maskCommand
keyDown?.post(tap: .cghidEventTap)
keyUp?.post(tap: .cghidEventTap)

// Restore clipboard after brief delay
DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
    pasteboard.clearContents()
    if let prev = previousContents {
        pasteboard.setString(prev, forType: .string)
    }
}
```

### UI Design

```
+-----------------------------------------------+
|  GhostType                              [x]   |
|-----------------------------------------------|
|                                               |
|  > What do you want to write?                 |
|  +-------------------------------------------+|
|  | Write a professional email declining the  ||
|  | meeting invitation...                     ||
|  +-------------------------------------------+|
|                                               |
|  Context: [Selected text: 47 chars]  [None]   |
|                                               |
|  [Generate]              [Cmd+Enter]          |
+-----------------------------------------------+

          ↓ (streaming response)

+-----------------------------------------------+
|  GhostType                              [x]   |
|-----------------------------------------------|
|                                               |
|  > Write a professional email declining...    |
|                                               |
|  ┌─────────────────────────────────────────┐  |
|  │ Thank you for the invitation to the     │  |
|  │ quarterly review meeting. Unfortunately,│  |
|  │ I have a scheduling conflict and won't  │  |
|  │ be able to attend. Could you please     │  |
|  │ share the meeting notes afterward?      │  |
|  │                                         │  |
|  │ Best regards█                           │  |
|  └─────────────────────────────────────────┘  |
|                                               |
|  [Insert ↵]  [Copy]  [Retry ↻]  [Cancel]     |
+-----------------------------------------------+
```

Visual design principles:
- **Vibrancy/blur background** (NSVisualEffectView) — matches macOS aesthetic
- **Compact** — never larger than 400x300pt
- **Dark/Light mode** — automatic via system appearance
- **Rounded corners** — 12pt corner radius
- **Subtle shadow** — matches native macOS panels
- **Typography** — SF Pro (system font), 13pt body, 11pt labels

---

## Backend: Strands Agents SDK (Python)

### Why Strands

1. **Model-driven** — The LLM drives the agent loop, not rigid code
2. **Multi-provider** — Swap between Claude, GPT-4, Bedrock, Ollama seamlessly
3. **Streaming** — Built-in event streaming for real-time token delivery
4. **Custom tools** — Easy `@tool` decorator for extending capabilities
5. **MCP support** — Connect to any MCP server for external tools
6. **Production-ready** — Used by AWS teams internally

### Backend Server Design

```python
# server.py — FastAPI + WebSocket server wrapping Strands Agent

from fastapi import FastAPI, WebSocket
from strands import Agent, tool
from strands.models.anthropic import AnthropicModel
import json

app = FastAPI()

# Configure model provider
model = AnthropicModel(
    model_id="claude-sonnet-4-20250514",
    max_tokens=4096,
)

# System prompt for writing assistance
SYSTEM_PROMPT = """You are GhostType, an AI writing assistant embedded in macOS.
You help users write, edit, and transform text directly where they're typing.

Rules:
- Output ONLY the requested text. No explanations, no markdown, no quotes.
- Match the tone and style of any provided context.
- Be concise unless explicitly asked to elaborate.
- If given selected text as context, transform/edit it as requested.
- For new text generation, produce ready-to-use content.
"""

@tool
def get_clipboard_context(text: str) -> str:
    """Get the selected text context from the active application."""
    return text

@app.websocket("/generate")
async def generate(websocket: WebSocket):
    await websocket.accept()

    while True:
        data = await websocket.receive_text()
        request = json.loads(data)

        prompt = request["prompt"]
        context = request.get("context", "")
        mode = request.get("mode", "generate")  # generate | rewrite | fix

        # Build the user message
        if context:
            user_message = f"Context (selected text): {context}\n\nTask: {prompt}"
        else:
            user_message = prompt

        # Create agent with streaming callback
        agent = Agent(
            model=model,
            system_prompt=SYSTEM_PROMPT,
            callback_handler=None,  # We handle streaming manually
        )

        # Stream tokens via websocket
        result = agent(user_message)

        # Send chunks as they arrive
        for event in result.stream:
            if hasattr(event, 'data'):
                await websocket.send_text(json.dumps({
                    "type": "token",
                    "content": event.data
                }))

        await websocket.send_text(json.dumps({
            "type": "done",
            "content": str(result)
        }))


@app.get("/health")
def health():
    return {"status": "ok"}
```

### Streaming Architecture

```
Swift App                    Python Server               LLM API
   |                              |                         |
   |-- WS: {prompt, context} --> |                         |
   |                              |-- API call (stream) --> |
   |                              |                         |
   |                              | <-- token chunk --------|
   | <-- WS: {type: "token"} --- |                         |
   |   (append to response view) |                         |
   |                              | <-- token chunk --------|
   | <-- WS: {type: "token"} --- |                         |
   |   (append to response view) |                         |
   |                              | <-- [DONE] -------------|
   | <-- WS: {type: "done"} ---- |                         |
   |                              |                         |
   |   User clicks [Insert]      |                         |
   |   → AX API insert text      |                         |
```

---

## Project Structure

```
ghosttype/
├── GhostType/                          # Xcode project (Swift/SwiftUI)
│   ├── App/
│   │   ├── GhostTypeApp.swift          # App entry point, menu bar setup
│   │   ├── AppDelegate.swift           # NSApplicationDelegate, lifecycle
│   │   └── AppState.swift              # Global app state (ObservableObject)
│   │
│   ├── Core/
│   │   ├── HotkeyManager.swift         # Global Cmd+K hotkey registration
│   │   ├── AccessibilityEngine.swift   # AX API: cursor pos, text insertion
│   │   ├── PanelManager.swift          # NSPanel creation & positioning
│   │   └── WebSocketClient.swift       # Connects to Python backend
│   │
│   ├── UI/
│   │   ├── PromptPanel/
│   │   │   ├── PromptPanelView.swift   # Main SwiftUI view for the popup
│   │   │   ├── PromptInputView.swift   # Text input field
│   │   │   ├── ResponseStreamView.swift # Streaming response display
│   │   │   └── ActionBarView.swift     # Insert/Copy/Retry/Cancel buttons
│   │   ├── Settings/
│   │   │   ├── SettingsView.swift      # Settings window
│   │   │   ├── ModelPickerView.swift   # Choose AI model/provider
│   │   │   └── ShortcutView.swift      # Customize hotkey
│   │   └── MenuBar/
│   │       └── MenuBarView.swift       # Status bar icon + menu
│   │
│   ├── Models/
│   │   ├── GenerateRequest.swift       # Request model
│   │   ├── GenerateResponse.swift      # Response model (streaming chunks)
│   │   └── AppSettings.swift           # User preferences model
│   │
│   └── Resources/
│       ├── Assets.xcassets             # App icon, colors
│       └── GhostType.entitlements      # Accessibility entitlement
│
├── backend/                            # Python Strands Agent server
│   ├── pyproject.toml                  # Python project config
│   ├── server.py                       # FastAPI + WebSocket server
│   ├── agent.py                        # Strands Agent configuration
│   ├── tools/                          # Custom Strands tools
│   │   ├── __init__.py
│   │   ├── text_tools.py              # Rewrite, summarize, expand, etc.
│   │   └── context_tools.py           # Context-aware tools
│   ├── config.py                       # Model provider configuration
│   └── prompts/
│       ├── system.txt                  # System prompt
│       └── modes/                      # Mode-specific prompts
│           ├── generate.txt
│           ├── rewrite.txt
│           ├── fix_grammar.txt
│           └── translate.txt
│
├── scripts/
│   ├── install.sh                      # One-line installer
│   ├── start-backend.sh                # Launch Python server
│   └── package.sh                      # Build .dmg for distribution
│
└── README.md
```

---

## Implementation Phases

### Phase 1: Core Shell
- [ ] Xcode project setup with SwiftUI lifecycle
- [ ] Menu bar app (LSUIElement = YES, no dock icon)
- [ ] Global Cmd+K hotkey via NSEvent
- [ ] Basic NSPanel popup (floating, non-activating)
- [ ] Accessibility permission request flow

### Phase 2: Cursor Tracking & Text Insertion
- [ ] AccessibilityEngine: get focused element
- [ ] Get cursor/caret screen coordinates via AX API
- [ ] Position NSPanel at cursor location
- [ ] Insert text via AXUIElementSetAttributeValue
- [ ] Fallback: simulated Cmd+V paste
- [ ] Handle edge cases (Electron apps, web textareas)

### Phase 3: Backend Agent
- [ ] Python project with FastAPI + uvicorn
- [ ] Strands Agent with Anthropic provider
- [ ] WebSocket endpoint for streaming
- [ ] System prompt for writing assistance
- [ ] Custom tools: rewrite, fix_grammar, expand, shorten, translate
- [ ] Configuration for multiple model providers

### Phase 4: Frontend-Backend Integration
- [ ] WebSocketClient in Swift (URLSessionWebSocketTask)
- [ ] Streaming token display in SwiftUI
- [ ] Request/response lifecycle management
- [ ] Error handling and retry logic
- [ ] Loading states and animations

### Phase 5: Polish & UX
- [ ] NSVisualEffectView vibrancy background
- [ ] Smooth panel show/hide animations
- [ ] Dark/Light mode support
- [ ] Selected text context indicator
- [ ] Quick action buttons (rewrite, fix, expand)
- [ ] Settings window (model, API key, hotkey)
- [ ] Auto-launch backend on app start
- [ ] Bundle Python backend in .app (optional)

### Phase 6: Distribution
- [ ] Code signing & notarization
- [ ] DMG installer with drag-to-Applications
- [ ] Auto-update mechanism (Sparkle framework)
- [ ] Landing page

---

## Key Technical Decisions

### 1. Menu Bar App (No Dock Icon)
Set `LSUIElement = YES` in Info.plist. The app lives in the menu bar like
Bartender, Raycast, etc. The floating panel appears on hotkey — no window
management needed.

### 2. Non-Activating Panel
The popup must NOT steal focus from the target app. Using `NSPanel` with
`.nonactivatingPanel` style mask ensures the target text field retains focus.
This is critical — if focus shifts, we lose the AX reference to the text element.

### 3. Dual Text Insertion Strategy
- **Primary**: `AXUIElementSetAttributeValue` with `kAXSelectedTextAttribute`
  - Works: Native macOS apps (Notes, TextEdit, Pages, Mail, Xcode)
  - Fails: Many Electron apps, some web textareas
- **Fallback**: Simulated Cmd+V paste
  - Works: Everything that supports paste
  - Downside: Pollutes clipboard (mitigated by save/restore)

### 4. Local Backend Server
The Python Strands Agent runs as a local process on `localhost:8420`.
The Swift app manages the process lifecycle (start on launch, kill on quit).
This avoids embedding Python in the .app bundle while keeping latency minimal.

### 5. WebSocket for Streaming
HTTP SSE would also work, but WebSocket is bidirectional — allowing:
- Cancel mid-generation
- Send context updates
- Keep-alive connection (no reconnect overhead per request)

---

## Dependencies

### Swift (via Swift Package Manager)
- `HotKey` (github.com/soffes/HotKey) — Simpler global hotkey API
- `Starscream` (github.com/nicklockwood/Starscream) — WebSocket client (or use native URLSession)

### Python (via pip/uv)
- `strands-agents` — Core agent SDK
- `strands-agents-tools` — Pre-built tools
- `fastapi` — HTTP/WebSocket server
- `uvicorn` — ASGI server
- `websockets` — WebSocket support for FastAPI

---

## Reference Apps
- **InlineAI** (inlineai.app) — Nearly identical concept, native Swift, Cmd+Shift+/
- **Raycast** — Spotlight-like popup UX, non-activating panel
- **Cursor** — Cmd+K inline edit in editor context
- **WritingTools** (github.com/theJayTea/WritingTools) — Open source Apple-style writing tools for all platforms
