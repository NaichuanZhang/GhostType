# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

GhostType is a native macOS AI writing assistant. Press Ctrl+K anywhere on the system, a floating panel appears at the text cursor, type a prompt, and AI-generated text streams back and can be inserted directly into the active app. Think Spotlight for AI writing.

## Architecture

Two-process architecture connected via WebSocket on `localhost:8420`:

- **Frontend** (`ghosttype/GhostType/`): Native Swift/SwiftUI menu bar app (no dock icon, `LSUIElement = YES`). Uses `NSPanel` with `.nonactivatingPanel` to float above all windows without stealing focus. Interacts with any app's text fields via macOS Accessibility (AX) APIs.
- **Backend** (`ghosttype/backend/`): Python FastAPI server wrapping a Strands Agents SDK agent. Receives prompts over WebSocket, runs them through the configured LLM provider, streams token responses back in real time.

### Data flow

```
User presses Ctrl+K → HotkeyManager → PanelManager.show() → AccessibilityEngine.getCursorInfo()
  → Panel positioned at cursor → User types prompt → WebSocketClient.generate()
  → FastAPI /generate WebSocket → Strands Agent (in thread pool) → LLM API (streaming)
  → StreamingCallbackHandler sends each token via WS → PromptPanelView appends to responseText
  → User clicks Insert → AccessibilityEngine.insertText() (AX API, fallback to simulated Cmd+V)
```

### Communication protocol

WebSocket at `ws://127.0.0.1:8420/generate`. HTTP health check at `GET /health`.

Client → Server:
```json
{"prompt": "...", "context": "...", "mode": "generate|rewrite|fix|translate",
 "config": {"provider": "bedrock", "model_id": "...", "aws_profile": "...", "aws_region": "..."}}
{"type": "cancel"}
```

Server → Client:
```json
{"type": "token", "content": "word"}
{"type": "done", "content": "full response"}
{"type": "error", "content": "error message"}
{"type": "cancelled"}
```

The frontend sends per-request `config` with provider, model ID, and credentials. The backend's `ModelConfig` dataclass merges these with env var defaults.

### Key Swift components (GhostType/Core/)

- **HotkeyManager**: Registers global Ctrl+K via `CGEventTap` (intercepts and consumes the event). Falls back to `NSEvent` monitors if the event tap can't be created.
- **AccessibilityEngine**: All AX API interactions — cursor position, selected text, text insertion. Chrome/Electron don't expose caret position via AX — mouse position is used as fallback.
- **FloatingPanel**: Custom `NSPanel` subclass overriding `canBecomeKey` to allow text input in a non-activating panel.
- **PanelManager**: Creates/positions `FloatingPanel`, handles Escape dismiss, coordinate conversion between AX (top-left origin) and NSWindow (bottom-left origin).
- **WebSocketClient**: `URLSessionWebSocketTask`-based client with health checks (polls `/health` every 10s), auto-reconnect with exponential backoff, and per-request config support.
- **StubAgent**: Simulates streaming AI responses for development without a running backend. Used as fallback when backend is unavailable.
- **AppState**: Single `ObservableObject` shared via `@EnvironmentObject`. Holds `wsClient`, UI state, AX target element, and settings (provider, credentials). `modelConfigForRequest()` builds the config dict sent with each generation request.

### Key Python components (backend/)

- **server.py**: FastAPI app with `/generate` WebSocket and `/health` GET. `StreamingCallbackHandler` bridges Strands' synchronous callbacks to async WebSocket — runs agent in thread pool via `asyncio.to_thread`, sends tokens with `asyncio.run_coroutine_threadsafe`. Cancellation via `threading.Event`. `_friendly_error()` converts provider exceptions to user-readable messages.
- **agent.py**: `ModelConfig` dataclass for per-request config (provider, model_id, aws_profile, aws_region, api_key). `create_model()` factory creates the right Strands model with merged config. `create_agent()` wires model + system prompt + tools + callback handler.
- **config.py**: `@dataclass` Config loaded from env vars as defaults. Per-request `ModelConfig` overrides take precedence.

## Build & Run Commands

### Backend (Python, requires >=3.10)

