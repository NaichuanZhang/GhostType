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
# REST endpoint tests (using httpx.AsyncClient + FastAPI TestClient)
# ---------------------------------------------------------------------------
class TestBrowserContextEndpoints:
    @pytest.fixture
    def client(self):
        from httpx import ASGITransport, AsyncClient
        from server import app

        transport = ASGITransport(app=app)
        return AsyncClient(transport=transport, base_url="http://test")

    async def test_get_empty(self, client):
        resp = await client.get("/browser-context")
        assert resp.status_code == 200
        data = resp.json()
        assert data["available"] is False
        assert data["context"] is None

    async def test_post_valid(self, client):
        resp = await client.post("/browser-context", json={
            "url": "https://example.com",
            "title": "Example Page",
            "content": "Page body here",
            "selected_text": "body",
        })
        assert resp.status_code == 200
        assert resp.json()["status"] == "ok"

    async def test_post_missing_url(self, client):
        resp = await client.post("/browser-context", json={
            "title": "No URL",
            "content": "body",
        })
        # Pydantic validation returns 422 for missing required field
        assert resp.status_code == 422

    async def test_post_updates_timestamp(self, client):
        """POST twice — GET should reflect the latest push's timestamp."""
        await client.post("/browser-context", json={
            "url": "https://first.com",
            "title": "First",
            "content": "first body",
            "selected_text": "",
        })
        resp1 = await client.get("/browser-context")
        ts1 = resp1.json()["context"]["timestamp"]

        await client.post("/browser-context", json={
            "url": "https://second.com",
            "title": "Second",
            "content": "second body",
            "selected_text": "",
        })
        resp2 = await client.get("/browser-context")
        ts2 = resp2.json()["context"]["timestamp"]

        assert ts2 >= ts1
        assert resp2.json()["context"]["url"] == "https://second.com"

    async def test_get_after_post(self, client):
        await client.post("/browser-context", json={
            "url": "https://example.com/page",
            "title": "My Page",
            "content": "Full page content here",
            "selected_text": "",
        })
        resp = await client.get("/browser-context")
        assert resp.status_code == 200
        data = resp.json()
        assert data["available"] is True
        assert data["context"]["url"] == "https://example.com/page"
        assert data["context"]["title"] == "My Page"
        assert data["context"]["content"] == "Full page content here"


# ---------------------------------------------------------------------------
# build_message with browser context
# ---------------------------------------------------------------------------
class TestBuildMessageWithBrowserContext:
    def test_no_browser_context(self):
        from server import build_message

        result = build_message("Summarize", "", "generate")
        assert "Browser page content" not in result

    def test_with_browser_context(self):
        from server import build_message

        result = build_message(
            "Summarize this page", "", "generate",
            browser_context="This is the full page text from Chrome.",
        )
        assert "Browser page content" in result
        assert "This is the full page text from Chrome." in result
        assert "Summarize this page" in result

    def test_browser_context_with_selected_context(self):
        from server import build_message

        result = build_message(
            "Explain this", "selected text", "generate",
            browser_context="Full page body",
        )
        assert "selected text" in result
        assert "Full page body" in result
        assert "Browser page content" in result
