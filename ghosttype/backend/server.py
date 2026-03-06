"""GhostType Backend Server — FastAPI + WebSocket with Strands Agent streaming."""

import asyncio
import base64
import contextlib
import json
import logging
import sys
import time
import threading
from contextlib import asynccontextmanager

from fastapi import FastAPI, WebSocket, WebSocketDisconnect
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

from agent import ModelConfig, create_agent
from agent_registry import AgentRegistry
from browser_context import BrowserContext, BrowserContextStore
from config import config
from mcp_manager import MCPManager

# ---------------------------------------------------------------------------
# Logging setup
# ---------------------------------------------------------------------------
logging.basicConfig(
    level=getattr(logging, config.log_level.upper(), logging.DEBUG),
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    stream=sys.stderr,
)
logger = logging.getLogger("ghosttype.server")

# ---------------------------------------------------------------------------
# MCP server lifecycle & Agent registry
# ---------------------------------------------------------------------------
mcp_manager = MCPManager()
agent_registry = AgentRegistry()
browser_context_store = BrowserContextStore()


@asynccontextmanager
async def lifespan(app):
    """Start MCP servers on startup, stop on shutdown."""
    mcp_manager.start()
    yield
    mcp_manager.stop()


# ---------------------------------------------------------------------------
# App
# ---------------------------------------------------------------------------
app = FastAPI(title="GhostType Backend", version="0.1.0", lifespan=lifespan)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


# ---------------------------------------------------------------------------
# Health endpoint
# ---------------------------------------------------------------------------
@app.get("/health")
async def health():
    """Health check endpoint."""
    return {
        "status": "ok",
        "provider": config.model_provider,
        "model": config.model_id,
    }


# ---------------------------------------------------------------------------
# Agents endpoint
# ---------------------------------------------------------------------------
@app.get("/agents")
async def agents():
    """Return available agent definitions."""
    snapshot = agent_registry.snapshot()
    return {
        "agents": snapshot.to_dicts(),
        "default_agent_id": snapshot.default_agent_id,
    }


# ---------------------------------------------------------------------------
# Browser context endpoints
# ---------------------------------------------------------------------------
class BrowserContextRequest(BaseModel):
    url: str
    title: str = ""
    content: str = ""
    selected_text: str = ""


@app.post("/browser-context")
async def post_browser_context(req: BrowserContextRequest):
    """Receive page content from the Chrome extension."""
    if not req.url:
        from fastapi.responses import JSONResponse
        return JSONResponse(status_code=400, content={"error": "url is required"})

    ctx = BrowserContext(
        url=req.url,
        title=req.title,
        content=req.content,
        selected_text=req.selected_text,
        timestamp=time.time(),
    )
    browser_context_store.set(ctx)
    logger.info("Browser context updated: url=%s, content_len=%d", req.url, len(req.content))
    logger.debug("Browser context detail: title=%r, selected_text_len=%d, content_preview=%r",
                 req.title, len(req.selected_text), req.content[:200])
    return {"status": "ok"}


@app.get("/browser-context")
async def get_browser_context():
    """Return the current browser context (if any)."""
    ctx = browser_context_store.get()
    logger.debug("Browser context GET: available=%s, url=%s", ctx is not None, ctx.url if ctx else None)
    return browser_context_store.to_dict()


# ---------------------------------------------------------------------------
# Streaming callback handler
# ---------------------------------------------------------------------------
class CancellationError(Exception):
    """Raised inside the agent thread when the client cancels generation."""


