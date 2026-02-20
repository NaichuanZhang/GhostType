# GhostType Backend Plan

## Current State

The backend exists with a basic working structure:
- `server.py` — FastAPI with `/generate` WebSocket and `/health` endpoints
- `agent.py` — Strands Agent creation with three inline tools (rewrite, fix_grammar, translate)
- `config.py` — Dataclass config loaded from env vars
- `tools/text_tools.py` — Three additional tools (count_words, extract_key_points, change_tone) **not wired into the agent**
- `prompts/system.txt` — System prompt (duplicated in agent.py code)

### What Works
- Multi-provider model factory (Anthropic, Bedrock, OpenAI, Ollama)
- WebSocket request/response lifecycle
- Mode-aware prompt building (generate/rewrite/fix/translate)
- Cancel support via `{"type": "cancel"}` messages

### What Doesn't Work / Needs Improvement
1. **No true streaming** — Full response is collected then sent as one "token" message + "done". Users see nothing until generation completes.
2. **System prompt duplication** — Defined in both `agent.py` and `prompts/system.txt`
3. **Unused tools** — `tools/text_tools.py` tools are never loaded
4. **No error recovery** — Agent exceptions crash the WebSocket connection
5. **No cancellation enforcement** — Cancel flag is checked but agent execution isn't interrupted
6. **No logging** — No structured logging for debugging or monitoring
7. **Agent created per-request** — New agent on every WebSocket message (no session reuse)

---

## Plan

### Phase 1: True Token-by-Token Streaming

**Goal**: Users see text appear word-by-word in the floating panel as the LLM generates it.

**Approach**: Use Strands' `callback_handler` to intercept streaming events and forward each token chunk over WebSocket in real time.

**Files to change**:
- `server.py` — Replace the current `result = agent(message)` / send-full-response pattern with a custom callback handler that sends each token as it arrives

**Implementation sketch**:
```python
from strands.agent.callback_handler import CallbackHandler

class WebSocketStreamHandler(CallbackHandler):
    def __init__(self, websocket):
        self.websocket = websocket
        self.loop = asyncio.get_event_loop()

    def on_llm_new_token(self, token: str, **kwargs):
        # Send each token chunk over WebSocket immediately
        asyncio.run_coroutine_threadsafe(
            self.websocket.send_text(json.dumps({
                "type": "token",
                "content": token
            })),
            self.loop
        )
```

**Key consideration**: Strands runs the agent synchronously. The WebSocket endpoint is async. The callback handler bridges these worlds by scheduling coroutines from the sync callback. Run the agent in a thread pool (`asyncio.to_thread` or `loop.run_in_executor`) so it doesn't block the event loop.

**Acceptance criteria**:
- Tokens appear in the Swift frontend within ~50ms of the LLM producing them
- "done" message still sent after full response completes
- Error messages still sent on failure

---

### Phase 2: Robust Error Handling & Cancellation

**Goal**: The WebSocket connection survives errors. Users can cancel mid-generation and the LLM call actually stops.

**Files to change**:
- `server.py` — Wrap agent execution in try/except, implement cancellation via threading Event or similar

**Error handling**:
```python
try:
    result = await asyncio.to_thread(agent, message)
except Exception as e:
    await websocket.send_text(json.dumps({
        "type": "error",
        "content": str(e)
    }))
    # Don't close the WebSocket — let the user retry
```

**Cancellation**:
- Maintain a `cancel_event = asyncio.Event()` per session
- The callback handler checks `cancel_event.is_set()` before sending each token; if set, raise an exception to abort the agent
- A concurrent task listens for `{"type": "cancel"}` messages and sets the event
- Use `asyncio.gather` or `asyncio.create_task` to run the agent and the cancel-listener concurrently

**Acceptance criteria**:
- Clicking Cancel in the UI stops token generation within ~200ms
- After an error, the user can send another prompt without reconnecting
- Provider API errors (rate limit, auth failure) produce user-friendly messages

---

### Phase 3: Consolidate System Prompt & Tools

**Goal**: Single source of truth for prompts. All tools wired in and organized.

**Files to change**:
- `agent.py` — Load system prompt from `prompts/system.txt` instead of hardcoding
- `agent.py` — Import and register tools from `tools/text_tools.py`
- `tools/text_tools.py` — Review and consolidate with the inline tools in `agent.py`

**Tool consolidation plan**:

Move all tools to `tools/` and import them in `agent.py`:

| Tool | Source | Keep? | Notes |
|------|--------|-------|-------|
| `rewrite_text` | agent.py (inline) | Yes, move to tools/ | Core feature |
| `fix_grammar` | agent.py (inline) | Yes, move to tools/ | Core feature |
| `translate_text` | agent.py (inline) | Yes, move to tools/ | Core feature |
| `count_words` | tools/text_tools.py | Remove | Not useful for a writing assistant — users don't ask for word counts mid-typing |
| `extract_key_points` | tools/text_tools.py | Remove | Overlaps with generate mode |
| `change_tone` | tools/text_tools.py | Merge with rewrite | The `rewrite_text` tool already takes a `style` param |

**Resulting tool set**:
```
tools/
├── __init__.py          # Exports all tools
├── rewrite.py           # rewrite_text(text, style)
├── grammar.py           # fix_grammar(text)
└── translate.py         # translate_text(text, target_language)
```

