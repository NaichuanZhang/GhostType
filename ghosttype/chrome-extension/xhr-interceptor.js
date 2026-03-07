/**
 * GhostType XHR/Fetch interceptor — captures JSON API responses.
 *
 * Runs in the MAIN world (page context) at document_start so it can
 * monkey-patch `fetch` and `XMLHttpRequest` before page scripts execute.
 *
 * Captured responses are relayed to the content script via postMessage.
 *
 * Security:
 *   - Only captures 2xx responses with JSON content-type
 *   - Skips auth/login/token/payment-related URLs
 *   - Redacts sensitive keys (passwords, tokens, secrets, etc.)
 *   - Per-response body limit: 30K chars
 */

if (!window.__ghosttype_xhr_interceptor) {
  window.__ghosttype_xhr_interceptor = true;

  const MAX_BODY_CHARS = 30_000;

  // ─── URL filtering ──────────────────────────────────────────────────

  const SENSITIVE_URL_PATTERNS = [
    /\/auth\b/i,
    /\/login\b/i,
    /\/logout\b/i,
    /\/token\b/i,
    /\/oauth/i,
    /\/session/i,
    /\/password/i,
    /\/payment/i,
    /\/checkout/i,
    /stripe\.com/i,
    /plaid\.com/i,
    /paypal\.com/i,
    /braintree/i,
  ];

  function isSensitiveUrl(url) {
    try {
      const str = typeof url === "string" ? url : url.toString();
      return SENSITIVE_URL_PATTERNS.some((re) => re.test(str));
    } catch {
      return true; // err on the side of caution
    }
  }

  // ─── Response filtering ─────────────────────────────────────────────

  function isJsonContentType(contentType) {
    if (!contentType) return false;
    return (
      contentType.includes("application/json") || contentType.includes("+json")
    );
  }

  function isSuccessStatus(status) {
    return status >= 200 && status < 300;
  }

  // ─── Sensitive key redaction ────────────────────────────────────────

  const SENSITIVE_KEYS = new Set([
    "password",
    "passwd",
    "pass",
    "token",
    "access_token",
    "refresh_token",
    "id_token",
    "secret",
    "client_secret",
    "api_key",
    "apikey",
    "api-key",
    "authorization",
    "auth",
    "cookie",
    "set-cookie",
    "session_id",
    "sessionid",
    "csrf",
    "csrf_token",
    "xsrf",
    "credit_card",
    "card_number",
    "cvv",
    "cvc",
    "ssn",
    "social_security",
    "private_key",
    "signing_key",
  ]);

  function redactSensitive(obj) {
    if (obj === null || obj === undefined) return obj;
    if (Array.isArray(obj)) return obj.map(redactSensitive);
    if (typeof obj !== "object") return obj;

    const result = {};
    for (const [key, value] of Object.entries(obj)) {
      if (SENSITIVE_KEYS.has(key.toLowerCase())) {
        result[key] = "[REDACTED]";
      } else {
        result[key] = redactSensitive(value);
      }
    }
    return result;
  }

  // ─── Capture relay ──────────────────────────────────────────────────

  function relayCapture(url, data) {
    try {
      const redacted = redactSensitive(data);
      let body = JSON.stringify(redacted);
      if (body.length > MAX_BODY_CHARS) {
        body = body.slice(0, MAX_BODY_CHARS);
      }
      // Re-parse to get a truncated-but-valid-ish object for the content script
      let parsedBody;
      try {
        parsedBody = JSON.parse(body);
      } catch {
        // Truncation broke JSON — send raw truncated string
        parsedBody = body;
      }

      window.postMessage(
        {
          source: "ghosttype-xhr",
          type: "xhr-capture",
          payload: {
            url: typeof url === "string" ? url : url.toString(),
            data: parsedBody,
            timestamp: Date.now(),
          },
        },
        "*",
      );
    } catch {
      // Silently ignore relay errors
    }
  }

  // ─── Patch fetch ────────────────────────────────────────────────────

  const originalFetch = window.fetch;

  window.fetch = function (...args) {
    const request = args[0];
    const url =
      request instanceof Request
        ? request.url
        : typeof request === "string"
          ? request
          : (request?.toString?.() ?? "");

    return originalFetch.apply(this, args).then((response) => {
      try {
        if (
          !isSensitiveUrl(url) &&
          isSuccessStatus(response.status) &&
          isJsonContentType(response.headers.get("content-type"))
        ) {
          // Clone so the page's consumption is not affected
          response
            .clone()
            .json()
            .then((data) => {
              relayCapture(url, data);
            })
            .catch(() => {}); // ignore parse errors
        }
      } catch {
        // Don't break the page
      }
      return response;
    });
  };

  // ─── Patch XMLHttpRequest ───────────────────────────────────────────

  const originalOpen = XMLHttpRequest.prototype.open;
  const originalSend = XMLHttpRequest.prototype.send;

  XMLHttpRequest.prototype.open = function (method, url, ...rest) {
    this.__ghosttype_url = url;
    return originalOpen.call(this, method, url, ...rest);
  };

  XMLHttpRequest.prototype.send = function (...args) {
    this.addEventListener("load", function () {
      try {
        const url = this.__ghosttype_url;
        if (url && !isSensitiveUrl(url) && isSuccessStatus(this.status)) {
          const ct = this.getResponseHeader("content-type") || "";
          if (isJsonContentType(ct)) {
            const data = JSON.parse(this.responseText);
            relayCapture(url, data);
          }
        }
      } catch {
        // Don't break the page
      }
    });
    return originalSend.apply(this, args);
  };
}
