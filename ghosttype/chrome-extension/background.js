/**
 * GhostType background service worker — coordinates content extraction
 * and pushes page context to the backend.
 *
 * Auto-captures on tab switch, page load, SPA navigation, and periodic
 * alarm so @browser context is always fresh even when the MV3 service
 * worker is killed and restarted.
 */

const BACKEND_URL = "http://127.0.0.1:8420/browser-context";

// Retry config for backend POST
const MAX_RETRIES = 3;
const INITIAL_BACKOFF_MS = 1000;

// Debounce state — skip if same tab captured within 2 seconds
let lastCapture = { tabId: null, time: 0 };

// Last known status for the popup to display
let lastStatus = {
  url: null,
  title: null,
  timestamp: null,
  error: null,
  xhrUrls: [],
};

// ─── Periodic refresh via alarm ──────────────────────────────────────

chrome.alarms.create("ghosttype-refresh", { periodInMinutes: 25 / 60 });

chrome.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name === "ghosttype-refresh") {
    chrome.tabs.query({ active: true, currentWindow: true }, (tabs) => {
      if (tabs[0]?.id) autoCaptureTab(tabs[0].id);
    });
  }
});

// ─── SPA navigation detection ────────────────────────────────────────

chrome.webNavigation.onHistoryStateUpdated.addListener((details) => {
  if (details.frameId === 0) {
    console.log(
      `[GhostType] onHistoryStateUpdated tabId=${details.tabId} url=${details.url}`,
    );
    autoCaptureTab(details.tabId);
  }
});

// ─── Retry helper ────────────────────────────────────────────────────

/**
 * POST payload to backend with exponential backoff retry.
 * Returns the Response on success, or throws on exhausted retries.
 */
async function postWithRetry(payload) {
  let lastError;
  for (let attempt = 0; attempt < MAX_RETRIES; attempt++) {
    try {
      const res = await fetch(BACKEND_URL, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
      });
      if (res.ok) return res;

      // Non-retryable client errors (4xx)
      if (res.status >= 400 && res.status < 500) {
        const text = await res.text();
        throw new Error(`Backend returned ${res.status}: ${text}`);
      }

      // Server error (5xx) — retry
      lastError = new Error(`Backend returned ${res.status}`);
    } catch (err) {
      lastError = err;
    }

    if (attempt < MAX_RETRIES - 1) {
      const delay = INITIAL_BACKOFF_MS * Math.pow(2, attempt);
      console.log(
        `[GhostType] POST retry ${attempt + 1}/${MAX_RETRIES} in ${delay}ms`,
      );
      await new Promise((r) => setTimeout(r, delay));
    }
  }
  throw lastError;
}

// ─── Core capture logic ──────────────────────────────────────────────

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
    response = await chrome.tabs.sendMessage(tabId, {
      action: "extractContent",
    });
    console.log(
      `[GhostType] sendMessage succeeded (manifest path) tabId=${tabId}`,
    );
  } catch {
    // Fallback: inject manually (page was open before extension loaded)
    console.log(
      `[GhostType] sendMessage failed, trying executeScript fallback tabId=${tabId}`,
    );
    try {
      await chrome.scripting.executeScript({
        target: { tabId },
        files: ["content.js"],
      });
      response = await chrome.tabs.sendMessage(tabId, {
        action: "extractContent",
      });
      console.log(
        `[GhostType] executeScript fallback succeeded tabId=${tabId}`,
      );
    } catch (err) {
      console.warn(
        `[GhostType] pushContext failed entirely tabId=${tabId}:`,
        err.message,
      );
      return { ok: false, error: err.message };
    }
  }

  if (response?.error) {
    console.warn(`[GhostType] content script returned error:`, response.error);
    return { ok: false, error: response.error };
  }

  // Push to backend with retry
  try {
    await postWithRetry(response);
    console.log(`[GhostType] backend POST success for ${response.url}`);

    // Clear XHR buffer in content script to prevent resending stale data
    try {
      await chrome.tabs.sendMessage(tabId, { action: "clearXhrData" });
    } catch {
      // Content script may not be loaded yet — safe to ignore
    }

    const xhrUrls = (response.xhr_data || []).map((e) => e.url);
    return { ok: true, title: response.title, url: response.url, xhrUrls };
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
        timestamp: Date.now(),
        error: null,
        xhrUrls: result.xhrUrls || [],
      };
    } else {
      lastStatus = {
        ...lastStatus,
        error: result.error,
        timestamp: Date.now(),
      };
    }
  } catch (err) {
    lastStatus = { ...lastStatus, error: err.message, timestamp: Date.now() };
  }
}

// ─── Event listeners ─────────────────────────────────────────────────

// Auto-capture when the user switches to a different tab
chrome.tabs.onActivated.addListener((activeInfo) => {
  console.log(`[GhostType] onActivated tabId=${activeInfo.tabId}`);
  autoCaptureTab(activeInfo.tabId);
});

// Auto-capture when a page finishes loading (main frame only)
chrome.webNavigation.onCompleted.addListener((details) => {
  if (details.frameId === 0) {
    console.log(
      `[GhostType] onCompleted tabId=${details.tabId} url=${details.url}`,
    );
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
            xhrUrls: result.xhrUrls || [],
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
