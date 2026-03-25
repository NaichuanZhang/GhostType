#!/usr/bin/env python3
"""GhostType stdio server — reads JSON lines from stdin, writes events to stdout.

Replaces the FastAPI/WebSocket server.py with a simpler stdio-based architecture.
Swift launches this as a managed subprocess, communicating via stdin/stdout pipes.

stdin:  Line-delimited JSON requests (one object per line)
stdout: Line-delimited JSON events (token, tool_start, tool_done, done, error, etc.)
stderr: Python logging (forwarded to Console.app by Swift)
"""

from __future__ import annotations

import base64
import json
import logging
import sys
import threading
import time
from typing import Any

from agent import ModelConfig, create_agent
from agent_registry import AgentRegistry
from config import config
from mcp_manager import MCPManager

# ---------------------------------------------------------------------------
# Logging → stderr only (stdout is reserved for JSON events)
# ---------------------------------------------------------------------------
logging.basicConfig(
    level=getattr(logging, config.log_level.upper(), logging.DEBUG),
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    stream=sys.stderr,
)
logger = logging.getLogger("ghosttype.stdio")

# ---------------------------------------------------------------------------
# MCP + Agent Registry
# ---------------------------------------------------------------------------
mcp_manager = MCPManager()
agent_registry = AgentRegistry()

# ---------------------------------------------------------------------------
# Cancellation
# ---------------------------------------------------------------------------

class CancellationError(Exception):
    """Raised inside the agent thread when the client cancels generation."""


# ---------------------------------------------------------------------------
# Streaming callback handler (stdio version)
# ---------------------------------------------------------------------------

class StdioCallbackHandler:
    """Strands callback handler that writes JSON lines to stdout.

    Much simpler than the WebSocket version — no asyncio bridging needed.
    Strands callbacks are synchronous, and so is stdout.write().
    """

    def __init__(self, cancel_event: threading.Event):
        self.cancel_event = cancel_event
        self.token_count = 0
        self.first_token_time: float | None = None
        self.start_time: float = time.monotonic()
        self._active_tool_id: str | None = None
        self._active_tool_name: str | None = None
        self._active_tool_input: dict | None = None

    def _close_active_tool(self):
        """Emit tool_done for the currently active tool, if any."""
        if self._active_tool_id is not None:
            msg: dict[str, Any] = {
                "type": "tool_done",
                "tool_name": self._active_tool_name or "unknown",
                "tool_id": self._active_tool_id,
            }
            if self._active_tool_input is not None:
                msg["tool_input"] = json.dumps(self._active_tool_input)
            emit(msg)
            self._active_tool_id = None
            self._active_tool_name = None
            self._active_tool_input = None

    def __call__(self, **kwargs):
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
            self._close_active_tool()
            tool_name = tool_use.get("name", "unknown")
            tool_id = tool_use.get("toolUseId", "")
            self._active_tool_id = tool_id
            self._active_tool_name = tool_name
            emit({
                "type": "tool_start",
                "tool_name": tool_name,
                "tool_id": tool_id,
            })
            return

        # --- Tool input streaming ---
        current_tool = kwargs.get("current_tool_use")
        if current_tool and self._active_tool_id:
            tool_input = current_tool.get("input")
            if tool_input:
                self._active_tool_input = tool_input

        data = kwargs.get("data", "")
        complete = kwargs.get("complete", False)

        if data and self._active_tool_id:
            self._close_active_tool()

        if data:
            if self.first_token_time is None:
                self.first_token_time = time.monotonic()
                ttft = self.first_token_time - self.start_time
                logger.debug("Time to first token: %.3fs", ttft)

            self.token_count += 1
            emit({"type": "token", "content": data})

        if complete and self._active_tool_id:
            self._close_active_tool()

        if complete and data:
            logger.debug(
                "Stream complete: %d callback invocations, %.3fs total",
                self.token_count,
                time.monotonic() - self.start_time,
            )


# ---------------------------------------------------------------------------
# Message building (same as server.py)
# ---------------------------------------------------------------------------

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
    """Build the agent message, optionally including a screenshot image."""
    if not screenshot_b64:
        return text

    try:
        image_bytes = base64.b64decode(screenshot_b64)
    except Exception:
        logger.warning("Failed to decode screenshot base64, sending text only")
        return text

    return [
        {"image": {"format": "jpeg", "source": {"bytes": image_bytes}}},
        {"text": text},
    ]


