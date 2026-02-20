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

from agent import ModelConfig, create_agent
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
# MCP server lifecycle
# ---------------------------------------------------------------------------
mcp_manager = MCPManager()


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

    def __call__(self, **kwargs):
        # Check for cancellation before doing any work
        if self.cancel_event.is_set():
            logger.debug("Cancel event detected in callback handler")
            raise CancellationError("Generation cancelled by client")

        data = kwargs.get("data", "")
        complete = kwargs.get("complete", False)

        if data:
            if self.first_token_time is None:
                self.first_token_time = time.monotonic()
                ttft = self.first_token_time - self.start_time
                logger.debug("Time to first token: %.3fs", ttft)

            self.token_count += 1
            self._send_ws_message({"type": "token", "content": data})

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


def build_message(prompt: str, context: str, mode: str) -> str:
    """Build the user text message based on mode and context."""
    if mode == "rewrite" and context:
        return f"Rewrite the following text:\n\n{context}\n\nInstructions: {prompt}"
    elif mode == "fix" and context:
        return f"Fix grammar and spelling in the following text:\n\n{context}"
    elif mode == "translate" and context:
        return f"Translate the following text. {prompt}\n\n{context}"
    elif context:
        return (
            f'Context (selected text from user\'s application):\n"""\n{context}\n"""\n\n'
            f"Task: {prompt}"
        )
    else:
        return prompt


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
    # Agent is recreated only when config or mode type changes.
    agent = None
    current_config: ModelConfig | None = None
    current_mode_type: str | None = None

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

            text_message = build_message(prompt, context, mode)
            user_message = build_multimodal_message(text_message, screenshot_b64)
            has_screenshot = screenshot_b64 is not None
            logger.info(
                "Generating: mode=%s, mode_type=%s, provider=%s, model=%s, prompt_len=%d, context_len=%d, screenshot=%s",
                mode, mode_type, model_config.effective_provider(), model_config.effective_model_id(),
                len(prompt), len(context), "yes" if has_screenshot else "no",
            )

            # Create callback handler for this request (per-request state)
            handler = StreamingCallbackHandler(
                websocket=websocket,
                loop=loop,
                cancel_event=cancel_event,
            )

            # Recreate agent if config or mode type changed; otherwise reuse
            if agent is None or model_config != current_config or mode_type != current_mode_type:
                logger.info(
                    "Creating new agent: config_changed=%s, mode_changed=%s",
                    model_config != current_config, mode_type != current_mode_type,
                )
                agent = create_agent(
                    callback_handler=handler,
                    model_config=model_config,
                    mode_type=mode_type,
                    mcp_tools=mcp_manager.get_mcp_tools(),
                )
                current_config = model_config
                current_mode_type = mode_type
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
