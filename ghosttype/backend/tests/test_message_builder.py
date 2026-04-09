"""Tests for message_builder.py — shared message construction utilities."""

import base64

import pytest

from message_builder import build_message, build_multimodal_message, friendly_error


# ---------------------------------------------------------------------------
# build_message
# ---------------------------------------------------------------------------

class TestBuildMessage:
    def test_generate_mode_plain_prompt(self):
        result = build_message("Write a haiku", "", "generate")
        assert result == "Write a haiku"

    def test_generate_mode_with_context(self):
        result = build_message("Summarize this", "some text", "generate")
        assert "some text" in result
        assert "Summarize this" in result

    def test_rewrite_mode_with_context(self):
        result = build_message("Make shorter", "long text", "rewrite")
        assert "Rewrite the following text" in result
        assert "long text" in result
        assert "Make shorter" in result

    def test_fix_mode_with_context(self):
        result = build_message("", "teh cat", "fix")
        assert "Fix grammar and spelling" in result
        assert "teh cat" in result

    def test_translate_mode_with_context(self):
        result = build_message("to Spanish", "hello", "translate")
        assert "Translate" in result
        assert "hello" in result
        assert "to Spanish" in result

    def test_browser_context_appended(self):
        result = build_message("Summarize", "", "generate", browser_context="Page content here")
        assert "Browser page content" in result
        assert "Page content here" in result

    def test_no_browser_context_by_default(self):
        result = build_message("Hello", "", "generate")
        assert "Browser page content" not in result

    def test_browser_context_combined_with_selected_context(self):
        result = build_message("Explain", "selected text", "generate", browser_context="Full page")
        assert "selected text" in result
        assert "Full page" in result


# ---------------------------------------------------------------------------
# build_multimodal_message
# ---------------------------------------------------------------------------

class TestBuildMultimodalMessage:
    def test_text_only_when_no_screenshot(self):
        result = build_multimodal_message("hello", None)
        assert result == "hello"

    def test_text_only_when_empty_screenshot(self):
        result = build_multimodal_message("hello", "")
        assert result == "hello"

    def test_with_valid_screenshot_returns_list(self):
        screenshot = base64.b64encode(b"fake jpeg data").decode()
        result = build_multimodal_message("describe this", screenshot)
        assert isinstance(result, list)
        assert len(result) == 2
        assert result[0]["image"]["format"] == "jpeg"
        assert result[1]["text"] == "describe this"

    def test_invalid_base64_falls_back_to_text(self):
        result = build_multimodal_message("hello", "not-valid-base64!!!")
        assert result == "hello"


# ---------------------------------------------------------------------------
# friendly_error
# ---------------------------------------------------------------------------

class TestFriendlyError:
    def test_expired_token(self):
        msg = friendly_error(Exception("ExpiredTokenException: token expired"))
        assert "credentials expired" in msg.lower()

    def test_access_denied(self):
        msg = friendly_error(Exception("AccessDeniedException"))
        assert "access denied" in msg.lower()

    def test_throttling(self):
        msg = friendly_error(Exception("ThrottlingException"))
        assert "throttled" in msg.lower()

    def test_connection_error(self):
        msg = friendly_error(Exception("ConnectionError: cannot connect"))
        assert "connect" in msg.lower()

    def test_generic_error(self):
        msg = friendly_error(Exception("something unexpected"))
        assert "Generation failed" in msg
        assert "something unexpected" in msg
