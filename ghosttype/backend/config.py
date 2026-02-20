"""Configuration for the GhostType backend."""

import os
from dataclasses import dataclass


@dataclass
class Config:
    """Backend configuration loaded from environment variables."""

    # Server
    host: str = "127.0.0.1"
    port: int = 8420

    # Model provider: "bedrock"
    model_provider: str = os.environ.get("GHOSTTYPE_PROVIDER", "bedrock")

    # Model ID
    model_id: str = os.environ.get(
        "GHOSTTYPE_MODEL_ID", "global.anthropic.claude-opus-4-6-v1"
    )

    # AWS (for Bedrock provider) — supports tokenmaster via AWS_PROFILE
    aws_profile: str = os.environ.get(
        "GHOSTTYPE_AWS_PROFILE", os.environ.get("AWS_PROFILE", "")
    )
    aws_region: str = os.environ.get(
        "GHOSTTYPE_AWS_REGION", os.environ.get("AWS_DEFAULT_REGION", "us-west-2")
    )

    # Generation settings
    max_tokens: int = int(os.environ.get("GHOSTTYPE_MAX_TOKENS", "2048"))
    temperature: float = float(os.environ.get("GHOSTTYPE_TEMPERATURE", "0.7"))

    # Logging
    log_level: str = os.environ.get("GHOSTTYPE_LOG_LEVEL", "DEBUG")


config = Config()
