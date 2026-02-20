"""Tests for server.py — build_message, _friendly_error, and WebSocket endpoint."""

import asyncio
import json
import logging
import threading
import time
from unittest import mock

import pytest

logger = logging.getLogger(__name__)


# ---------------------------------------------------------------------------
# build_message tests
# ---------------------------------------------------------------------------
class TestBuildMessage:
    def test_generate_no_context(self):
        from server import build_message

        result = build_message("Write an email", "", "generate")
        assert result == "Write an email"

    def test_generate_with_context(self):
        from server import build_message

        result = build_message("Summarize this", "Some long text here", "generate")
        assert "Some long text here" in result
        assert "Summarize this" in result
        assert "Context" in result

    def test_rewrite_mode(self):
        from server import build_message

        result = build_message("Make it formal", "Hey dude", "rewrite")
        assert "Rewrite" in result
        assert "Hey dude" in result
        assert "Make it formal" in result

    def test_fix_mode(self):
        from server import build_message

        result = build_message("", "Ths has errros", "fix")
        assert "Fix grammar" in result
        assert "Ths has errros" in result

    def test_translate_mode(self):
        from server import build_message

        result = build_message("to Spanish", "Hello world", "translate")
        assert "Translate" in result
        assert "Hello world" in result
        assert "to Spanish" in result

    def test_rewrite_without_context_falls_through(self):
        from server import build_message

        result = build_message("Rewrite something", "", "rewrite")
        # Without context, rewrite mode falls through to plain prompt
        assert result == "Rewrite something"

    def test_unknown_mode_with_context(self):
        from server import build_message

        result = build_message("Do something", "context text", "unknown_mode")
        assert "context text" in result
        assert "Do something" in result


# ---------------------------------------------------------------------------
# build_multimodal_message tests
# ---------------------------------------------------------------------------
class TestBuildMultimodalMessage:
    def test_no_screenshot_returns_string(self):
        from server import build_multimodal_message

        result = build_multimodal_message("Hello world", None)
        assert result == "Hello world"

    def test_empty_screenshot_returns_string(self):
        from server import build_multimodal_message

        result = build_multimodal_message("Hello world", "")
        assert result == "Hello world"

    def test_with_screenshot_returns_content_blocks(self):
        import base64
        from server import build_multimodal_message

        fake_image = base64.b64encode(b"fake-jpeg-data").decode()
        result = build_multimodal_message("Describe this", fake_image)

        assert isinstance(result, list)
        assert len(result) == 2
        assert "image" in result[0]
        assert result[0]["image"]["format"] == "jpeg"
        assert result[0]["image"]["source"]["bytes"] == b"fake-jpeg-data"
        assert result[1] == {"text": "Describe this"}

    def test_invalid_base64_falls_back_to_string(self):
        from server import build_multimodal_message

        result = build_multimodal_message("Hello", "not-valid-base64!!!")
        assert result == "Hello"


# ---------------------------------------------------------------------------
# _friendly_error tests
# ---------------------------------------------------------------------------
class TestFriendlyError:
    def test_rate_limit_error(self):
        from server import _friendly_error

        err = Exception("Rate limit exceeded for model xyz")
        result = _friendly_error(err)
        assert "Rate limit" in result
        assert "wait" in result.lower()

    def test_authentication_error(self):
        from server import _friendly_error

        err = Exception("Authentication failed: invalid API key")
        result = _friendly_error(err)
        assert "Authentication" in result

    def test_credentials_error(self):
        from server import _friendly_error

        err = Exception("Unable to locate credentials")
        result = _friendly_error(err)
        assert "Authentication" in result

    def test_timeout_error(self):
        from server import _friendly_error

        err = Exception("Connection timeout after 30s")
        result = _friendly_error(err)
        assert "timed out" in result.lower()

    def test_expired_token_error(self):
        from server import _friendly_error

        err = Exception("ExpiredTokenException: security token has expired")
        result = _friendly_error(err)
        assert "expired" in result.lower()
        assert "tokenmaster" in result.lower()

    def test_generic_error_includes_type(self):
        from server import _friendly_error

        err = ValueError("something went wrong")
        result = _friendly_error(err)
        assert "ValueError" in result
        assert "something went wrong" in result


