# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

GhostType is a native macOS AI writing assistant. Press Ctrl+K anywhere on the system, a floating panel appears at the text cursor, type a prompt, and AI-generated text streams back and can be inserted directly into the active app. Think Spotlight for AI writing.

## Build & Run

### Backend (Python >=3.10)

```bash
# First-time setup + run
./scripts/start-backend.sh

# Or manually:
cd backend && python3 -m venv .venv && source .venv/bin/activate
pip install -e ".[dev]"
python server.py  # starts on http://127.0.0.1:8420
```

### Frontend (Swift, no Xcode IDE required)

```bash
cd ghosttype  # project root with Package.swift
./scripts/run.sh  # builds SPM, creates .app bundle, launches
```

### Tests

```bash
# Backend (pytest, asyncio_mode=auto — no @pytest.mark.asyncio needed)
cd backend && source .venv/bin/activate
python -m pytest tests/ -v
python -m pytest tests/test_server.py::TestStreamingCallbackHandler::test_token_streaming -v

# Frontend (swift-testing 6.0)
swift test  # from project root
```

## Architecture

Two-process architecture: native Swift menu bar app + Python backend. The primary communication path is **stdio pipes** (Swift launches Python as a managed subprocess). A legacy WebSocket path (`server.py` on `localhost:8420`) is kept as fallback.

### Data flow (stdio subprocess — primary)

```
Ctrl+K → HotkeyManager → PanelManager.show() → AccessibilityEngine.getCursorInfo()
  → Panel at cursor → User types → GenerationService.generate()
  → SubprocessManager writes JSON line to Python stdin
  → Python stdio_server.py: Strands Agent runs → streams tokens to stdout
  → SubprocessManager reads stdout lines → AppState.appendToken() → UI renders
  → Insert → TextInsertionService → AccessibilityEngine.insertText() (AX API, fallback Cmd+V paste)
```

### Data flow (WebSocket — legacy fallback)

```
Ctrl+K → HotkeyManager → PanelManager → WebSocketClient.generate()
  → FastAPI /generate WS → Strands Agent → StreamingCallbackHandler → tokens via WS
  → PromptPanelView renders → Insert → AccessibilityEngine.insertText()
```

### Backend (`backend/`)

**Agent system** — agents are defined declaratively in `agents/agents.yaml`, loaded by `AgentRegistry` into immutable `AgentDefinition` snapshots. Each agent specifies a system prompt file, tool list, MCP servers, supported modes, and optional `app_mappings` for auto-selection by active app bundle ID. The `ToolRegistry` maps tool name strings to `@tool` function objects.

**Stdio server** (`stdio_server.py`): Primary backend entry point. Reads JSON lines from stdin, writes events to stdout. `StdioCallbackHandler` writes tokens directly to stdout (no async bridging needed). Agent runs in a thread with 120s timeout. Much simpler than the WebSocket path (~200 lines vs ~800).

**Legacy server** (`server.py`): FastAPI with `/generate` WebSocket, `/health` GET, `/agents` GET. `StreamingCallbackHandler` bridges Strands' sync callbacks to async WebSocket. Kept as fallback.

**Agent lifecycle** (`agent.py`): One agent per WebSocket connection (enables multi-turn). Agent is recreated when config, mode type, or agent ID changes; otherwise reused (preserves conversation history). `ModelConfig` dataclass merges per-request config with env var defaults. Memory context is injected into system prompt on agent creation.

**Mode types**: "draft" (writing/editing — restrictive prompt, raw text output) vs "chat" (conversational — relaxed prompt, markdown). Auto-classified from request mode and context presence, or client can specify `mode_type` explicitly.

**Memory** (`tools/memory_tools.py`): Persistent JSON file at `~/.config/ghosttype/memories.json`. Memories are injected into system prompt via `build_memory_context()`. Memory tools (`save_memory`, `recall_memories`, `forget_memory`) are always available regardless of agent definition.

