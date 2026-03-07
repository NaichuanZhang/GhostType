const captureBtn = document.getElementById("capture");
const statusEl = document.getElementById("status");
const xhrListEl = document.getElementById("xhr-list");

const STALE_THRESHOLD_MS = 60_000;
const MAX_XHR_DISPLAY = 5;

function setStatus(text, type = "") {
  statusEl.textContent = text;
  statusEl.className = type;
}

function formatAgo(timestampMs) {
  const ago = Math.round((Date.now() - timestampMs) / 1000);
  if (ago < 60) return `${ago}s ago`;
  return `${Math.round(ago / 60)}m ago`;
}

function renderXhrUrls(urls) {
  if (!urls || urls.length === 0) {
    xhrListEl.style.display = "none";
    return;
  }
  const display = urls.slice(0, MAX_XHR_DISPLAY);
  const pathnames = display.map((u) => {
    try {
      return new URL(u).pathname;
    } catch {
      return u;
    }
  });
  const label = `<div class="xhr-label">API calls (${urls.length}):</div>`;
  const items = pathnames
    .map((p) => `<div class="xhr-url">${p}</div>`)
    .join("");
  xhrListEl.innerHTML = label + items;
  xhrListEl.style.display = "block";
}

// Show last auto-captured status on popup open
chrome.runtime.sendMessage({ action: "getStatus" }, (response) => {
  if (chrome.runtime.lastError || !response) {
    setStatus("Waiting for tab...");
    return;
  }
  if (response.error) {
    setStatus(response.error, "error");
  } else if (response.title && response.timestamp) {
    const isStale = Date.now() - response.timestamp > STALE_THRESHOLD_MS;
    const agoText = formatAgo(response.timestamp);
    if (isStale) {
      setStatus(`\u26a0 Stale: "${response.title}" (${agoText})`, "warning");
    } else {
      setStatus(`Auto-captured: "${response.title}" (${agoText})`, "success");
    }
    renderXhrUrls(response.xhrUrls);
  } else {
    setStatus("Waiting for tab...");
  }
});

captureBtn.addEventListener("click", async () => {
  captureBtn.disabled = true;
  setStatus("Capturing...");

  chrome.runtime.sendMessage({ action: "captureContext" }, (response) => {
    captureBtn.disabled = false;

    if (chrome.runtime.lastError) {
      setStatus(chrome.runtime.lastError.message, "error");
      return;
    }

    if (response?.ok) {
      const title = response.title || "page";
      setStatus(`Sent: "${title}"`, "success");
      renderXhrUrls(response.xhrUrls);
    } else {
      setStatus(response?.error || "Unknown error", "error");
    }
  });
});