class StreamingCallbackHandler:
    """Bridges Strands' synchronous callback to an async WebSocket.

    Strands Agent runs synchronously in a worker thread. This handler is
    called on that thread for every streaming event. It schedules async
    WebSocket sends on the event loop running in the main thread.

    Cancellation: the caller sets ``cancel_event``. On the next callback
    invocation the handler raises ``CancellationError`` which propagates
    up through the agent and terminates generation.
    """

    def __init__(
        self,
        websocket: WebSocket,
        loop: asyncio.AbstractEventLoop,
        cancel_event: threading.Event,
    ):
        self.websocket = websocket
        self.loop = loop
        self.cancel_event = cancel_event
        self.token_count = 0
        self.first_token_time: float | None = None
        self.start_time: float = time.monotonic()
        # Tool call tracking
        self._active_tool_id: str | None = None
        self._active_tool_name: str | None = None
        self._active_tool_input: dict | None = None

    def _close_active_tool(self):
        """Send tool_done for the currently active tool, if any."""
        if self._active_tool_id is not None:
            msg = {
                "type": "tool_done",
                "tool_name": self._active_tool_name or "unknown",
                "tool_id": self._active_tool_id,
            }
            if self._active_tool_input is not None:
                msg["tool_input"] = json.dumps(self._active_tool_input)
            self._send_ws_message(msg)
            self._active_tool_id = None
            self._active_tool_name = None
            self._active_tool_input = None

    def __call__(self, **kwargs):
        # Check for cancellation before doing any work
        if self.cancel_event.is_set():
            logger.debug("Cancel event detected in callback handler")
            raise CancellationError("Generation cancelled by client")

        # --- Tool call start ---
        event = kwargs.get("event") or {}
        tool_use = (
            event.get("contentBlockStart", {})
            .get("start", {})
            .get("toolUse")
        )
        if tool_use:
            # Close previous tool if one was active
            self._close_active_tool()
            tool_name = tool_use.get("name", "unknown")
            tool_id = tool_use.get("toolUseId", "")
            self._active_tool_id = tool_id
            self._active_tool_name = tool_name
            self._send_ws_message({
                "type": "tool_start",
                "tool_name": tool_name,
                "tool_id": tool_id,
            })
            return  # tool start events don't carry text data

        # --- Tool input streaming ---
        current_tool = kwargs.get("current_tool_use")
        if current_tool and self._active_tool_id:
            tool_input = current_tool.get("input")
            if tool_input:
                self._active_tool_input = tool_input

        data = kwargs.get("data", "")
        complete = kwargs.get("complete", False)

        # Close active tool when text data arrives or stream completes
        if data and self._active_tool_id:
            self._close_active_tool()

        if data:
            if self.first_token_time is None:
                self.first_token_time = time.monotonic()
                ttft = self.first_token_time - self.start_time
                logger.debug("Time to first token: %.3fs", ttft)

            self.token_count += 1
            self._send_ws_message({"type": "token", "content": data})

        if complete and self._active_tool_id:
            self._close_active_tool()

        if complete and data:
            logger.debug(
                "Stream complete: %d callback invocations, %.3fs total",
                self.token_count,
                time.monotonic() - self.start_time,
            )

    def _send_ws_message(self, message: dict):
        """Schedule a WebSocket send on the event loop (thread-safe)."""
        future = asyncio.run_coroutine_threadsafe(
            self.websocket.send_text(json.dumps(message)),
            self.loop,
        )
        # Wait for the send to complete so we don't overwhelm the socket
        try:
            future.result(timeout=5.0)
        except Exception as e:
            logger.warning("Failed to send WS message: %s", e)


# Maximum time (seconds) for a single generation before timeout.
# Multi-turn conversations with large history can be slow; this prevents
# the endpoint from hanging indefinitely if the LLM API stalls.
GENERATION_TIMEOUT = 120


# ---------------------------------------------------------------------------
# Message building
# ---------------------------------------------------------------------------
def classify_mode_type(mode: str, context: str, prompt: str) -> str:
    """Classify the request as 'draft' or 'chat' mode type.

    Returns 'draft' if the request involves writing/editing (context present,
    or mode is rewrite/fix/translate). Returns 'chat' otherwise.
    """
    if mode in ("rewrite", "fix", "translate"):
        return "draft"
    if context:
        return "draft"
    return "chat"


def build_message(prompt: str, context: str, mode: str, browser_context: str = "") -> str:
    """Build the user text message based on mode and context."""
    if mode == "rewrite" and context:
        base = f"Rewrite the following text:\n\n{context}\n\nInstructions: {prompt}"
    elif mode == "fix" and context:
        base = f"Fix grammar and spelling in the following text:\n\n{context}"
    elif mode == "translate" and context:
        base = f"Translate the following text. {prompt}\n\n{context}"
    elif context:
        base = (
            f'Context (selected text from user\'s application):\n"""\n{context}\n"""\n\n'
            f"Task: {prompt}"
        )
    else:
        base = prompt

    if browser_context:
        base += f'\n\nBrowser page content:\n"""\n{browser_context}\n"""'

    return base


