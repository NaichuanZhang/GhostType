/**
 * GhostType background service worker — coordinates content extraction
 * and pushes page context to the backend.
 *
 * Auto-captures on tab switch and page load so @browser context is always fresh.
 */

const BACKEND_URL = "http://127.0.0.1:8420/browser-context";

// Debounce state — skip if same tab captured within 2 seconds
let lastCapture = { tabId: null, time: 0 };

// Last known status for the popup to display
let lastStatus = { url: null, title: null, timestamp: null, error: null };

/**
 * Extract page content and POST to backend.
 *
 * Tries sendMessage first (content script loaded via manifest). Falls back to
 * executeScript + sendMessage for tabs that were open before the extension was
 * installed or reloaded.
 *
 * Returns { ok: true, title, url } on success or { ok: false, error } on failure.
 */
async function pushContext(tabId) {
  console.log(`[GhostType] pushContext tabId=${tabId}`);

  let response;
  try {
    // Content script should already be loaded (declared in manifest)
    response = await chrome.tabs.sendMessage(tabId, { action: "extractContent" });
    console.log(`[GhostType] sendMessage succeeded (manifest path) tabId=${tabId}`);
  } catch {
    // Fallback: inject manually (page was open before extension loaded)
    console.log(`[GhostType] sendMessage failed, trying executeScript fallback tabId=${tabId}`);
    try {
      await chrome.scripting.executeScript({
        target: { tabId },
        files: ["content.js"],
      });
      response = await chrome.tabs.sendMessage(tabId, { action: "extractContent" });
      console.log(`[GhostType] executeScript fallback succeeded tabId=${tabId}`);
    } catch (err) {
      console.warn(`[GhostType] pushContext failed entirely tabId=${tabId}:`, err.message);
      return { ok: false, error: err.message };
    }
  }

  if (response?.error) {
    console.warn(`[GhostType] content script returned error:`, response.error);
    return { ok: false, error: response.error };
  }

  // Push to backend
  try {
    const res = await fetch(BACKEND_URL, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(response),
    });

    if (!res.ok) {
      const text = await res.text();
      console.warn(`[GhostType] backend POST failed: ${res.status} ${text}`);
      return { ok: false, error: `Backend returned ${res.status}: ${text}` };
    }

    console.log(`[GhostType] backend POST success for ${response.url}`);
    return { ok: true, title: response.title, url: response.url };
  } catch (err) {
    console.warn(`[GhostType] backend POST error:`, err.message);
    return { ok: false, error: err.message };
  }
}

/**
 * Auto-capture with debounce — skips if same tab was captured < 2s ago.
 * Failures are silent (logged but don't surface to the user).
 */
async function autoCaptureTab(tabId) {
  const now = Date.now();
  if (lastCapture.tabId === tabId && now - lastCapture.time < 2000) {
    console.log(`[GhostType] autoCaptureTab debounced tabId=${tabId}`);
    return; // debounce
  }

  console.log(`[GhostType] autoCaptureTab tabId=${tabId}`);
  lastCapture = { tabId, time: now };

  try {
    const result = await pushContext(tabId);
    if (result.ok) {
      lastStatus = {
        url: result.url,
        title: result.title,
        timestamp: now,
        error: null,
      };
    } else {
      lastStatus = { ...lastStatus, error: result.error, timestamp: now };
    }
  } catch (err) {
    lastStatus = { ...lastStatus, error: err.message, timestamp: now };
  }
}

// Auto-capture when the user switches to a different tab
chrome.tabs.onActivated.addListener((activeInfo) => {
  console.log(`[GhostType] onActivated tabId=${activeInfo.tabId}`);
  autoCaptureTab(activeInfo.tabId);
});

// Auto-capture when a page finishes loading (main frame only)
chrome.webNavigation.onCompleted.addListener((details) => {
  if (details.frameId === 0) {
    console.log(`[GhostType] onCompleted tabId=${details.tabId} url=${details.url}`);
    autoCaptureTab(details.tabId);
  }
});

// Listen for messages from the popup
chrome.runtime.onMessage.addListener((msg, sender, sendResponse) => {
  if (msg.action === "captureContext") {
    chrome.tabs.query({ active: true, currentWindow: true }, async (tabs) => {
      if (!tabs[0]?.id) {
        sendResponse({ ok: false, error: "No active tab found" });
        return;
      }
      try {
        // Manual capture bypasses debounce
        lastCapture = { tabId: null, time: 0 };
        const result = await pushContext(tabs[0].id);
        if (result.ok) {
          lastStatus = {
            url: result.url,
            title: result.title,
            timestamp: Date.now(),
            error: null,
          };
        }
        sendResponse(result);
      } catch (err) {
        sendResponse({ ok: false, error: err.message });
      }
    });
    return true; // async response
  }

  if (msg.action === "getStatus") {
    sendResponse(lastStatus);
    return false;
  }
});
