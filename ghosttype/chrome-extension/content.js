/**
 * GhostType content script — extracts page content for @browser context.
 *
 * Declared in manifest.json as a persistent content script so it's available
 * on every page. Also guards against duplicate registration when the background
 * service worker injects it manually as a fallback.
 */

if (!window.__ghosttype_content_loaded) {
  window.__ghosttype_content_loaded = true;

  function extractPageContent() {
    const clone = document.cloneNode(true);

    // Remove non-content elements
    const removeSelectors = [
      "script", "style", "noscript", "nav", "header", "footer",
      "aside", "iframe", "[role='navigation']", "[role='banner']",
      "[role='contentinfo']", "[aria-hidden='true']",
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
      .replace(/\n{3,}/g, "\n\n")  // collapse excessive newlines
      .trim();

    const MAX_CHARS = 50_000;
    const truncated = text.length > MAX_CHARS
      ? text.slice(0, MAX_CHARS) + "\n[...truncated]"
      : text;

    const selectedText = window.getSelection()?.toString()?.trim() || "";

    return {
      url: window.location.href,
      title: document.title,
      content: truncated,
      selected_text: selectedText,
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
    }
    return true; // keep channel open for async response
  });
}