# ---------------------------------------------------------------------------
# StreamingCallbackHandler tests
# ---------------------------------------------------------------------------
class TestStreamingCallbackHandler:
    def _make_handler(self, cancel_event=None):
        """Create a StreamingCallbackHandler with mocked WebSocket."""
        from server import StreamingCallbackHandler

        ws = mock.AsyncMock()
        loop = asyncio.new_event_loop()
        cancel = cancel_event or threading.Event()

        handler = StreamingCallbackHandler(
            websocket=ws,
            loop=loop,
            cancel_event=cancel,
        )
        return handler, ws, loop

    def test_sends_token_on_data(self):
        """Handler should send a token message when data is received."""
        from server import StreamingCallbackHandler

        ws = mock.MagicMock()
        loop = asyncio.new_event_loop()

        handler = StreamingCallbackHandler(
            websocket=ws,
            loop=loop,
            cancel_event=threading.Event(),
        )

        # Mock _send_ws_message to avoid real async scheduling
        handler._send_ws_message = mock.MagicMock()

        handler(data="Hello")

        handler._send_ws_message.assert_called_once_with({
            "type": "token",
            "content": "Hello",
        })
        assert handler.token_count == 1

    def test_tracks_first_token_time(self):
        from server import StreamingCallbackHandler

        handler = StreamingCallbackHandler(
            websocket=mock.MagicMock(),
            loop=asyncio.new_event_loop(),
            cancel_event=threading.Event(),
        )
        handler._send_ws_message = mock.MagicMock()

        assert handler.first_token_time is None
        handler(data="first")
        assert handler.first_token_time is not None

        first_time = handler.first_token_time
        handler(data="second")
        # Should not change after first token
        assert handler.first_token_time == first_time

    def test_increments_token_count(self):
        from server import StreamingCallbackHandler

        handler = StreamingCallbackHandler(
            websocket=mock.MagicMock(),
            loop=asyncio.new_event_loop(),
            cancel_event=threading.Event(),
        )
        handler._send_ws_message = mock.MagicMock()

        handler(data="a")
        handler(data="b")
        handler(data="c")
        assert handler.token_count == 3

    def test_ignores_empty_data(self):
        from server import StreamingCallbackHandler

        handler = StreamingCallbackHandler(
            websocket=mock.MagicMock(),
            loop=asyncio.new_event_loop(),
            cancel_event=threading.Event(),
        )
        handler._send_ws_message = mock.MagicMock()

        handler(data="")
        handler(complete=True)

        handler._send_ws_message.assert_not_called()
        assert handler.token_count == 0

    def test_cancel_raises_cancellation_error(self):
        from server import StreamingCallbackHandler, CancellationError

        cancel = threading.Event()
        cancel.set()  # Already cancelled

        handler = StreamingCallbackHandler(
            websocket=mock.MagicMock(),
            loop=asyncio.new_event_loop(),
            cancel_event=cancel,
        )

        with pytest.raises(CancellationError):
            handler(data="should not get here")


# ---------------------------------------------------------------------------
# _run_agent tests
# ---------------------------------------------------------------------------
class TestRunAgent:
    def test_runs_agent_with_message(self):
        from server import _run_agent

        mock_agent = mock.MagicMock()
        mock_agent.return_value = "response"
        cancel = threading.Event()

        result = _run_agent(mock_agent, "hello", cancel)

        mock_agent.assert_called_once_with("hello")
        assert result == "response"

    def test_raises_if_already_cancelled(self):
        from server import _run_agent, CancellationError

        mock_agent = mock.MagicMock()
        cancel = threading.Event()
        cancel.set()

        with pytest.raises(CancellationError, match="before start"):
            _run_agent(mock_agent, "hello", cancel)

        mock_agent.assert_not_called()