**System prompt**: Delete the hardcoded string in `agent.py`. Load from `prompts/system.txt` at agent creation time. This is the single source of truth.

**Acceptance criteria**:
- System prompt lives only in `prompts/system.txt`
- All tools live in `tools/` directory
- `agent.py` imports tools from `tools/` package

---

### Phase 4: Structured Logging

**Goal**: Debug backend issues without guessing. Log requests, responses, errors, and timing.

**Files to change**:
- `server.py` — Add request/response logging
- `agent.py` — Add agent creation logging
- New file: `logging_config.py` — Centralized logging setup

**What to log**:
- Incoming WebSocket messages (prompt, mode, context length — NOT full context for privacy)
- Model provider and model ID used
- Time to first token (TTFT)
- Total generation time
- Token count (if available from provider response)
- Errors with full tracebacks
- WebSocket connect/disconnect events

**Format**: JSON structured logging to stderr. Keep it simple — no log aggregation service, just parseable output.

```python
import logging
import json

logging.basicConfig(
    level=logging.INFO,
    format='%(message)s',  # JSON lines
    stream=sys.stderr
)

def log_event(event_type, **data):
    logging.info(json.dumps({"event": event_type, "ts": time.time(), **data}))
```

**Acceptance criteria**:
- Every request produces a log line with mode, timing, and status
- Errors produce log lines with exception details
- Logs are JSON-parseable

---

### Phase 5: Mode-Specific Prompt Templates

**Goal**: Better prompt engineering per mode, externalized as text files so they're easy to iterate on without code changes.

**Files to change/create**:
- `prompts/modes/generate.txt`
- `prompts/modes/rewrite.txt`
- `prompts/modes/fix.txt`
- `prompts/modes/translate.txt`
- `server.py` — Replace `build_message()` string formatting with template loading

**Current `build_message()` approach** (inline string concatenation):
```python
if mode == "rewrite":
    return f"Rewrite the following text:\n\n{context}\n\nInstructions: {prompt}"
```

**New approach** (template files with placeholders):
```
# prompts/modes/rewrite.txt
Rewrite the following text according to the instructions.

TEXT:
{context}

INSTRUCTIONS:
{prompt}

Output ONLY the rewritten text. No explanations.
```

```python
def build_message(prompt, context, mode):
    template_path = PROMPTS_DIR / "modes" / f"{mode}.txt"
    if template_path.exists():
        template = template_path.read_text()
        return template.format(prompt=prompt, context=context)
    return prompt  # fallback for unknown modes
```

**Acceptance criteria**:
- Each mode has a dedicated prompt template file
- Templates are loaded at request time (no restart needed to pick up changes during development)
- Unknown modes fall back to raw prompt passthrough

---

### Phase 6: Session-Aware Agent (Optional / Future)

**Goal**: Allow multi-turn conversations within a single panel session. The agent remembers the previous exchange so users can say "make it shorter" or "now translate that to Spanish."

**Current behavior**: New agent per message. No memory.

**Approach**: Keep the agent alive for the duration of the WebSocket connection. Strands Agent maintains conversation history automatically.

```python
@app.websocket("/generate")
async def generate(websocket):
    await websocket.accept()
    agent = create_agent()  # One agent per connection

    while True:
        data = await websocket.receive_text()
        # ... same agent handles all messages in this session
```

**Trade-off**: This uses more memory (conversation history accumulates) and the context window fills up over a long session. For a writing assistant where interactions are short (1-3 exchanges), this is fine. Add a `max_history` limit or let the frontend signal "new session" by reconnecting.

**Acceptance criteria**:
- Agent persists across messages within a single WebSocket connection
- Conversation history enables follow-up instructions ("make it shorter")
- New WebSocket connection = fresh agent

---

## Execution Order

```
Phase 1 (Streaming)     ← Most impactful for UX, do first
  ↓
Phase 2 (Error/Cancel)  ← Required for production-quality experience
  ↓
Phase 3 (Prompts/Tools) ← Cleanup/consolidation, enables faster iteration
  ↓
Phase 4 (Logging)       ← Needed for debugging all the above
  ↓
Phase 5 (Templates)     ← Prompt engineering improvements
  ↓
Phase 6 (Sessions)      ← Nice-to-have, enables follow-up instructions
```

Phases 1-2 are critical. Phase 3-4 are important cleanup. Phases 5-6 are enhancements.

---

## File Structure After All Phases

```
backend/
├── pyproject.toml
├── server.py              # FastAPI + WebSocket, streaming handler
├── agent.py               # create_model(), create_agent(), load system prompt
├── config.py              # Dataclass config from env vars
├── logging_config.py      # JSON structured logging setup
├── tools/
│   ├── __init__.py        # Exports: rewrite_text, fix_grammar, translate_text
│   ├── rewrite.py         # @tool rewrite_text(text, style)
│   ├── grammar.py         # @tool fix_grammar(text)
│   └── translate.py       # @tool translate_text(text, target_language)
└── prompts/
    ├── system.txt         # Single source of truth for system prompt
    └── modes/
        ├── generate.txt   # Template for generate mode
        ├── rewrite.txt    # Template for rewrite mode
        ├── fix.txt        # Template for fix mode
        └── translate.txt  # Template for translate mode
```
