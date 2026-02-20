"""GhostType AgentCore Backend — FastAPI with synchronous /invocations endpoint."""

import base64
import logging
import sys
import time

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse

from agent import ModelConfig, create_agent
from config import config

# ---------------------------------------------------------------------------
# Logging setup
# ---------------------------------------------------------------------------
logging.basicConfig(
    level=getattr(logging, config.log_level.upper(), logging.DEBUG),
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    stream=sys.stderr,
)
logger = logging.getLogger("ghosttype.agentcore")

# ---------------------------------------------------------------------------
# App
# ---------------------------------------------------------------------------
app = FastAPI(title="GhostType AgentCore Backend", version="0.1.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)


# ---------------------------------------------------------------------------
# Health / Ping endpoint (required by AgentCore)
# ---------------------------------------------------------------------------
@app.get("/ping")
async def ping():
    """Health check endpoint (AgentCore convention)."""
    return {"status": "ok"}


@app.get("/health")
async def health():
    """Health check endpoint (standard convention)."""
    return {
        "status": "ok",
        "provider": config.model_provider,
        "model": config.model_id,
    }


# ---------------------------------------------------------------------------
# Message building (reused from local backend logic)
# ---------------------------------------------------------------------------
def classify_mode_type(mode: str, context: str, prompt: str) -> str:
    """Classify the request as 'draft' or 'chat' mode type."""
    if mode in ("rewrite", "fix", "translate"):
        return "draft"
    if context:
        return "draft"
    return "chat"


def build_message(prompt: str, context: str, mode: str) -> str:
    """Build the user text message based on mode and context."""
    if mode == "rewrite" and context:
        return f"Rewrite the following text:\n\n{context}\n\nInstructions: {prompt}"
    elif mode == "fix" and context:
        return f"Fix grammar and spelling in the following text:\n\n{context}"
    elif mode == "translate" and context:
        return f"Translate the following text. {prompt}\n\n{context}"
    elif context:
        return (
            f'Context (selected text from user\'s application):\n"""\n{context}\n"""\n\n'
            f"Task: {prompt}"
        )
    else:
        return prompt


def build_multimodal_message(text: str, screenshot_b64: str | None) -> str | list:
    """Build the agent message, optionally including a screenshot image."""
    if not screenshot_b64:
        return text

    try:
        image_bytes = base64.b64decode(screenshot_b64)
    except Exception:
        logger.warning("Failed to decode screenshot base64, sending text only")
        return text

    return [
        {
            "image": {
                "format": "jpeg",
                "source": {"bytes": image_bytes},
            }
        },
        {"text": text},
    ]


# ---------------------------------------------------------------------------
# Invocations endpoint (synchronous — full response at once)
# ---------------------------------------------------------------------------
@app.post("/invocations")
async def invocations(request: Request):
    """Synchronous generation endpoint for AgentCore.

    Request body:
        {"prompt": "...", "context": "...", "mode": "generate|rewrite|fix|translate",
         "config": {"provider": "bedrock", "model_id": "...", "aws_profile": "...", "aws_region": "..."}}

    Response:
        {"type": "done", "content": "full response text"}
        {"type": "error", "content": "error message"}
    """
    try:
        body = await request.json()
    except Exception as e:
        return JSONResponse(
            status_code=400,
            content={"type": "error", "content": f"Invalid JSON: {e}"},
        )

    prompt = body.get("prompt", "")
    context = body.get("context", "")
    mode = body.get("mode", "generate")
    screenshot_b64 = body.get("screenshot")

    if not prompt and mode == "generate":
        return JSONResponse(
            status_code=400,
            content={"type": "error", "content": "Empty prompt"},
        )

    # Extract per-request model config
    request_config = body.get("config")
    model_config = ModelConfig.from_request(request_config)

    # Determine mode type
    mode_type = body.get("mode_type") or classify_mode_type(mode, context, prompt)

    text_message = build_message(prompt, context, mode)
    user_message = build_multimodal_message(text_message, screenshot_b64)

    logger.info(
        "Generating: mode=%s, mode_type=%s, provider=%s, model=%s, prompt_len=%d, context_len=%d",
        mode, mode_type, model_config.effective_provider(), model_config.effective_model_id(),
        len(prompt), len(context),
    )

    gen_start = time.monotonic()

    try:
        agent = create_agent(model_config=model_config, mode_type=mode_type)
        result = agent(user_message)
        full_response = str(result)
        elapsed = time.monotonic() - gen_start

        logger.info(
            "Generation complete: %.3fs, response_len=%d",
            elapsed, len(full_response),
        )

        return {"type": "done", "content": full_response}

    except Exception as e:
        elapsed = time.monotonic() - gen_start
        logger.error(
            "Generation error after %.3fs: %s: %s",
            elapsed, type(e).__name__, e,
            exc_info=True,
        )
        return JSONResponse(
            status_code=500,
            content={"type": "error", "content": _friendly_error(e)},
        )


def _friendly_error(e: Exception) -> str:
    """Convert exceptions into user-friendly error messages."""
    msg = str(e)
    etype = type(e).__name__

    if "rate" in msg.lower() and "limit" in msg.lower():
        return "Rate limit exceeded. Please wait a moment and try again."
    if "authentication" in msg.lower() or "credentials" in msg.lower():
        return "Authentication error. Check your AWS credentials."
    if "timeout" in msg.lower():
        return "Request timed out. The model may be overloaded — try again."
    if "ExpiredTokenException" in msg or "ExpiredToken" in msg:
        return "AWS credentials expired. Run tokenmaster to refresh."

    return f"{etype}: {msg}"


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------
if __name__ == "__main__":
    import uvicorn

    logger.info(
        "Starting GhostType AgentCore backend: provider=%s, model=%s, host=%s:%d",
        config.model_provider, config.model_id, config.host, config.port,
    )

    uvicorn.run(
        "server:app",
        host=config.host,
        port=config.port,
        reload=True,
        log_level=config.log_level.lower(),
    )
