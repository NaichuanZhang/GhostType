"""Shared message building utilities for the GhostType backend.

Constructs user messages from prompt, context, mode, and optional
browser context / screenshot data.
"""

from __future__ import annotations

import base64
import logging

logger = logging.getLogger("ghosttype.message_builder")


def build_message(prompt: str, context: str, mode: str, browser_context: str = "") -> str:
    """Build the user text message based on mode and context."""
    if mode == "rewrite" and context:
        base = f"Rewrite the following text:\n\n{context}\n\nInstructions: {prompt}"
    elif mode == "fix" and context:
        base = f"Fix grammar and spelling in the following text:\n\n{context}"
    elif mode == "translate" and context:
        base = f"Translate the following text. {prompt}\n\n{context}"
    elif context:
        base = (
            f'Context (selected text from user\'s application):\n"""\n{context}\n"""\n\n'
            f"Task: {prompt}"
        )
    else:
        base = prompt

    if browser_context:
        base += f'\n\nBrowser page content:\n"""\n{browser_context}\n"""'

    return base


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
        {"image": {"format": "jpeg", "source": {"bytes": image_bytes}}},
        {"text": text},
    ]


def friendly_error(exc: Exception) -> str:
    """Convert provider exceptions to user-readable messages."""
    msg = str(exc)
    if "ExpiredTokenException" in msg or "ExpiredToken" in msg:
        return "AWS credentials expired. Run 'ada credentials update' or refresh your AWS session."
    if "AccessDeniedException" in msg:
        return "Access denied. Check your AWS profile and model permissions."
    if "ThrottlingException" in msg:
        return "Request throttled by the model provider. Try again in a few seconds."
    if "ModelNotReadyException" in msg:
        return "Model is not ready. Please try again shortly."
    if "ValidationException" in msg and "model" in msg.lower():
        return f"Invalid model configuration: {msg}"
    if "ConnectTimeoutError" in msg or "ConnectionError" in msg:
        return "Cannot connect to the model provider. Check your network and AWS region."
    return f"Generation failed: {msg}"