**Browser context** (`browser_context.py`): `BrowserContext` (frozen dataclass) + thread-safe `BrowserContextStore`. The Chrome extension POSTs page content to `POST /browser-context`; the frontend reads it via `GET /browser-context`. During generation, if the client sends `"include_browser_context": true`, the server injects the stored page content (truncated to 10K chars) into the agent prompt via `build_message()`.

**MCP** (`mcp_manager.py`): Loads server definitions from `mcp_config.json`. Creates fresh `MCPClient` instances per agent — the Strands Agent manages subprocess lifecycle internally. Agents can specify which MCP servers they need via `mcp_servers` in their definition.

### Frontend (`GhostType/`)

SPM package split into `GhostTypeLib` (library) and `GhostType` (executable in `GhostTypeMain/`). Uses `main.swift` with manual `NSApplication` bootstrap (not `@main`) because SwiftUI `@main` requires Xcode-managed bundles.

**App** (`App/`):
- `AppState` — single `ObservableObject`, shared via `@EnvironmentObject`. Holds all UI state, WebSocket client, session store, agent service, and settings.
- `AppDelegate` — `NSApplicationDelegate` handling app lifecycle, dock icon hiding, menu bar setup.

**Core** (`Core/`):
- `HotkeyManager` — global Ctrl+K via `CGEventTap` (intercepts and consumes)
- `AccessibilityEngine` — AX API: cursor position, selected text, text insertion
- `FloatingPanel` — `NSPanel` subclass, non-activating (`.nonactivatingPanel`), resizable, no title bar buttons. Default 480x640, min 380x300, max 1200x900.
- `PanelManager` — creates/positions panel, handles coordinate conversion (AX top-left vs NSWindow bottom-left), key event monitoring (Escape dismiss, Cmd+Enter submit)
- `WebSocketClient` — legacy `URLSessionWebSocketTask`, health poll every 10s, auto-reconnect (fallback path)
- `AgentService` — fetches agent definitions from `GET /agents` (legacy)
- `SessionStore` — persists conversations as JSON at `~/.config/ghosttype/sessions/`
- `BrowserContextService` — fetches browser context from `GET /browser-context` (legacy)

**Services** (`Services/`):
- `SubprocessManager` — manages Python subprocess via stdin/stdout JSON lines (primary backend communication)
- `GenerationService` — orchestrates AI generation via SubprocessManager, streams events to AppState
- `TextInsertionService` — handles text insertion into target app via AX API or simulated paste

**UI** (`UI/`):
- `PromptPanelView` (~300 lines) — main prompt panel orchestrator. Decomposed into sub-views: `HeaderBar`, `ConversationView`, `ResponseArea`, `PromptInputBar`, `ActionBar`, `ContextIndicators`.
- `AutoGrowingTextView` — `NSTextView` wrapped for SwiftUI, grows vertically as text is entered. Handles Shift+Enter (newline) vs Enter (submit).
- `MarkdownView` — rendered markdown responses with syntax highlighting (Highlightr).
- `HistorySidebarView`/`SessionDetailView` — session history browser.

**Models** (`Models/`):
- `AgentInfo` — agent definition from backend, includes `agentForBundle()` for auto-selection
- `Session`/`SessionMessage` — conversation persistence model

### Chrome Extension (`chrome-extension/`)

Manifest V3 extension that captures active tab content and POSTs it to the backend's `/browser-context` endpoint. `content.js` extracts page text on navigation; `background.js` relays it to the backend. The popup (`popup.html`/`popup.js`) shows connection status. Load as an unpacked extension in `chrome://extensions`.

### Communication Protocol

**Primary (stdio)**: Swift launches `stdio_server.py` as a subprocess. Line-delimited JSON on stdin/stdout.

**Legacy (WebSocket)**: `ws://127.0.0.1:8420/generate`. Health: `GET /health`. Agents: `GET /agents`. Browser context: `POST /browser-context`, `GET /browser-context`.

Client → Server:
```json
{"prompt": "...", "context": "...", "mode": "generate|rewrite|fix|translate",
 "mode_type": "draft|chat", "agent": "general|coding|email",
 "screenshot": "base64 JPEG", "config": {"provider": "bedrock", ...}}
{"type": "cancel"}
{"type": "new_conversation"}
```

