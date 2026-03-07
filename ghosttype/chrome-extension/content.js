/**
 * GhostType content script — extracts page content for @browser context.
 *
 * Declared in manifest.json as a persistent content script so it's available
 * on every page. Also guards against duplicate registration when the background
 * service worker injects it manually as a fallback.
 */

if (!window.__ghosttype_content_loaded) {
  window.__ghosttype_content_loaded = true;

  // ─── XHR capture buffer ───────────────────────────────────────────
  const MAX_XHR_ENTRIES = 20;
  const MAX_XHR_TOTAL_CHARS = 30_000;
  let xhrCaptures = [];
  let xhrTotalChars = 0;

  // Listen for captures from the MAIN world xhr-interceptor
  window.addEventListener("message", (event) => {
    if (event.source !== window) return;
    if (event.data?.source !== "ghosttype-xhr") return;
    if (event.data?.type !== "xhr-capture") return;

    const payload = event.data.payload;
    if (!payload?.url) return;

    const entrySize = JSON.stringify(payload).length;

    // FIFO eviction: drop oldest entries if over limits
    while (
      xhrCaptures.length >= MAX_XHR_ENTRIES ||
      (xhrTotalChars + entrySize > MAX_XHR_TOTAL_CHARS &&
        xhrCaptures.length > 0)
    ) {
      const removed = xhrCaptures.shift();
      xhrTotalChars -= JSON.stringify(removed).length;
    }

    xhrCaptures.push(payload);
    xhrTotalChars += entrySize;
  });

  // Reset buffer on SPA navigation
  function resetXhrBuffer() {
    xhrCaptures = [];
    xhrTotalChars = 0;
  }

  window.addEventListener("popstate", resetXhrBuffer);
  window.addEventListener("hashchange", resetXhrBuffer);

  function extractPageContent() {
    const clone = document.cloneNode(true);

    // Remove non-content elements
    const removeSelectors = [
      "script",
      "style",
      "noscript",
      "nav",
      "header",
      "footer",
      "aside",
      "iframe",
      "[role='navigation']",
      "[role='banner']",
      "[role='contentinfo']",
      "[aria-hidden='true']",
    ];
    for (const sel of removeSelectors) {
      for (const el of clone.querySelectorAll(sel)) {
        el.remove();
      }
    }

    // Prefer semantic content containers
    const contentEl =
      clone.querySelector("main") ||
      clone.querySelector("article") ||
      clone.querySelector("[role='main']") ||
      clone.body;

    const text = (contentEl?.innerText || contentEl?.textContent || "")
      .replace(/\n{3,}/g, "\n\n") // collapse excessive newlines
      .trim();

    const MAX_CHARS = 50_000;
    const truncated =
      text.length > MAX_CHARS
        ? text.slice(0, MAX_CHARS) + "\n[...truncated]"
        : text;

    const selectedText = window.getSelection()?.toString()?.trim() || "";

    return {
      url: window.location.href,
      title: document.title,
      content: truncated,
      selected_text: selectedText,
      xhr_data: xhrCaptures.length > 0 ? [...xhrCaptures] : undefined,
    };
  }

  // Respond to messages from the background service worker
  chrome.runtime.onMessage.addListener((msg, _sender, sendResponse) => {
    if (msg.action === "extractContent") {
      try {
        sendResponse(extractPageContent());
      } catch (err) {
        sendResponse({ error: err.message });
      }
    } else if (msg.action === "clearXhrData") {
      resetXhrBuffer();
      sendResponse({ ok: true });
    }
    return true; // keep channel open for async response
  });
}