```bash
# First-time setup + run
./ghosttype/scripts/start-backend.sh

# Or manually:
cd ghosttype/backend
python3 -m venv .venv && source .venv/bin/activate
pip install -e ".[anthropic]"  # or .[bedrock], .[openai]
python server.py  # starts on http://127.0.0.1:8420

# Run tests
cd ghosttype/backend
source .venv/bin/activate
pip install -e ".[dev]"        # installs pytest, pytest-asyncio
python -m pytest tests/ -v     # 53 tests across config, agent, server
python -m pytest tests/test_server.py::TestStreamingCallbackHandler -v  # single test class
python -m pytest tests/test_server.py::TestStreamingCallbackHandler::test_token_streaming -v  # single test
```

pytest is configured with `asyncio_mode = "auto"` — async test functions work without the `@pytest.mark.asyncio` decorator.

### Frontend (Swift)

```bash
# Build and run as .app bundle (recommended — creates Info.plist, etc.)
cd ghosttype
./scripts/run.sh

# Or build only with Swift Package Manager
cd ghosttype
swift build
# Binary at .build/debug/GhostType needs .app bundle for menu bar + AX to work.
```

No Xcode IDE required — builds with Swift Package Manager (Swift 5.9, macOS 13+). No tests, linters, or formatters on the Swift side.

### Backend configuration

Env vars serve as defaults. The frontend Settings UI overrides these per-request.

| Variable | Default | Purpose |
|---|---|---|
| `GHOSTTYPE_PROVIDER` | `anthropic` | Model provider: anthropic, bedrock, openai, ollama |
| `GHOSTTYPE_MODEL_ID` | `global.anthropic.claude-opus-4-6-v1` | Model identifier |
| `GHOSTTYPE_AWS_PROFILE` | `""` (falls back to `AWS_PROFILE`) | AWS profile for Bedrock (supports tokenmaster) |
| `GHOSTTYPE_AWS_REGION` | `us-west-2` (falls back to `AWS_DEFAULT_REGION`) | AWS region for Bedrock |
| `GHOSTTYPE_MAX_TOKENS` | `2048` | Max generation tokens |
| `GHOSTTYPE_TEMPERATURE` | `0.7` | Generation temperature |
| `GHOSTTYPE_LOG_LEVEL` | `DEBUG` | Python logging level |
| `ANTHROPIC_API_KEY` | — | Required for Anthropic provider |
| `OPENAI_API_KEY` | — | Required for OpenAI provider |
| `OLLAMA_HOST` | `http://localhost:11434` | Ollama server URL |

## Important Patterns

- The NSPanel must remain non-activating (`.nonactivatingPanel` style mask) — stealing focus from the target app breaks AX API text insertion.
- Text insertion uses a dual strategy: AX API direct set (`kAXSelectedTextAttribute`) preferred, simulated Cmd+V paste as fallback (saves/restores clipboard). Web-based apps (Chrome, Electron) skip AX retries and paste directly.
- `AppState` stores the AX target element captured at panel-open time — do not clear `targetElement` until after text insertion completes.
- Screen coordinate systems differ: AX API uses top-left origin (CG coordinates), NSWindow uses bottom-left (Cocoa coordinates). Conversion: `cocoaY = primaryScreen.frame.height - cgY`.
- Chrome/Electron limitation: These apps don't expose `kAXBoundsForRangeParameterizedAttribute` via accessibility. Panel is positioned at the window corner instead. No macOS API can get precise caret position from Chrome.
- The backend's `StreamingCallbackHandler` runs in a worker thread (via `asyncio.to_thread`). It uses `asyncio.run_coroutine_threadsafe` to send WebSocket messages from the sync callback. Cancellation is checked on every callback invocation via `threading.Event`.
- The frontend falls back to `StubAgent` when the backend is unavailable (`backendStatus != .running`). The health check polls `/health` every 10 seconds to detect backend availability.
- The frontend defaults `modelProvider` to `"bedrock"` in `AppState` while the backend defaults to `"anthropic"` in `config.py`. Both share the same default model ID. These defaults are only for fresh installs — existing users have values persisted in UserDefaults.
- The app requires macOS Accessibility permission (`GhostType.entitlements`). Without it, AX APIs silently return nil.
- `main.swift` uses manual `NSApplication` bootstrap (not `@main`) because SwiftUI `@main App` requires an Xcode-managed app bundle. SPM builds need this manual approach.