# ---------------------------------------------------------------------------
# WebSocket endpoint integration tests (using FastAPI TestClient)
# ---------------------------------------------------------------------------
class TestWebSocketEndpoint:
    @pytest.fixture
    def mock_agent(self):
        """Patch create_agent to return a mock that simulates streaming."""
        with mock.patch("server.create_agent") as mock_create:
            agent = mock.MagicMock()
            agent.return_value = "Generated text response"
            mock_create.return_value = agent
            yield agent, mock_create

    def test_health_endpoint(self):
        from fastapi.testclient import TestClient
        from server import app

        client = TestClient(app)
        resp = client.get("/health")
        assert resp.status_code == 200
        data = resp.json()
        assert data["status"] == "ok"
        assert "provider" in data
        assert "model" in data

    def test_generate_returns_done(self, mock_agent):
        from fastapi.testclient import TestClient
        from server import app

        agent, mock_create = mock_agent
        client = TestClient(app)

        with client.websocket_connect("/generate") as ws:
            ws.send_text(json.dumps({
                "prompt": "Write hello",
                "mode": "generate",
            }))

            # Collect all messages until we get "done"
            messages = []
            for _ in range(20):  # Safety limit
                raw = ws.receive_text()
                msg = json.loads(raw)
                messages.append(msg)
                if msg["type"] in ("done", "error"):
                    break

            types = [m["type"] for m in messages]
            assert "done" in types
            done_msg = next(m for m in messages if m["type"] == "done")
            assert done_msg["content"] == "Generated text response"

    def test_empty_prompt_returns_error(self, mock_agent):
        from fastapi.testclient import TestClient
        from server import app

        client = TestClient(app)

        with client.websocket_connect("/generate") as ws:
            ws.send_text(json.dumps({
                "prompt": "",
                "mode": "generate",
            }))

            raw = ws.receive_text()
            msg = json.loads(raw)
            assert msg["type"] == "error"
            assert "Empty prompt" in msg["content"]

    def test_invalid_json_returns_error(self, mock_agent):
        from fastapi.testclient import TestClient
        from server import app

        client = TestClient(app)

        with client.websocket_connect("/generate") as ws:
            ws.send_text("not valid json {{{")

            raw = ws.receive_text()
            msg = json.loads(raw)
            assert msg["type"] == "error"
            assert "Invalid JSON" in msg["content"]

    def test_agent_error_returns_error_message(self):
        """When the agent raises, server should send error and keep WS alive."""
        from fastapi.testclient import TestClient
        from server import app

        with mock.patch("server.create_agent") as mock_create:
            agent = mock.MagicMock()
            agent.side_effect = RuntimeError("Model exploded")
            mock_create.return_value = agent

            client = TestClient(app)

            with client.websocket_connect("/generate") as ws:
                ws.send_text(json.dumps({
                    "prompt": "Hello",
                    "mode": "generate",
                }))

                raw = ws.receive_text()
                msg = json.loads(raw)
                assert msg["type"] == "error"
                assert "Model exploded" in msg["content"]

                # WebSocket should still be alive — send another request
                ws.send_text(json.dumps({
                    "prompt": "Try again",
                    "mode": "generate",
                }))

                raw2 = ws.receive_text()
                msg2 = json.loads(raw2)
                # Should get another error (same mock), not a disconnect
                assert msg2["type"] == "error"

    def test_fix_mode_allows_empty_prompt(self, mock_agent):
        """Fix mode doesn't need a prompt — just context."""
        from fastapi.testclient import TestClient
        from server import app

        agent, _ = mock_agent
        client = TestClient(app)

        with client.websocket_connect("/generate") as ws:
            ws.send_text(json.dumps({
                "prompt": "",
                "context": "Ths has errros",
                "mode": "fix",
            }))

            messages = []
            for _ in range(20):
                raw = ws.receive_text()
                msg = json.loads(raw)
                messages.append(msg)
                if msg["type"] in ("done", "error"):
                    break

            types = [m["type"] for m in messages]
            assert "done" in types


# ---------------------------------------------------------------------------
# classify_mode_type tests
# ---------------------------------------------------------------------------
class TestClassifyModeType:
    def test_rewrite_mode_returns_draft(self):
        from server import classify_mode_type

        assert classify_mode_type("rewrite", "", "Make it formal") == "draft"

    def test_fix_mode_returns_draft(self):
        from server import classify_mode_type

        assert classify_mode_type("fix", "", "") == "draft"

    def test_translate_mode_returns_draft(self):
        from server import classify_mode_type

        assert classify_mode_type("translate", "", "to Spanish") == "draft"

    def test_context_present_returns_draft(self):
        from server import classify_mode_type

        assert classify_mode_type("generate", "Some selected text", "Summarize") == "draft"

    def test_no_context_generate_returns_chat(self):
        from server import classify_mode_type

        assert classify_mode_type("generate", "", "What is Python?") == "chat"

    def test_empty_everything_returns_chat(self):
        from server import classify_mode_type

        assert classify_mode_type("generate", "", "") == "chat"