def build_multimodal_message(text: str, screenshot_b64: str | None) -> str | list:
    """Build the agent message, optionally including a screenshot image.

    If a screenshot is provided, returns a list of content blocks (Bedrock
    Converse API format) with the image and text. Otherwise returns the
    plain text string.
    """
    if not screenshot_b64:
        return text

    try:
        image_bytes = base64.b64decode(screenshot_b64)
    except Exception:
        logger.warning("Failed to decode screenshot base64, sending text only")
        return text

    return [
        {
            "image": {
                "format": "jpeg",
                "source": {"bytes": image_bytes},
            }
        },
        {"text": text},
    ]


# ---------------------------------------------------------------------------
# WebSocket endpoint
# ---------------------------------------------------------------------------
@app.websocket("/generate")
async def generate(websocket: WebSocket):
    """WebSocket endpoint for streaming text generation.

    Client → Server messages:
        {"prompt": "...", "context": "...", "mode": "generate|rewrite|fix|translate",
         "config": {"provider": "bedrock", "model_id": "...", "aws_profile": "...", "aws_region": "..."}}
        {"type": "cancel"}

    Server → Client messages:
        {"type": "token", "content": "partial text"}
        {"type": "done", "content": "full response text"}
        {"type": "error", "content": "error message"}
        {"type": "cancelled"}
    """
    await websocket.accept()
    logger.info("Client connected")

    # One agent per connection (enables multi-turn follow-ups within a session).
    # Agent is recreated only when config, mode type, or agent id changes.
    agent = None
    current_config: ModelConfig | None = None
    current_mode_type: str | None = None
    current_agent_id: str | None = None

    loop = asyncio.get_running_loop()
    cancel_event = threading.Event()

    try:
        while True:
            raw = await websocket.receive_text()
            logger.debug("Received message: %s", raw[:200])

            try:
                request = json.loads(raw)
            except json.JSONDecodeError as e:
                logger.warning("Invalid JSON from client: %s", e)
                await websocket.send_text(json.dumps({
                    "type": "error",
                    "content": f"Invalid JSON: {e}",
                }))
                continue

            # ----- Handle cancel -----
            if request.get("type") == "cancel":
                logger.info("Cancel requested by client")
                cancel_event.set()
                continue

            # ----- Handle new_conversation -----
            if request.get("type") == "new_conversation":
                logger.info("New conversation requested — resetting agent")
                agent = None
                current_config = None
                current_mode_type = None
                current_agent_id = None
                await websocket.send_text(json.dumps({"type": "conversation_reset"}))
                continue

            # ----- Validate prompt -----
            prompt = request.get("prompt", "")
            context = request.get("context", "")
            mode = request.get("mode", "generate")
            screenshot_b64 = request.get("screenshot")

            if not prompt and mode == "generate":
                await websocket.send_text(json.dumps({
                    "type": "error",
                    "content": "Empty prompt",
                }))
                continue

            # Reset cancel event for new generation
            cancel_event.clear()

            # Extract per-request model config (provider, credentials, etc.)
            request_config = request.get("config")
            model_config = ModelConfig.from_request(request_config)

            # Determine mode type — use client-provided value or auto-classify
            mode_type = request.get("mode_type") or classify_mode_type(mode, context, prompt)

            # Optionally attach browser page content
            browser_ctx_text = ""
            if request.get("include_browser_context"):
                bc = browser_context_store.get()
                if bc is not None:
                    # Truncate to 10,000 chars to stay within reasonable context limits
                    browser_ctx_text = bc.content[:10_000]
                    if bc.selected_text:
                        browser_ctx_text += f"\n\nUser's selection on the page:\n{bc.selected_text[:2_000]}"

            if browser_ctx_text:
                logger.debug("Browser context injected: len=%d, preview=%r", len(browser_ctx_text), browser_ctx_text[:200])
            elif request.get("include_browser_context"):
                logger.debug("Browser context requested but none available")

            text_message = build_message(prompt, context, mode, browser_context=browser_ctx_text)
            user_message = build_multimodal_message(text_message, screenshot_b64)
            has_screenshot = screenshot_b64 is not None
            logger.info(
                "Generating: mode=%s, mode_type=%s, provider=%s, model=%s, prompt_len=%d, context_len=%d, screenshot=%s",
                mode, mode_type, model_config.effective_provider(), model_config.effective_model_id(),
                len(prompt), len(context), "yes" if has_screenshot else "no",
            )

            # Resolve agent definition
            registry_snapshot = agent_registry.snapshot()
            requested_agent_id = request.get("agent") or registry_snapshot.default_agent_id
            agent_def = registry_snapshot.get(requested_agent_id)
            if agent_def is None:
                await websocket.send_text(json.dumps({
                    "type": "error",
                    "content": f"Unknown agent: {requested_agent_id}",
                }))
                continue

            # Create callback handler for this request (per-request state)
            handler = StreamingCallbackHandler(
                websocket=websocket,
                loop=loop,
                cancel_event=cancel_event,
            )

            # Recreate agent if config, mode type, or agent changed; otherwise reuse
            agent_changed = requested_agent_id != current_agent_id
            if agent is None or model_config != current_config or mode_type != current_mode_type or agent_changed:
                logger.info(
                    "Creating new agent: config_changed=%s, mode_changed=%s, agent_changed=%s (id=%s)",
                    model_config != current_config, mode_type != current_mode_type,
                    agent_changed, requested_agent_id,
                )
                # Resolve MCP tools — filter by agent's mcp_servers if specified
                if agent_def.mcp_servers:
                    mcp_tools = mcp_manager.get_mcp_tools_by_names(agent_def.mcp_servers)
                else:
                    mcp_tools = mcp_manager.get_mcp_tools()
                agent = create_agent(
                    callback_handler=handler,
                    model_config=model_config,
                    mode_type=mode_type,
                    mcp_tools=mcp_tools,
                    agent_def=agent_def,
                )
                current_config = model_config
                current_mode_type = mode_type
                current_agent_id = requested_agent_id
            else:
                # Reuse agent (preserves conversation history), just update handler
                agent.callback_handler = handler

            gen_start = time.monotonic()

            # Start agent in a background thread so the event loop
            # remains free to read WebSocket messages (cancel, etc.).
            agent_task = asyncio.create_task(
                asyncio.to_thread(_run_agent, agent, user_message, cancel_event)
            )

            logger.debug(
                "Generation started: agent_reused=%s, cancel_clear=%s",
                model_config == current_config and mode_type == current_mode_type,
                not cancel_event.is_set(),
            )

            # ----------------------------------------------------------
            # Concurrent cancel listener — reads from WebSocket while
            # the agent is running so the client can cancel mid-stream.
            # Without this, cancel messages sit in the buffer until the
            # generation finishes, making multi-turn conversations with
            # long history appear to hang.
            # ----------------------------------------------------------
            timed_out = False
            try:
                while not agent_task.done():
                    remaining = GENERATION_TIMEOUT - (time.monotonic() - gen_start)
                    if remaining <= 0:
                        logger.warning(
                            "Generation timed out after %ds", GENERATION_TIMEOUT,
                        )
                        cancel_event.set()
                        timed_out = True
                        break

                    recv_task = asyncio.create_task(websocket.receive_text())
                    done_set, pending_set = await asyncio.wait(
                        {agent_task, recv_task},
                        return_when=asyncio.FIRST_COMPLETED,
                        timeout=min(remaining, 1.0),
                    )

                    # Clean up the pending recv if the agent finished first
                    if recv_task in pending_set:
                        recv_task.cancel()
                        with contextlib.suppress(asyncio.CancelledError):
                            await recv_task

                    # Process any message received during generation
                    if recv_task in done_set:
                        try:
                            raw_inner = recv_task.result()
                        except WebSocketDisconnect:
                            # Client gone — cancel agent and propagate
                            cancel_event.set()
                            agent_task.cancel()
                            with contextlib.suppress(Exception):
                                await agent_task
                            raise
                        except Exception as exc:
                            logger.debug("Read error during generation: %s", exc)
                            continue

                        try:
                            inner_msg = json.loads(raw_inner)
                        except json.JSONDecodeError:
                            logger.debug("Invalid JSON during generation")
                            continue

                        msg_type = inner_msg.get("type")
                        logger.debug("Message during generation: type=%s", msg_type)
                        if msg_type == "cancel":
                            logger.info("Cancel received during generation")
                            cancel_event.set()
                        elif msg_type == "new_conversation":
                            logger.info(
                                "New conversation during generation — cancelling"
                            )
                            cancel_event.set()
                            agent = None
                            current_config = None
                            current_mode_type = None
                            current_agent_id = None

                # --- Collect agent result ---
                if timed_out:
                    # Give agent a moment to respond to cancel_event
                    done_set, _ = await asyncio.wait(
                        {agent_task}, timeout=5.0,
                    )
                    if not done_set:
                        agent_task.cancel()
                        raise asyncio.TimeoutError("Generation timed out")
                    result = agent_task.result()
                else:
                    result = await agent_task

                full_response = str(result)
                elapsed = time.monotonic() - gen_start

                logger.info(
                    "Generation complete: %.3fs, response_len=%d",
                    elapsed, len(full_response),
                )

                await websocket.send_text(json.dumps({
                    "type": "done",
                    "content": full_response,
                }))

            except CancellationError:
                elapsed = time.monotonic() - gen_start
                logger.info("Generation cancelled after %.3fs", elapsed)
                await websocket.send_text(json.dumps({"type": "cancelled"}))

            except asyncio.TimeoutError:
                elapsed = time.monotonic() - gen_start
                logger.warning("Generation timed out after %.3fs", elapsed)
                # Reset agent — it may be in a broken state after timeout
                agent = None
                current_config = None
                current_mode_type = None
                current_agent_id = None
                await websocket.send_text(json.dumps({
                    "type": "error",
                    "content": "Generation timed out. Try a shorter conversation or start a new one.",
                }))

            except WebSocketDisconnect:
                raise

            except Exception as e:
                elapsed = time.monotonic() - gen_start
                logger.error(
                    "Generation error after %.3fs: %s: %s",
                    elapsed, type(e).__name__, e,
                    exc_info=True,
                )
                # Send error but keep the WebSocket alive for retry
                await websocket.send_text(json.dumps({
                    "type": "error",
                    "content": _friendly_error(e),
                }))

    except WebSocketDisconnect:
        logger.info("Client disconnected")
    except Exception as e:
        logger.error("WebSocket error: %s: %s", type(e).__name__, e, exc_info=True)