Server → Client:
```json
{"type": "token", "content": "word"}
{"type": "tool_start", "tool_name": "...", "tool_id": "..."}
{"type": "tool_done", "tool_name": "...", "tool_id": "...", "tool_input": "..."}
{"type": "done", "content": "full response"}
{"type": "error", "content": "message"}
{"type": "cancelled"}
{"type": "conversation_reset"}
```

## Important Patterns

- **Non-activating panel**: The `NSPanel` must remain non-activating — stealing focus from the target app breaks AX text insertion. Never change the `.nonactivatingPanel` style mask. Title bar buttons are hidden; the panel is dismissed via Escape.
- **Static panel sizing**: The panel is a fixed 480x640 GPT-style chat window (user-resizable). `AppState.panelWidth` is a `let` constant — no dynamic resize based on content. Content scrolls within the panel instead of the panel growing. This eliminates the `intrinsicContentSize` deadlock that occurred when `resizePanelToFit()` triggered SwiftUI layout during token streaming.
- **Text insertion dual strategy**: AX API direct set preferred, simulated Cmd+V paste as fallback. Web apps (Chrome/Electron) skip AX retries and paste directly.
- **Coordinate conversion**: AX API uses top-left origin, NSWindow uses bottom-left. Formula: `cocoaY = primaryScreen.frame.height - cgY`.
- **Thread bridging (stdio)**: `StdioCallbackHandler` writes directly to stdout from the agent thread — no async bridging needed. Thread-safe via `_stdout_lock`.
- **Thread bridging (legacy WebSocket)**: `StreamingCallbackHandler` runs in a worker thread, schedules async sends via `asyncio.run_coroutine_threadsafe`. Cancellation is checked on every callback.
- **StubAgent fallback**: When backend is unavailable, the frontend falls back to `StubAgent` for simulated responses.
- **Agent reuse**: The agent is preserved across turns within a WebSocket connection. Only recreated when config/mode/agent changes. `AppState.targetElement` must not be cleared until after insertion completes.
- **Immutable data**: `AgentDefinition`, `AgentRegistrySnapshot`, `ModelConfig` are frozen/immutable dataclasses. Config is loaded once at module level.
- **Memory always available**: Memory tools are appended to every agent's tool list regardless of what `agents.yaml` specifies.
- **Accessibility permission**: Required for AX APIs. Without it, APIs silently return nil.
- **Keyboard shortcuts**: Enter submits prompt, Shift+Enter inserts newline, Cmd+Enter queues a submit during active generation (fires automatically when generation completes), Escape dismisses panel.
- **@Published animation guard**: `AppState` properties that trigger animations use `didSet` guards (not `willSet`) to prevent initial `@Published` emission from breaking animations on view appear. See commit `d79bd40`.

## Configuration

Env vars serve as defaults; the frontend Settings UI overrides per-request. Persistent defaults at `~/.config/ghosttype/default.json`.

| Variable | Default | Purpose |
|---|---|---|
| `GHOSTTYPE_PROVIDER` | `bedrock` | Model provider |
| `GHOSTTYPE_MODEL_ID` | `global.anthropic.claude-opus-4-6-v1` | Model identifier |
| `GHOSTTYPE_AWS_PROFILE` | `""` (falls back to `AWS_PROFILE`) | AWS profile for Bedrock |
| `GHOSTTYPE_AWS_REGION` | `us-west-2` | AWS region for Bedrock |
| `GHOSTTYPE_MAX_TOKENS` | `2048` | Max generation tokens |
| `GHOSTTYPE_TEMPERATURE` | `0.7` | Generation temperature |
| `GHOSTTYPE_LOG_LEVEL` | `DEBUG` | Python logging level |

## Known Limitations

- **Chrome/Electron caret position**: No macOS API can get precise caret position from Chrome. Panel falls back to window-corner positioning.
- **Single hotkey**: Ctrl+K is hardcoded; no UI for remapping.
- **Bedrock-only provider**: `create_model()` currently only implements the `bedrock` provider path.
