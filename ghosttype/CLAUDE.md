# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

GhostType is a native macOS AI writing assistant. Press Ctrl+K anywhere on the system, a floating panel appears at the text cursor, type a prompt, and AI-generated text streams back and can be inserted directly into the active app. Think Spotlight for AI writing.

## Build & Run

### Backend (Python >=3.10, managed by uv)

```bash
cd backend && uv sync --group dev  # first-time setup
# Backend launches automatically as a subprocess when the Swift app starts.
```

### Frontend (Swift 5.9, SPM, no Xcode IDE required)

```bash
./scripts/run.sh  # builds SPM, creates .app bundle, launches (backend starts automatically)
```

### Tests

```bash
# Backend
cd backend
uv run --group dev python -m pytest tests/ -v                    # all tests
uv run --group dev python -m pytest tests/test_stdio_server.py -v  # one file
uv run --group dev python -m pytest tests/test_stdio_server.py::TestStdioCallbackHandler::test_token_streaming -v  # one test

# Frontend (swift-testing 6.0 framework)
swift test  # from project root
```

pytest is configured with `asyncio_mode = "auto"` — async test functions work without `@pytest.mark.asyncio`.

## Architecture

Two-process architecture: native Swift menu bar app + Python backend connected via **stdio pipes** (Swift launches Python as a managed subprocess via `uv run`). A minimal HTTP server on port 8420 handles Chrome extension browser context only.

### Data flow

```
Ctrl+K → HotkeyManager → PanelManager.show() → AccessibilityEngine.getCursorInfo()
  → Panel at cursor → User types → GenerationService.generate()
  → SubprocessManager writes JSON line to Python stdin
  → stdio_server.py: Strands Agent runs → streams tokens to stdout
  → SubprocessManager reads stdout lines → AppState.appendToken() → UI renders
  → Insert → TextInsertionService → AccessibilityEngine.insertText() (AX API, fallback Cmd+V paste)
```

### Backend (`backend/`)

`stdio_server.py` is the sole entry point. Reads JSON lines from stdin, writes events to stdout. `StdioCallbackHandler` writes tokens directly from the agent thread (thread-safe via `_stdout_lock`). Agent runs in a thread with 120s timeout. Also spawns a minimal `http.server` thread on port 8420 for Chrome extension browser context.

**Agent system**: Agents are defined declaratively in `agents/agents.yaml`, loaded by `AgentRegistry` into immutable `AgentDefinition` snapshots. Each agent specifies a system prompt file (in `prompts/`), tool list, MCP servers, supported modes, and optional `app_mappings` for auto-selection by active app bundle ID. Three agents: `general` (default), `coding`, `email`. `ToolRegistry` maps tool name strings to `@tool` function objects.

**Agent lifecycle** (`agent.py`): One agent per subprocess session (enables multi-turn). Agent is recreated when config, mode type, or agent ID changes; otherwise reused (preserves conversation history). `ModelConfig` dataclass merges per-request config with env var defaults.

**Mode types**: "draft" (writing/editing — restrictive prompt, raw text output) vs "chat" (conversational — relaxed prompt, markdown). Auto-classified from request mode and context presence, or client can specify `mode_type` explicitly.

**Memory** (`tools/memory_tools.py`): Persistent JSON at `~/.config/ghosttype/memories.json`. Injected into system prompt on agent creation. Memory tools (`save_memory`, `recall_memories`, `forget_memory`) are always available regardless of agent definition.

**Browser context** (`browser_context.py`): Chrome extension POSTs page content to `POST /browser-context`; during generation, if client sends `"include_browser_context": true`, stored page content (truncated to 10K chars) is injected into the agent prompt.

### Frontend (`GhostType/`)

SPM package split into `GhostTypeLib` (library at `GhostType/`) and `GhostType` (executable at `GhostTypeMain/`). Uses `main.swift` with manual `NSApplication` bootstrap (not `@main`) because SwiftUI `@main` requires Xcode-managed bundles.

`AppState` is the single `ObservableObject` shared via `@EnvironmentObject`. Split into extensions: `AppState+Generation.swift` (token batching, tool calls) and `AppState+Session.swift` (persistence, resume).

Key services: `SubprocessManager` (launches Python via `uv run`, stdin/stdout JSON pipes), `GenerationService` (orchestrates generation, errors if subprocess unavailable), `ModeDetector` (classifies prompt intent), `TextInsertionService` (AX API + paste fallback).

Dependency injection via protocols in `Core/Protocols.swift`: `AccessibilityProvider`, `SubprocessProvider`, `SessionStorage`.

### Chrome Extension (`chrome-extension/`)

Manifest V3 extension that captures active tab content and POSTs to `/browser-context` on port 8420. Load as unpacked extension in `chrome://extensions`.

### Communication Protocol

**Stdio (primary)**: Line-delimited JSON on stdin/stdout.

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
{"type": "token|tool_start|tool_done|done|error|cancelled|conversation_reset", ...}
```

**HTTP (Chrome extension only)**: `POST /browser-context`, `GET /browser-context`, `GET /health` on port 8420.

## Important Patterns

- **Non-activating panel**: `NSPanel` must keep `.nonactivatingPanel` style — stealing focus breaks AX text insertion. Title bar buttons hidden; dismiss via Escape.
- **Static panel sizing**: Fixed 480x640, user-resizable. `AppState.panelWidth` is a `let` constant — no dynamic resize. Content scrolls. This avoids `intrinsicContentSize` deadlock during token streaming.
- **Text insertion dual strategy**: AX API direct set preferred, simulated Cmd+V paste fallback. Web apps (Chrome/Electron) skip AX retries and paste directly.
- **Coordinate conversion**: AX API uses top-left origin, NSWindow uses bottom-left. Formula: `cocoaY = primaryScreen.frame.height - cgY`.
- **Action triggers**: Key events (Enter, Cmd+Enter, Escape) route from `PanelManager` to `PromptPanelView` via `@Published` UInt counters on AppState (`enterAction`, `submitAction`, `dismissAction`).
- **@Published animation guard**: `AppState` properties that trigger animations use `didSet` guards (not `willSet`) to prevent initial `@Published` emission from breaking animations on view appear.
- **Immutable data**: `AgentDefinition`, `AgentRegistrySnapshot`, `ModelConfig` are frozen/immutable dataclasses. Config is loaded once at module level.
- **targetElement lifecycle**: `AppState.targetElement` (AX reference captured at panel-open) must not be cleared until after text insertion completes.
- **Keyboard shortcuts**: Enter = submit, Shift+Enter = newline, Cmd+Enter = queue submit during active generation, Escape = dismiss.
- **Accessibility permission**: Required for AX APIs. Without it, APIs silently return nil (no error thrown).
- **Bedrock-only provider**: `create_model()` currently only implements the `bedrock` provider path.

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
