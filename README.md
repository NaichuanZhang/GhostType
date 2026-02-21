# GhostType

A native macOS AI writing assistant. Press **Ctrl+K** anywhere on the system, type a prompt into the floating panel, and AI-generated text streams back in real time -- ready to insert directly into the active app. Think Spotlight for AI writing.

**[Watch the demo video](https://drive.google.com/file/d/1AD9gCUB76QqH_EGH_Zd_QefImAPDl0pv/view?usp=drive_link)** | **[Slide deck](https://docs.google.com/presentation/d/17CxFMVcIuuAas0sncyIrj_XOtwbQ_fph/edit?usp=drive_link&ouid=100873294427634961344&rtpof=true&sd=true)**

## How It Works

1. Press **Ctrl+K** in any app -- a floating panel appears at the text cursor
2. Type a prompt (or select text first for rewrite/fix/translate)
3. AI text streams in token by token
4. Click **Insert** -- text is placed directly into the app via macOS Accessibility APIs

The panel never steals focus from the target app. Text insertion works through AX APIs with a clipboard-paste fallback for web browsers.

## Features

- **System-wide hotkey** -- Ctrl+K works in any application
- **Real-time streaming** -- tokens appear as they're generated, not after
- **Contextual modes** -- Generate, Rewrite, Fix Grammar, Translate
- **Draft & Chat modes** -- draft mode outputs raw text; chat mode supports multi-turn conversation with markdown
- **Screenshot context** -- captures the active window and sends it alongside the prompt for visual awareness
- **Selected text context** -- highlight text before pressing Ctrl+K to transform it
- **Direct text insertion** -- inserts AI output into the target app via AX APIs (no manual copy-paste)
- **Multi-provider support** -- Amazon Bedrock, Anthropic, OpenAI, Ollama
- **Text-to-speech** -- stream-plays AI responses as audio (MiniMax T2A)
- **MCP tool support** -- extensible via Model Context Protocol servers
- **Menu bar app** -- lives in the menu bar, no dock icon

## Architecture

Two-process design connected via WebSocket on `localhost:8420`:

```
┌─────────────────────────────┐        WebSocket         ┌─────────────────────────────┐
│     Swift/SwiftUI Frontend  │ ◄──── ws://127.0.0.1 ──► │   Python FastAPI Backend     │
│                             │         :8420             │                             │
│  NSPanel (non-activating)   │                           │  Strands Agents SDK         │
│  Accessibility Engine       │                           │  Streaming callbacks        │
│  Hotkey Manager (CGEvent)   │                           │  MCP tool servers           │
│  Menu bar app               │                           │  Multi-provider support     │
└─────────────────────────────┘                           └─────────────────────────────┘
```

**Frontend** -- Native Swift/SwiftUI menu bar app. Uses `NSPanel` with `.nonactivatingPanel` to float above all windows without stealing focus. Reads and writes to any app's text fields via macOS Accessibility APIs.

**Backend** -- Python FastAPI server wrapping a Strands Agents SDK agent. Receives prompts over WebSocket, runs them through the configured LLM, and streams tokens back in real time.

## Tech Stack

### Frontend

| Component | Technology |
|---|---|
| Language | Swift 5.9 |
| UI | SwiftUI |
| Platform | macOS 13+ (Ventura) |
| Build system | Swift Package Manager |
| Window | NSPanel (non-activating, always-on-top) |
| Hotkey | CGEventTap (system-level intercept) |
| Text insertion | macOS Accessibility APIs (AXUIElement) |
| Markdown rendering | Custom parser + [Highlightr](https://github.com/raspu/Highlightr) for syntax highlighting |
| Networking | URLSessionWebSocketTask |
| Screen capture | ScreenCaptureKit |

### Backend

| Component | Technology |
|---|---|
| Language | Python 3.10+ |
| Framework | FastAPI + Uvicorn |
| AI agent | [Strands Agents SDK](https://github.com/strands-agents/sdk-python) |
| Transport | WebSocket (streaming), HTTP (health check) |
| Providers | Amazon Bedrock, Anthropic, OpenAI, Ollama |
| Tools | Model Context Protocol (MCP) |
| Testing | pytest + pytest-asyncio |

### Optional: AgentCore Deployment

An alternative backend target for [AWS Bedrock AgentCore](https://aws.amazon.com/bedrock/agentcore/) (managed runtime). Uses HTTP POST `/invocations` instead of WebSocket -- full response at once, no token streaming. Has its own venv, config, and Dockerfile.

## Getting Started

### Prerequisites

- macOS 13 (Ventura) or later
- Swift 5.9+ (comes with Xcode 15+ or standalone Swift toolchain)
- Python 3.10+
- API credentials for at least one provider (Bedrock, Anthropic, OpenAI, or Ollama)

### 1. Start the backend

```bash
./ghosttype/scripts/start-backend.sh
```

This creates a virtual environment, installs dependencies, and starts the server on `http://127.0.0.1:8420`.

Or manually:

```bash
cd ghosttype/backend
python3 -m venv .venv && source .venv/bin/activate
pip install -e .
python server.py
```

### 2. Build and launch the frontend

```bash
cd ghosttype
./scripts/run.sh
```

This builds with SPM, creates a `.app` bundle, and launches it. Look for the ghost icon in the menu bar.

### 3. Grant Accessibility permission

On first launch, macOS will prompt for Accessibility access. Grant it in **System Settings > Privacy & Security > Accessibility**. Without this, text cursor detection and insertion won't work.

### 4. Configure

Click the ghost menu bar icon to open Settings. Choose your provider, model, and enter credentials.

## Configuration

Environment variables serve as defaults. The Settings UI overrides them per-request.

| Variable | Default | Purpose |
|---|---|---|
| `GHOSTTYPE_PROVIDER` | `anthropic` | Provider: `bedrock`, `anthropic`, `openai`, `ollama` |
| `GHOSTTYPE_MODEL_ID` | `global.anthropic.claude-opus-4-6-v1` | Model identifier |
| `GHOSTTYPE_AWS_PROFILE` | `""` | AWS profile for Bedrock |
| `GHOSTTYPE_AWS_REGION` | `us-west-2` | AWS region for Bedrock |
| `GHOSTTYPE_MAX_TOKENS` | `2048` | Max generation tokens |
| `GHOSTTYPE_TEMPERATURE` | `0.7` | Generation temperature |
| `ANTHROPIC_API_KEY` | -- | Required for Anthropic provider |
| `OPENAI_API_KEY` | -- | Required for OpenAI provider |
| `OLLAMA_HOST` | `http://localhost:11434` | Ollama server URL |

A default config file can be placed at `~/.config/ghosttype/default.json`:

```json
{
  "modelId": "us.anthropic.claude-sonnet-4-20250514-v1:0",
  "awsProfile": "my-profile",
  "awsRegion": "us-west-2"
}
```

## Communication Protocol

WebSocket at `ws://127.0.0.1:8420/generate`. Health check at `GET /health`.

**Client -> Server:**

```json
{
  "prompt": "Rewrite this more concisely",
  "context": "selected text from the app",
  "mode": "rewrite",
  "config": { "provider": "bedrock", "model_id": "...", "aws_region": "us-west-2" },
  "screenshot": "base64-encoded JPEG (optional)"
}
```

**Server -> Client (streaming):**

```json
{"type": "token", "content": "Each"}
{"type": "token", "content": " word"}
{"type": "token", "content": " streams"}
{"type": "done", "content": "Each word streams individually."}
```

Cancellation: client sends `{"type": "cancel"}`, server responds with `{"type": "cancelled"}`.

## Project Structure

```
ghosttype/
├── GhostType/                    # Swift frontend source
│   ├── App/                      # AppDelegate, AppState, main.swift
│   ├── Core/                     # HotkeyManager, AccessibilityEngine,
│   │                             # FloatingPanel, PanelManager,
│   │                             # WebSocketClient, TTSClient, StubAgent
│   ├── UI/
│   │   ├── PromptPanel/          # PromptPanelView, MarkdownView, AvatarView
│   │   └── Settings/             # SettingsView
│   └── Resources/                # Info.plist, entitlements, icons
├── GhostTypeMain/                # Executable entry point (re-exports main.swift)
├── backend/                      # Python backend
│   ├── server.py                 # FastAPI WebSocket server
│   ├── agent.py                  # Strands Agent factory
│   ├── config.py                 # Env var configuration
│   ├── mcp_manager.py            # MCP server lifecycle
│   ├── prompts/                  # System prompts (draft + chat modes)
│   └── tests/                    # pytest suite
├── agentcore/                    # AWS Bedrock AgentCore deployment
│   ├── server.py                 # HTTP /invocations endpoint
│   ├── Dockerfile
│   └── ...
├── scripts/
│   ├── run.sh                    # Build + launch frontend
│   └── start-backend.sh          # Setup + start backend
├── Tests/GhostTypeTests/         # Swift tests
├── Package.swift                 # SPM manifest
└── project.yml                   # XcodeGen config (optional)
```

## Running Tests

**Backend:**

```bash
cd ghosttype/backend
source .venv/bin/activate
python -m pytest tests/ -v
```

**Frontend:**

```bash
cd ghosttype
swift test
```

## Known Limitations

- **Chrome/Electron caret position** -- these apps don't expose caret bounds via Accessibility APIs. The panel falls back to window-corner positioning instead of exact cursor placement.
- **Accessibility permission required** -- without it, AX APIs silently return nil. Must be granted manually in System Settings.
- **Single hotkey** -- Ctrl+K is hardcoded; no UI for remapping.
- **No persistent memory** -- a fresh agent is created per request. Multi-turn conversation is supported within a session but not persisted across restarts.

## License

Private repository. All rights reserved.