# ---------------------------------------------------------------------------
# Multi-turn conversation tests
# ---------------------------------------------------------------------------
class TestMultiTurnConversation:
    def test_agent_reused_across_messages(self):
        """Agent should be created once and reused for subsequent messages."""
        from fastapi.testclient import TestClient
        from server import app

        with mock.patch("server.create_agent") as mock_create:
            agent = mock.MagicMock()
            agent.return_value = "Response"
            mock_create.return_value = agent

            client = TestClient(app)

            with client.websocket_connect("/generate") as ws:
                # First message — agent should be created
                ws.send_text(json.dumps({
                    "prompt": "Hello",
                    "mode": "generate",
                }))
                for _ in range(20):
                    msg = json.loads(ws.receive_text())
                    if msg["type"] in ("done", "error"):
                        break
                assert mock_create.call_count == 1

                # Second message with same config — agent should be reused
                ws.send_text(json.dumps({
                    "prompt": "Follow up",
                    "mode": "generate",
                }))
                for _ in range(20):
                    msg = json.loads(ws.receive_text())
                    if msg["type"] in ("done", "error"):
                        break

                # Agent should NOT have been recreated
                assert mock_create.call_count == 1
                # But agent should have been called twice
                assert agent.call_count == 2

    def test_mode_switch_recreates_agent(self):
        """Switching from chat to draft mode should recreate the agent."""
        from fastapi.testclient import TestClient
        from server import app

        with mock.patch("server.create_agent") as mock_create:
            agent = mock.MagicMock()
            agent.return_value = "Response"
            mock_create.return_value = agent

            client = TestClient(app)

            with client.websocket_connect("/generate") as ws:
                # First message — chat mode (no context, generate mode)
                ws.send_text(json.dumps({
                    "prompt": "What is Python?",
                    "mode": "generate",
                    "mode_type": "chat",
                }))
                for _ in range(20):
                    msg = json.loads(ws.receive_text())
                    if msg["type"] in ("done", "error"):
                        break
                assert mock_create.call_count == 1

                # Second message — draft mode (explicit mode_type)
                ws.send_text(json.dumps({
                    "prompt": "Rewrite this",
                    "context": "Some text",
                    "mode": "rewrite",
                    "mode_type": "draft",
                }))
                for _ in range(20):
                    msg = json.loads(ws.receive_text())
                    if msg["type"] in ("done", "error"):
                        break

                # Agent should have been recreated due to mode switch
                assert mock_create.call_count == 2

    def test_new_conversation_resets_agent(self):
        """Sending new_conversation should reset the agent."""
        from fastapi.testclient import TestClient
        from server import app

        with mock.patch("server.create_agent") as mock_create:
            agent = mock.MagicMock()
            agent.return_value = "Response"
            mock_create.return_value = agent

            client = TestClient(app)

            with client.websocket_connect("/generate") as ws:
                # First message
                ws.send_text(json.dumps({
                    "prompt": "Hello",
                    "mode": "generate",
                }))
                for _ in range(20):
                    msg = json.loads(ws.receive_text())
                    if msg["type"] in ("done", "error"):
                        break
                assert mock_create.call_count == 1

                # Send new_conversation
                ws.send_text(json.dumps({"type": "new_conversation"}))
                reset_msg = json.loads(ws.receive_text())
                assert reset_msg["type"] == "conversation_reset"

                # Next message should create a new agent
                ws.send_text(json.dumps({
                    "prompt": "Fresh start",
                    "mode": "generate",
                }))
                for _ in range(20):
                    msg = json.loads(ws.receive_text())
                    if msg["type"] in ("done", "error"):
                        break

                # Agent should have been recreated after reset
                assert mock_create.call_count == 2

    def test_config_change_recreates_agent(self):
        """Changing model config should recreate the agent."""
        from fastapi.testclient import TestClient
        from server import app

        with mock.patch("server.create_agent") as mock_create:
            agent = mock.MagicMock()
            agent.return_value = "Response"
            mock_create.return_value = agent

            client = TestClient(app)

            with client.websocket_connect("/generate") as ws:
                # First message with default config
                ws.send_text(json.dumps({
                    "prompt": "Hello",
                    "mode": "generate",
                }))
                for _ in range(20):
                    msg = json.loads(ws.receive_text())
                    if msg["type"] in ("done", "error"):
                        break
                assert mock_create.call_count == 1

                # Second message with different config
                ws.send_text(json.dumps({
                    "prompt": "Hello again",
                    "mode": "generate",
                    "config": {
                        "provider": "bedrock",
                        "model_id": "different-model",
                    },
                }))
                for _ in range(20):
                    msg = json.loads(ws.receive_text())
                    if msg["type"] in ("done", "error"):
                        break

                # Agent should have been recreated due to config change
                assert mock_create.call_count == 2


