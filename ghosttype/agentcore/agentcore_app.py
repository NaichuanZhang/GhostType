"""GhostType AgentCore SDK entrypoint.

This module provides the entrypoint for Bedrock AgentCore's managed runtime.
It receives payloads from the AgentCore invoke API and delegates to the
Strands Agent for generation.
"""

import logging
import sys
import time

from agent import ModelConfig, create_agent

logging.basicConfig(
    level=logging.DEBUG,
    format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    stream=sys.stderr,
)
logger = logging.getLogger("ghosttype.agentcore_app")

try:
    from bedrock_agentcore.runtime import BedrockAgentCoreApp
    app = BedrockAgentCoreApp()
except ImportError:
    logger.warning("bedrock_agentcore not installed — SDK entrypoint unavailable")
    app = None


def _classify_mode_type(mode: str, context: str) -> str:
    if mode in ("rewrite", "fix", "translate"):
        return "draft"
    if context:
        return "draft"
    return "chat"


def _build_message(prompt: str, context: str, mode: str) -> str:
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


if app is not None:
    @app.entrypoint
    def invoke(payload: dict) -> dict:
        """AgentCore invoke entrypoint.

        Args:
            payload: Dict with keys: prompt, context, mode, config.

        Returns:
            {"result": "generated text"}
        """
        prompt = payload.get("prompt", "")
        context = payload.get("context", "")
        mode = payload.get("mode", "generate")

        if not prompt and mode == "generate":
            return {"error": "Empty prompt"}

        model_config = ModelConfig.from_request(payload.get("config"))
        mode_type = payload.get("mode_type") or _classify_mode_type(mode, context)
        user_message = _build_message(prompt, context, mode)

        logger.info(
            "AgentCore invoke: mode=%s, mode_type=%s, prompt_len=%d",
            mode, mode_type, len(prompt),
        )

        gen_start = time.monotonic()
        try:
            agent = create_agent(model_config=model_config, mode_type=mode_type)
            result = agent(user_message)
            elapsed = time.monotonic() - gen_start
            response_text = str(result)
            logger.info("AgentCore invoke complete: %.3fs, len=%d", elapsed, len(response_text))
            return {"result": response_text}
        except Exception as e:
            logger.error("AgentCore invoke error: %s: %s", type(e).__name__, e, exc_info=True)
            return {"error": str(e)}
