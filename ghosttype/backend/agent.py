"""Strands Agent configuration for GhostType."""

import logging
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable

from strands import Agent, tool

from config import config

logger = logging.getLogger("ghosttype.agent")

# Load system prompt from file (single source of truth)
_PROMPTS_DIR = Path(__file__).parent / "prompts"


@dataclass
class ModelConfig:
    """Per-request model configuration. Falls back to env var defaults."""

    provider: str = ""
    model_id: str = ""
    aws_profile: str = ""
    aws_region: str = ""

    @classmethod
    def from_request(cls, data: dict | None) -> "ModelConfig":
        """Create from a request's 'config' dict, falling back to env var defaults."""
        if not data:
            return cls()
        return cls(
            provider=data.get("provider", ""),
            model_id=data.get("model_id", ""),
            aws_profile=data.get("aws_profile", ""),
            aws_region=data.get("aws_region", ""),
        )

    def effective_provider(self) -> str:
        return (self.provider or config.model_provider).lower()

    def effective_model_id(self) -> str:
        return self.model_id or config.model_id

    def effective_aws_profile(self) -> str:
        return self.aws_profile or config.aws_profile

    def effective_aws_region(self) -> str:
        return self.aws_region or config.aws_region


def _load_system_prompt(mode_type: str = "draft") -> str:
    """Load the system prompt for the given mode type.

    Args:
        mode_type: "draft" loads prompts/system.txt (restrictive writing prompt),
                   "chat" loads prompts/chat.txt (conversational prompt).
    """
    filename = "chat.txt" if mode_type == "chat" else "system.txt"
    prompt_file = _PROMPTS_DIR / filename
    if prompt_file.exists():
        text = prompt_file.read_text().strip()
        logger.debug("Loaded system prompt from %s (%d chars)", prompt_file, len(text))
        return text

    logger.warning("System prompt file not found at %s, using fallback", prompt_file)
    if mode_type == "chat":
        return (
            "You are GhostType, an AI assistant embedded in macOS. "
            "Be concise but thorough. Use markdown formatting when it helps readability."
        )
    return (
        "You are GhostType, an AI writing assistant. "
        "Output ONLY the requested text. No explanations or markdown."
    )


def create_model(model_config: ModelConfig | None = None):
    """Create the model provider based on configuration.

    Args:
        model_config: Per-request config overrides. Falls back to env var defaults.
    """
    mc = model_config or ModelConfig()
    provider = mc.effective_provider()
    model_id = mc.effective_model_id()

    logger.debug(
        "Creating model: provider=%s, model_id=%s, max_tokens=%d",
        provider, model_id, config.max_tokens,
    )

    if provider == "bedrock":
        import boto3
        from strands.models.bedrock import BedrockModel

        aws_profile = mc.effective_aws_profile()
        aws_region = mc.effective_aws_region()

        # Build boto3 session with optional profile (supports tokenmaster)
        session_kwargs: dict[str, Any] = {"region_name": aws_region}
        if aws_profile:
            session_kwargs["profile_name"] = aws_profile
            logger.debug("Using AWS profile: %s", aws_profile)

        session = boto3.Session(**session_kwargs)
        logger.debug("Boto3 session: region=%s, profile=%s", session.region_name, aws_profile or "(default)")

        return BedrockModel(
            model_id=model_id,
            boto_session=session,
            max_tokens=config.max_tokens,
        )

    else:
        raise ValueError(f"Unknown model provider: {provider}")


# Custom tools for writing assistance
@tool
def rewrite_text(text: str, style: str = "professional") -> str:
    """Rewrite the given text in the specified style.

    Args:
        text: The text to rewrite.
        style: The target style (professional, casual, formal, friendly, academic).

    Returns:
        The rewritten text.
    """
    return f"Please rewrite the following text in a {style} style:\n\n{text}"


@tool
def fix_grammar(text: str) -> str:
    """Fix grammar and spelling errors in the given text.

    Args:
        text: The text to fix.

    Returns:
        The corrected text.
    """
    return f"Fix all grammar and spelling errors in the following text, preserving the original meaning and tone:\n\n{text}"


@tool
def translate_text(text: str, target_language: str) -> str:
    """Translate text to the target language.

    Args:
        text: The text to translate.
        target_language: The language to translate to.

    Returns:
        The translated text.
    """
    return f"Translate the following text to {target_language}:\n\n{text}"


def create_agent(
    callback_handler: Callable | None = None,
    model_config: ModelConfig | None = None,
    mode_type: str = "draft",
    mcp_tools: list | None = None,
) -> Agent:
    """Create and configure the GhostType agent.

    Args:
        callback_handler: Optional callback for streaming events. If None,
            a null handler is used (no stdout printing).
        model_config: Per-request model configuration overrides.
        mode_type: "draft" for writing/editing (restrictive prompt),
                   "chat" for conversational Q&A (relaxed prompt).
        mcp_tools: Optional list of MCPClient instances (ToolProviders) to
                   merge into the agent's tools alongside the built-in tools.
    """
    model = create_model(model_config)
    system_prompt = _load_system_prompt(mode_type)

    # Use null handler by default so agent doesn't print to stdout
    from strands.handlers.callback_handler import null_callback_handler

    handler = callback_handler if callback_handler is not None else null_callback_handler

    tools: list = [rewrite_text, fix_grammar, translate_text]
    if mcp_tools:
        tools.extend(mcp_tools)

    agent = Agent(
        model=model,
        system_prompt=system_prompt,
        tools=tools,
        callback_handler=handler,
    )

    logger.debug("Agent created: mode_type=%s, tools=%d", mode_type, len(agent.tool_registry.get_all_tools_config()))
    return agent