# ---------------------------------------------------------------------------
# Cancel-during-generation tests (concurrent cancel listener)
# ---------------------------------------------------------------------------
class TestCancelDuringGeneration:
    @staticmethod
    def _make_streaming_mock(side_effect_fn):
        """Create a mock agent whose create_agent properly wires the callback_handler.

        The real ``create_agent`` sets ``callback_handler`` on the Agent at
        construction time. Our mock needs to replicate that so the
        side_effect function can call the real ``StreamingCallbackHandler``
        (which checks ``cancel_event`` on every invocation).
        """
        agent_obj = mock.MagicMock()
        agent_obj.side_effect = side_effect_fn

        def create_agent_side_effect(**kwargs):
            handler = kwargs.get("callback_handler")
            if handler is not None:
                agent_obj.callback_handler = handler
            return agent_obj

        return agent_obj, create_agent_side_effect

    def test_cancel_interrupts_streaming_agent(self):
        """Cancel message sent during generation should stop the agent.

        The server's concurrent cancel listener reads WebSocket messages
        while the agent runs in a thread pool, allowing cancel to take
        effect immediately instead of sitting in the buffer.
        """
        from fastapi.testclient import TestClient
        from server import app, CancellationError

        gen_started = threading.Event()

        def streaming_agent(message):
            gen_started.set()
            handler = agent_obj.callback_handler
            # Simulate streaming tokens — the real handler checks
            # cancel_event on every callback invocation.
            for i in range(200):
                time.sleep(0.02)
                if callable(handler):
                    handler(data=f"tok{i} ")
            return "Full response (should not reach here)"

        agent_obj, create_side_effect = self._make_streaming_mock(streaming_agent)

        with mock.patch("server.create_agent", side_effect=create_side_effect):
            client = TestClient(app)

            with client.websocket_connect("/generate") as ws:
                ws.send_text(json.dumps({
                    "prompt": "Tell me a long story",
                    "mode": "generate",
                }))

                # Wait until the agent has started streaming
                assert gen_started.wait(timeout=5), "Agent never started"
                time.sleep(0.15)  # let a few tokens flow

                # Send cancel — the concurrent listener should pick this up
                ws.send_text(json.dumps({"type": "cancel"}))

                # Collect all messages
                messages = []
                for _ in range(500):
                    raw = ws.receive_text()
                    msg = json.loads(raw)
                    messages.append(msg)
                    if msg["type"] in ("done", "error", "cancelled"):
                        break

                types = [m["type"] for m in messages]
                assert "cancelled" in types, (
                    f"Expected 'cancelled' in message types, got: {types[-5:]}"
                )

    def test_cancel_before_first_token(self):
        """Cancel sent before the agent produces any tokens should still work."""
        from fastapi.testclient import TestClient
        from server import app, CancellationError

        gen_started = threading.Event()

        def slow_start_agent(message):
            gen_started.set()
            handler = agent_obj.callback_handler
            # Simulate a long time-to-first-token — handler is called
            # with empty data (no tokens emitted yet), but cancel_event
            # is still checked on every invocation.
            for _ in range(100):
                time.sleep(0.05)
                if callable(handler):
                    handler(data="")  # empty data — TTFT not reached
            return "Should have been cancelled"

        agent_obj, create_side_effect = self._make_streaming_mock(slow_start_agent)

        with mock.patch("server.create_agent", side_effect=create_side_effect):
            client = TestClient(app)

            with client.websocket_connect("/generate") as ws:
                ws.send_text(json.dumps({
                    "prompt": "Hello",
                    "mode": "generate",
                }))

                assert gen_started.wait(timeout=5)
                time.sleep(0.1)

                ws.send_text(json.dumps({"type": "cancel"}))

                messages = []
                for _ in range(100):
                    raw = ws.receive_text()
                    msg = json.loads(raw)
                    messages.append(msg)
                    if msg["type"] in ("done", "error", "cancelled"):
                        break

                types = [m["type"] for m in messages]
                assert "cancelled" in types or "done" in types

    def test_multi_turn_with_cancel_recovery(self):
        """After cancelling a generation, the next turn should work normally."""
        from fastapi.testclient import TestClient
        from server import app, CancellationError

        gen_started = threading.Event()
        call_count = {"n": 0}

        def agent_side_effect(message):
            call_count["n"] += 1
            handler = agent_obj.callback_handler
            if call_count["n"] == 1:
                # First call: slow — will be cancelled
                gen_started.set()
                for i in range(200):
                    time.sleep(0.02)
                    if callable(handler):
                        handler(data=f"slow{i} ")
                return "Slow response"
            else:
                # Second call: fast — should complete normally
                return "Fast response"

        agent_obj, create_side_effect = self._make_streaming_mock(agent_side_effect)

        with mock.patch("server.create_agent", side_effect=create_side_effect):
            client = TestClient(app)

            with client.websocket_connect("/generate") as ws:
                # --- Turn 1: send and cancel ---
                ws.send_text(json.dumps({
                    "prompt": "Slow prompt",
                    "mode": "generate",
                }))
                assert gen_started.wait(timeout=5)
                time.sleep(0.15)
                ws.send_text(json.dumps({"type": "cancel"}))

                for _ in range(500):
                    msg = json.loads(ws.receive_text())
                    if msg["type"] in ("done", "error", "cancelled"):
                        break

                # --- Turn 2: should work normally ---
                ws.send_text(json.dumps({
                    "prompt": "Fast prompt",
                    "mode": "generate",
                }))

                messages = []
                for _ in range(50):
                    raw = ws.receive_text()
                    msg = json.loads(raw)
                    messages.append(msg)
                    if msg["type"] in ("done", "error"):
                        break

                types = [m["type"] for m in messages]
                assert "done" in types, (
                    f"Turn 2 should complete normally, got: {types}"
                )
                done_msg = next(m for m in messages if m["type"] == "done")
                assert done_msg["content"] == "Fast response"


