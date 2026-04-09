"""Tests for the browser context HTTP handler in stdio_server.py."""

import json
import threading
import time
from http.client import HTTPConnection

import pytest

from stdio_server import _start_http_server, _browser_store
from browser_context import BrowserContext


@pytest.fixture(scope="module")
def http_server():
    """Start the HTTP server on a random-ish port for testing."""
    port = 18421
    _start_http_server(port=port)
    time.sleep(0.2)  # Give thread time to bind
    yield port


@pytest.fixture(autouse=True)
def clear_store():
    """Reset the browser store before each test."""
    _browser_store._context = None
    yield


class TestBrowserContextHTTP:
    def test_health_endpoint(self, http_server):
        conn = HTTPConnection("127.0.0.1", http_server)
        conn.request("GET", "/health")
        resp = conn.getresponse()
        assert resp.status == 200
        data = json.loads(resp.read())
        assert data["status"] == "ok"
        conn.close()

    def test_get_empty_context(self, http_server):
        conn = HTTPConnection("127.0.0.1", http_server)
        conn.request("GET", "/browser-context")
        resp = conn.getresponse()
        assert resp.status == 200
        data = json.loads(resp.read())
        assert data["available"] is False
        conn.close()

    def test_post_and_get_context(self, http_server):
        conn = HTTPConnection("127.0.0.1", http_server)

        # POST context
        body = json.dumps({
            "url": "https://example.com",
            "title": "Example",
            "content": "Page body",
            "selected_text": "body",
        }).encode()
        conn.request("POST", "/browser-context", body=body,
                     headers={"Content-Type": "application/json"})
        resp = conn.getresponse()
        assert resp.status == 200
        data = json.loads(resp.read())
        assert data["status"] == "ok"

        # GET context
        conn.request("GET", "/browser-context")
        resp = conn.getresponse()
        assert resp.status == 200
        data = json.loads(resp.read())
        assert data["available"] is True
        assert data["context"]["url"] == "https://example.com"
        assert data["context"]["title"] == "Example"
        conn.close()

    def test_post_missing_url_returns_400(self, http_server):
        conn = HTTPConnection("127.0.0.1", http_server)
        body = json.dumps({"title": "No URL"}).encode()
        conn.request("POST", "/browser-context", body=body,
                     headers={"Content-Type": "application/json"})
        resp = conn.getresponse()
        assert resp.status == 400
        conn.close()

    def test_post_invalid_json_returns_400(self, http_server):
        conn = HTTPConnection("127.0.0.1", http_server)
        conn.request("POST", "/browser-context", body=b"not json",
                     headers={"Content-Type": "application/json"})
        resp = conn.getresponse()
        assert resp.status == 400
        conn.close()

    def test_unknown_path_returns_404(self, http_server):
        conn = HTTPConnection("127.0.0.1", http_server)
        conn.request("GET", "/nonexistent")
        resp = conn.getresponse()
        assert resp.status == 404
        conn.close()

    def test_cors_headers_present(self, http_server):
        conn = HTTPConnection("127.0.0.1", http_server)
        conn.request("GET", "/health")
        resp = conn.getresponse()
        assert resp.getheader("Access-Control-Allow-Origin") == "*"
        conn.close()
