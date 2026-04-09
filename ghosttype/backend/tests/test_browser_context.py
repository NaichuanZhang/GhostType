"""Tests for browser_context.py — BrowserContext dataclass and BrowserContextStore."""

import time
from datetime import datetime

import pytest


# ---------------------------------------------------------------------------
# BrowserContext dataclass tests
# ---------------------------------------------------------------------------
class TestBrowserContext:
    def test_creation(self):
        from browser_context import BrowserContext

        ctx = BrowserContext(
            url="https://example.com",
            title="Example",
            content="Hello world",
            selected_text="world",
            timestamp=1234567890.0,
        )
        assert ctx.url == "https://example.com"
        assert ctx.title == "Example"
        assert ctx.content == "Hello world"
        assert ctx.selected_text == "world"
        assert ctx.timestamp == 1234567890.0

    def test_immutability(self):
        from browser_context import BrowserContext

        ctx = BrowserContext(
            url="https://example.com",
            title="Example",
            content="body",
            selected_text="",
            timestamp=0.0,
        )
        with pytest.raises(AttributeError):
            ctx.url = "https://other.com"

    def test_to_dict(self):
        from browser_context import BrowserContext

        ctx = BrowserContext(
            url="https://example.com",
            title="Example",
            content="body text",
            selected_text="text",
            timestamp=100.0,
        )
        d = ctx.to_dict()
        assert d == {
            "url": "https://example.com",
            "title": "Example",
            "content": "body text",
            "selected_text": "text",
            "timestamp": 100.0,
            "xhr_data": [],
        }


# ---------------------------------------------------------------------------
# BrowserContextStore tests
# ---------------------------------------------------------------------------
class TestBrowserContextStore:
    def test_get_empty_returns_none(self):
        from browser_context import BrowserContextStore

        store = BrowserContextStore()
        assert store.get() is None

    def test_set_and_get(self):
        from browser_context import BrowserContext, BrowserContextStore

        store = BrowserContextStore()
        ctx = BrowserContext(
            url="https://example.com",
            title="Example",
            content="page content",
            selected_text="",
            timestamp=time.time(),
        )
        store.set(ctx)
        result = store.get()
        assert result is not None
        assert result.url == "https://example.com"
        assert result.content == "page content"

    def test_overwrite(self):
        from browser_context import BrowserContext, BrowserContextStore

        store = BrowserContextStore()
        ctx1 = BrowserContext(
            url="https://first.com", title="First", content="a",
            selected_text="", timestamp=1.0,
        )
        ctx2 = BrowserContext(
            url="https://second.com", title="Second", content="b",
            selected_text="", timestamp=2.0,
        )
        store.set(ctx1)
        store.set(ctx2)
        result = store.get()
        assert result is not None
        assert result.url == "https://second.com"

    def test_clear(self):
        from browser_context import BrowserContext, BrowserContextStore

        store = BrowserContextStore()
        ctx = BrowserContext(
            url="https://example.com", title="Example", content="x",
            selected_text="", timestamp=0.0,
        )
        store.set(ctx)
        store.clear()
        assert store.get() is None

    def test_to_dict_when_empty(self):
        from browser_context import BrowserContextStore

        store = BrowserContextStore()
        d = store.to_dict()
        assert d == {"available": False, "context": None}

    def test_to_dict_when_populated(self):
        from browser_context import BrowserContext, BrowserContextStore

        store = BrowserContextStore()
        ctx = BrowserContext(
            url="https://example.com", title="Example", content="body",
            selected_text="sel", timestamp=42.0,
        )
        store.set(ctx)
        d = store.to_dict()
        assert d["available"] is True
        assert d["context"]["url"] == "https://example.com"
        assert d["context"]["title"] == "Example"




# ---------------------------------------------------------------------------
# BrowserContext with xhr_data
# ---------------------------------------------------------------------------
class TestBrowserContextXhrData:
    def test_default_xhr_data_is_empty_tuple(self):
        from browser_context import BrowserContext

        ctx = BrowserContext(
            url="https://example.com", title="Example", content="body",
            selected_text="", timestamp=0.0,
        )
        assert ctx.xhr_data == ()

    def test_creation_with_xhr_data(self):
        from browser_context import BrowserContext

        entries = (
            {"url": "https://api.example.com/data", "data": {"items": [1, 2]}},
        )
        ctx = BrowserContext(
            url="https://example.com", title="Example", content="body",
            selected_text="", timestamp=0.0, xhr_data=entries,
        )
        assert len(ctx.xhr_data) == 1
        assert ctx.xhr_data[0]["url"] == "https://api.example.com/data"

    def test_to_dict_includes_xhr_data(self):
        from browser_context import BrowserContext

        entries = (
            {"url": "https://api.example.com/v1", "data": {"ok": True}},
        )
        ctx = BrowserContext(
            url="https://example.com", title="T", content="C",
            selected_text="", timestamp=1.0, xhr_data=entries,
        )
        d = ctx.to_dict()
        assert "xhr_data" in d
        assert isinstance(d["xhr_data"], list)
        assert d["xhr_data"][0]["url"] == "https://api.example.com/v1"

    def test_to_dict_empty_xhr_data_is_empty_list(self):
        from browser_context import BrowserContext

        ctx = BrowserContext(
            url="https://example.com", title="T", content="C",
            selected_text="", timestamp=1.0,
        )
        d = ctx.to_dict()
        assert d["xhr_data"] == []

    def test_store_round_trip_with_xhr_data(self):
        from browser_context import BrowserContext, BrowserContextStore

        entries = (
            {"url": "https://api.example.com/users", "data": {"count": 5}},
            {"url": "https://api.example.com/posts", "data": {"count": 10}},
        )
        store = BrowserContextStore()
        ctx = BrowserContext(
            url="https://example.com", title="T", content="C",
            selected_text="", timestamp=1.0, xhr_data=entries,
        )
        store.set(ctx)
        result = store.get()
        assert result is not None
        assert len(result.xhr_data) == 2
        assert result.xhr_data[1]["data"]["count"] == 10


class TestBuildMessageWithBrowserContext:
    def test_no_browser_context(self):
        from message_builder import build_message

        result = build_message("Summarize", "", "generate")
        assert "Browser page content" not in result

    def test_with_browser_context(self):
        from message_builder import build_message

        result = build_message(
            "Summarize this page", "", "generate",
            browser_context="This is the full page text from Chrome.",
        )
        assert "Browser page content" in result
        assert "This is the full page text from Chrome." in result
        assert "Summarize this page" in result

    def test_browser_context_with_selected_context(self):
        from message_builder import build_message

        result = build_message(
            "Explain this", "selected text", "generate",
            browser_context="Full page body",
        )
        assert "selected text" in result
        assert "Full page body" in result
        assert "Browser page content" in result