# ---------------------------------------------------------------------------
# Generation timeout tests
# ---------------------------------------------------------------------------
class TestGenerationTimeout:
    def test_timeout_sends_error_and_resets_agent(self):
        """When generation exceeds GENERATION_TIMEOUT, server should send
        an error and reset the agent for a clean slate on the next request.
        """
        from fastapi.testclient import TestClient
        import server
        from server import app

        original_timeout = server.GENERATION_TIMEOUT

        with mock.patch("server.create_agent") as mock_create:
            agent_obj = mock.MagicMock()

            def hanging_agent(message):
                # Block longer than the timeout
                time.sleep(10)
                return "Too late"

            agent_obj.side_effect = hanging_agent
            mock_create.return_value = agent_obj

            # Use a very short timeout for testing
            server.GENERATION_TIMEOUT = 1

            try:
                client = TestClient(app)

                with client.websocket_connect("/generate") as ws:
                    ws.send_text(json.dumps({
                        "prompt": "Hang forever",
                        "mode": "generate",
                    }))

                    messages = []
                    for _ in range(50):
                        raw = ws.receive_text()
                        msg = json.loads(raw)
                        messages.append(msg)
                        if msg["type"] in ("done", "error", "cancelled"):
                            break

                    types = [m["type"] for m in messages]
                    assert "error" in types, (
                        f"Expected timeout error, got: {types}"
                    )
                    error_msg = next(m for m in messages if m["type"] == "error")
                    assert "timed out" in error_msg["content"].lower()
            finally:
                server.GENERATION_TIMEOUT = original_timeout
