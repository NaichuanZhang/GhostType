"""Browser context storage — receives page content from the Chrome extension."""

import threading
import time
from dataclasses import dataclass


@dataclass(frozen=True)
class BrowserContext:
    """Immutable snapshot of the active browser tab's content."""

    url: str
    title: str
    content: str
    selected_text: str
    timestamp: float
    xhr_data: tuple[dict, ...] = ()

    def to_dict(self) -> dict:
        return {
            "url": self.url,
            "title": self.title,
            "content": self.content,
            "selected_text": self.selected_text,
            "timestamp": self.timestamp,
            "xhr_data": list(self.xhr_data),
        }


class BrowserContextStore:
    """Thread-safe in-memory store for the latest browser context.

    Only the most recent page is stored — the extension pushes on every
    capture, overwriting the previous value.
    """

    def __init__(self):
        self._lock = threading.Lock()
        self._context: BrowserContext | None = None

    def set(self, context: BrowserContext) -> None:
        with self._lock:
            self._context = context

    def get(self) -> BrowserContext | None:
        with self._lock:
            return self._context

    def clear(self) -> None:
        with self._lock:
            self._context = None

    def to_dict(self) -> dict:
        ctx = self.get()
        if ctx is None:
            return {"available": False, "context": None}
        return {"available": True, "context": ctx.to_dict()}