def _friendly_error(exc: Exception) -> str:
    """Convert provider exceptions to user-readable messages."""
    msg = str(exc)
    if "ExpiredTokenException" in msg or "ExpiredToken" in msg:
        return "AWS credentials expired. Run 'ada credentials update' or refresh your AWS session."
    if "AccessDeniedException" in msg:
        return "Access denied. Check your AWS profile and model permissions."
    if "ThrottlingException" in msg:
        return "Request throttled by the model provider. Try again in a few seconds."
    if "ModelNotReadyException" in msg:
        return "Model is not ready. Please try again shortly."
    if "ValidationException" in msg and "model" in msg.lower():
        return f"Invalid model configuration: {msg}"
    if "ConnectTimeoutError" in msg or "ConnectionError" in msg:
        return "Cannot connect to the model provider. Check your network and AWS region."
    return f"Generation failed: {msg}"


# ---------------------------------------------------------------------------
# Output
# ---------------------------------------------------------------------------

# Lock for thread-safe stdout writes (agent runs in a thread)
_stdout_lock = threading.Lock()


def emit(event: dict):
    """Write one JSON line to stdout, flush immediately. Thread-safe."""
    line = json.dumps(event, ensure_ascii=False) + "\n"
    with _stdout_lock:
        sys.stdout.write(line)
        sys.stdout.flush()


# ---------------------------------------------------------------------------
# Generation timeout
# ---------------------------------------------------------------------------
GENERATION_TIMEOUT = 120  # seconds


# ---------------------------------------------------------------------------
# Main loop
# ---------------------------------------------------------------------------