def _run_agent(agent, message: str, cancel_event: threading.Event):
    """Run the Strands agent in a worker thread.

    The callback handler checks ``cancel_event`` on every token, so
    cancellation raises ``CancellationError`` from within the agent loop.
    """
    # Double-check cancel wasn't requested before we even start
    if cancel_event.is_set():
        raise CancellationError("Generation cancelled before start")

    return agent(message)


def _friendly_error(e: Exception) -> str:
    """Convert exceptions into user-friendly error messages."""
    msg = str(e)
    etype = type(e).__name__

    # Common provider errors
    if "rate" in msg.lower() and "limit" in msg.lower():
        return "Rate limit exceeded. Please wait a moment and try again."
    if "authentication" in msg.lower() or "credentials" in msg.lower():
        return "Authentication error. Check your AWS credentials."
    if "timeout" in msg.lower():
        return "Request timed out. The model may be overloaded — try again."
    if "ExpiredTokenException" in msg or "ExpiredToken" in msg:
        return "AWS credentials expired. Run tokenmaster to refresh."

    return f"{etype}: {msg}"


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
if __name__ == "__main__":
    import uvicorn

    logger.info(
        "Starting GhostType backend: provider=%s, model=%s, host=%s:%d",
        config.model_provider, config.model_id, config.host, config.port,
    )

    uvicorn.run(
        "server:app",
        host=config.host,
        port=config.port,
        reload=True,
        log_level=config.log_level.lower(),
    )
