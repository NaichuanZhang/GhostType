"""Tests for stdio_server.py — message building, error handling, event emission."""

import json
import threading
from io import StringIO
from unittest.mock import patch

import pytest

# Import from the module under test
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent.parent))

from stdio_server import (
    emit,
    StdioCallbackHandler,
    CancellationError,
)
from message_builder import (
    build_message,
    build_multimodal_message,
    friendly_error,
)


# ---------------------------------------------------------------------------
# build_message
# ---------------------------------------------------------------------------


class TestBuildMessage:
    def test_plain_prompt(self):
        result = build_message("hello world", "", "generate")
        assert result == "hello world"

    def test_with_context(self):
        result = build_message("Summarize this", "some text", "generate")
        assert 'Context (selected text' in result
        assert "some text" in result
        assert "Summarize this" in result

    def test_rewrite_mode(self):
        result = build_message("Make it shorter", "long text here", "rewrite")
        assert "Rewrite the following text" in result
        assert "long text here" in result
        assert "Make it shorter" in result

    def test_fix_mode(self):
        result = build_message("", "text with erors", "fix")
        assert "Fix grammar and spelling" in result
        assert "text with erors" in result

    def test_translate_mode(self):
        result = build_message("to Spanish", "Hello", "translate")
        assert "Translate" in result
        assert "to Spanish" in result
        assert "Hello" in result

    def test_browser_context_appended(self):
        result = build_message("hello", "", "generate", browser_context="Page content here")
        assert "Browser page content" in result
        assert "Page content here" in result

    def test_browser_context_empty_not_appended(self):
        result = build_message("hello", "", "generate", browser_context="")
        assert "Browser page content" not in result


# ---------------------------------------------------------------------------
# build_multimodal_message
# ---------------------------------------------------------------------------


class TestBuildMultimodalMessage:
    def test_text_only_returns_string(self):
        result = build_multimodal_message("hello", None)
        assert result == "hello"

    def test_with_screenshot_returns_list(self):
        # A minimal valid base64 JPEG
        import base64
        b64 = base64.b64encode(b"\xff\xd8\xff\xe0test").decode()
        result = build_multimodal_message("hello", b64)
        assert isinstance(result, list)
        assert len(result) == 2
        assert result[0]["image"]["format"] == "jpeg"
        assert result[1]["text"] == "hello"

    def test_invalid_base64_falls_back_to_text(self):
        result = build_multimodal_message("hello", "!!!invalid!!!")
        assert result == "hello"


# ---------------------------------------------------------------------------
# friendly_error
# ---------------------------------------------------------------------------


class TestFriendlyError:
    def test_expired_token(self):
        msg = friendly_error(Exception("ExpiredTokenException: token expired"))
        assert "expired" in msg.lower()

    def test_access_denied(self):
        msg = friendly_error(Exception("AccessDeniedException"))
        assert "Access denied" in msg

    def test_throttling(self):
        msg = friendly_error(Exception("ThrottlingException"))
        assert "throttled" in msg.lower()

    def test_connection_error(self):
        msg = friendly_error(Exception("ConnectionError: cannot connect"))
        assert "connect" in msg.lower()

    def test_generic_error(self):
        msg = friendly_error(Exception("something unexpected"))
        assert "Generation failed" in msg


# ---------------------------------------------------------------------------
# emit
# ---------------------------------------------------------------------------


class TestEmit:
    def test_emit_writes_json_line(self):
        buf = StringIO()
        with patch("stdio_server.sys.stdout", buf):
            emit({"type": "token", "content": "hello"})

        output = buf.getvalue()
        assert output.endswith("\n")
        parsed = json.loads(output.strip())
        assert parsed["type"] == "token"
        assert parsed["content"] == "hello"

    def test_emit_thread_safe(self):
        """Multiple threads emitting concurrently should not interleave."""
        buf = StringIO()
        results = []

        def worker(n):
            with patch("stdio_server.sys.stdout", buf):
                emit({"type": "token", "content": f"word{n}"})

        threads = [threading.Thread(target=worker, args=(i,)) for i in range(10)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()

        # Each line should be valid JSON
        lines = buf.getvalue().strip().split("\n")
        assert len(lines) == 10
        for line in lines:
            parsed = json.loads(line)
            assert parsed["type"] == "token"


# ---------------------------------------------------------------------------
# StdioCallbackHandler
# ---------------------------------------------------------------------------


class TestStdioCallbackHandler:
    def test_token_streaming(self):
        buf = StringIO()
        cancel = threading.Event()
        handler = StdioCallbackHandler(cancel)

        with patch("stdio_server.sys.stdout", buf):
            handler(data="Hello")
            handler(data=" world")

        lines = buf.getvalue().strip().split("\n")
        assert len(lines) == 2
        assert json.loads(lines[0])["content"] == "Hello"
        assert json.loads(lines[1])["content"] == " world"
        assert handler.token_count == 2

    def test_cancellation_raises(self):
        cancel = threading.Event()
        cancel.set()
        handler = StdioCallbackHandler(cancel)

        with pytest.raises(CancellationError):
            handler(data="should not emit")

    def test_tool_events(self):
        buf = StringIO()
        cancel = threading.Event()
        handler = StdioCallbackHandler(cancel)

        with patch("stdio_server.sys.stdout", buf):
            # Simulate tool start event
            handler(event={
                "contentBlockStart": {
                    "start": {
                        "toolUse": {"name": "search", "toolUseId": "t1"}
                    }
                }
            })
            # Simulate tool input
            handler(current_tool_use={"input": {"query": "test"}})
            # Simulate text after tool (closes tool)
            handler(data="Result text")

        lines = buf.getvalue().strip().split("\n")
        events = [json.loads(l) for l in lines]

        assert events[0]["type"] == "tool_start"
        assert events[0]["tool_name"] == "search"
        assert events[0]["tool_id"] == "t1"
        assert events[1]["type"] == "tool_done"
        assert events[1]["tool_name"] == "search"
        assert events[2]["type"] == "token"
        assert events[2]["content"] == "Result text"

    def test_complete_closes_active_tool(self):
        buf = StringIO()
        cancel = threading.Event()
        handler = StdioCallbackHandler(cancel)

        with patch("stdio_server.sys.stdout", buf):
            handler(event={
                "contentBlockStart": {
                    "start": {
                        "toolUse": {"name": "calc", "toolUseId": "t2"}
                    }
                }
            })
            handler(complete=True, data="final")

        lines = buf.getvalue().strip().split("\n")
        events = [json.loads(l) for l in lines]

        types = [e["type"] for e in events]
        assert "tool_start" in types
        assert "tool_done" in types
        assert "token" in types