def main():
    mcp_manager.start()
    logger.info("GhostType stdio server started (PID %d)", __import__("os").getpid())

    agent = None
    cancel_event = threading.Event()

    # Track state for agent reuse
    last_config: ModelConfig | None = None
    last_mode_type: str | None = None
    last_agent_id: str | None = None

    try:
        for line in sys.stdin:
            line = line.strip()
            if not line:
                continue

            try:
                request = json.loads(line)
            except json.JSONDecodeError as e:
                logger.warning("Invalid JSON from stdin: %s", e)
                emit({"type": "error", "content": f"Invalid JSON: {e}"})
                continue

            msg_type = request.get("type", "generate")

            # ---- Get agents ----
            if msg_type == "get_agents":
                snapshot = agent_registry.snapshot()
                emit({
                    "type": "agents",
                    "agents": snapshot.to_dicts(),
                    "default_agent_id": snapshot.default_agent_id,
                })
                continue

            # ---- New conversation ----
            if msg_type == "new_conversation":
                agent = None
                last_config = None
                last_mode_type = None
                last_agent_id = None
                emit({"type": "conversation_reset"})
                logger.info("Conversation reset")
                continue

            # ---- Restore history ----
            if msg_type == "restore_history":
                messages = request.get("messages", [])
                model_config = ModelConfig.from_request(request.get("config"))
                mode_type = request.get("mode_type", "draft")
                agent_id = request.get("agent")

                # Resolve agent definition
                snapshot = agent_registry.snapshot()
                resolved_id = agent_id or snapshot.default_agent_id
                agent_def = snapshot.get(resolved_id)

                # Get MCP tools
                mcp_tools = []
                if agent_def and agent_def.mcp_servers:
                    mcp_tools = mcp_manager.get_tools_for_agent(agent_def)

                # Create fresh agent with history
                agent = create_agent(
                    model_config=model_config,
                    mode_type=mode_type,
                    mcp_tools=mcp_tools if mcp_tools else None,
                    agent_def=agent_def,
                )

                # Replay conversation history into agent
                for msg in messages:
                    role = msg.get("role", "user")
                    content = msg.get("content", "")
                    agent.messages.append({"role": role, "content": [{"text": content}]})

                last_config = model_config
                last_mode_type = mode_type
                last_agent_id = resolved_id

                emit({"type": "history_restored"})
                logger.info("History restored: %d messages", len(messages))
                continue

            # ---- Cancel ----
            if msg_type == "cancel":
                cancel_event.set()
                logger.info("Cancel requested")
                continue

            # ---- Generate ----
            if msg_type == "generate":
                cancel_event.clear()

                prompt = request.get("prompt", "")
                context = request.get("context", "")
                mode = request.get("mode", "generate")
                mode_type = request.get("mode_type") or (
                    "draft" if context or mode in ("rewrite", "fix", "translate") else "chat"
                )
                screenshot_b64 = request.get("screenshot")
                browser_ctx_text = request.get("browser_context", "")
                model_config = ModelConfig.from_request(request.get("config"))

                # Resolve agent
                snapshot = agent_registry.snapshot()
                requested_agent_id = request.get("agent") or snapshot.default_agent_id
                agent_def = snapshot.get(requested_agent_id)
                if agent_def is None:
                    emit({"type": "error", "content": f"Unknown agent: {requested_agent_id}"})
                    continue

                # Determine if agent needs recreation
                needs_new_agent = (
                    agent is None
                    or model_config != last_config
                    or mode_type != last_mode_type
                    or requested_agent_id != last_agent_id
                )

                if needs_new_agent:
                    mcp_tools = []
                    if agent_def.mcp_servers:
                        mcp_tools = mcp_manager.get_tools_for_agent(agent_def)

                    handler = StdioCallbackHandler(cancel_event)
                    agent = create_agent(
                        callback_handler=handler,
                        model_config=model_config,
                        mode_type=mode_type,
                        mcp_tools=mcp_tools if mcp_tools else None,
                        agent_def=agent_def,
                    )
                    last_config = model_config
                    last_mode_type = mode_type
                    last_agent_id = requested_agent_id
                    logger.info("Created new agent: id=%s, mode_type=%s", requested_agent_id, mode_type)
                else:
                    # Reuse agent, update callback handler
                    handler = StdioCallbackHandler(cancel_event)
                    agent.callback_handler = handler
                    logger.debug("Reusing agent: id=%s", requested_agent_id)

                # Build message
                text_message = build_message(prompt, context, mode, browser_context=browser_ctx_text)
                user_message = build_multimodal_message(text_message, screenshot_b64)

                logger.info(
                    "Generating: mode=%s, mode_type=%s, prompt_len=%d, context_len=%d, screenshot=%s",
                    mode, mode_type, len(prompt), len(context),
                    "yes" if screenshot_b64 else "no",
                )

                # Run agent in a thread with timeout
                result_text = ""
                error_text = ""
                was_cancelled = False

                def run_agent():
                    nonlocal result_text, error_text, was_cancelled
                    try:
                        result = agent(user_message)
                        # Extract text from Strands result
                        if hasattr(result, "message") and result.message:
                            content_blocks = result.message.get("content", [])
                            result_text = "".join(
                                block.get("text", "") for block in content_blocks if "text" in block
                            )
                    except CancellationError:
                        was_cancelled = True
                        logger.info("Generation cancelled")
                    except Exception as e:
                        error_text = _friendly_error(e)
                        logger.error("Generation failed: %s", e, exc_info=True)

                gen_thread = threading.Thread(target=run_agent, daemon=True)
                gen_thread.start()
                gen_thread.join(timeout=GENERATION_TIMEOUT)

                if gen_thread.is_alive():
                    # Timeout — signal cancellation and wait briefly
                    cancel_event.set()
                    gen_thread.join(timeout=5)
                    emit({"type": "error", "content": "Generation timed out after 120 seconds."})
                elif was_cancelled:
                    emit({"type": "cancelled"})
                elif error_text:
                    emit({"type": "error", "content": error_text})
                else:
                    emit({"type": "done", "content": result_text})

                continue

            # ---- Unknown message type ----
            logger.warning("Unknown message type: %s", msg_type)
            emit({"type": "error", "content": f"Unknown message type: {msg_type}"})

    except KeyboardInterrupt:
        logger.info("Interrupted, shutting down")
    finally:
        mcp_manager.stop()
        logger.info("GhostType stdio server stopped")


if __name__ == "__main__":
    main()
