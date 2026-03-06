const captureBtn = document.getElementById("capture");
const statusEl = document.getElementById("status");

function setStatus(text, type = "") {
  statusEl.textContent = text;
  statusEl.className = type;
}

// Show last auto-captured status on popup open
chrome.runtime.sendMessage({ action: "getStatus" }, (response) => {
  if (chrome.runtime.lastError || !response) {
    setStatus("Waiting for tab...");
    return;
  }
  if (response.error) {
    setStatus(response.error, "error");
  } else if (response.title) {
    const ago = Math.round((Date.now() - response.timestamp) / 1000);
    const agoText = ago < 60 ? `${ago}s ago` : `${Math.round(ago / 60)}m ago`;
    setStatus(`Auto-captured: "${response.title}" (${agoText})`, "success");
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
    } else {
      setStatus(response?.error || "Unknown error", "error");
    }
  });
});
