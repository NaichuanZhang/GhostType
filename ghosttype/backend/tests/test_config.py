"""Tests for config.py."""

import os
from unittest import mock

import pytest


def _make_config(**env_overrides):
    """Create a fresh Config instance with optional env var overrides."""
    with mock.patch.dict(os.environ, env_overrides, clear=False):
        # Re-import to pick up new env vars (Config reads at class-definition time)
        import importlib
        import config as config_mod

        importlib.reload(config_mod)
        return config_mod.Config()


class TestConfigDefaults:
    def test_default_host_and_port(self):
        cfg = _make_config()
        assert cfg.host == "127.0.0.1"
        assert cfg.port == 8420

    def test_default_provider(self):
        cfg = _make_config()
        assert cfg.model_provider == "bedrock"

    def test_default_model_id(self):
        cfg = _make_config()
        assert "claude" in cfg.model_id.lower() or "sonnet" in cfg.model_id.lower()

    def test_default_max_tokens(self):
        cfg = _make_config()
        assert cfg.max_tokens == 2048

    def test_default_temperature(self):
        cfg = _make_config()
        assert cfg.temperature == 0.7

    def test_default_aws_region(self):
        cfg = _make_config()
        assert cfg.aws_region == "us-west-2"

    def test_default_log_level(self):
        cfg = _make_config()
        assert cfg.log_level == "DEBUG"


class TestConfigEnvOverrides:
    def test_model_id_override(self):
        cfg = _make_config(GHOSTTYPE_MODEL_ID="my-custom-model")
        assert cfg.model_id == "my-custom-model"

    def test_max_tokens_override(self):
        cfg = _make_config(GHOSTTYPE_MAX_TOKENS="4096")
        assert cfg.max_tokens == 4096

    def test_temperature_override(self):
        cfg = _make_config(GHOSTTYPE_TEMPERATURE="0.3")
        assert cfg.temperature == pytest.approx(0.3)

    def test_aws_profile_from_ghosttype_env(self):
        cfg = _make_config(GHOSTTYPE_AWS_PROFILE="my-profile")
        assert cfg.aws_profile == "my-profile"

    def test_aws_profile_falls_back_to_aws_profile_env(self):
        cfg = _make_config(AWS_PROFILE="fallback-profile")
        assert cfg.aws_profile == "fallback-profile"

    def test_ghosttype_aws_profile_takes_precedence(self):
        cfg = _make_config(
            GHOSTTYPE_AWS_PROFILE="ghosttype-profile",
            AWS_PROFILE="aws-profile",
        )
        assert cfg.aws_profile == "ghosttype-profile"

    def test_aws_region_override(self):
        cfg = _make_config(GHOSTTYPE_AWS_REGION="eu-west-1")
        assert cfg.aws_region == "eu-west-1"

    def test_aws_region_falls_back_to_aws_default_region(self):
        cfg = _make_config(AWS_DEFAULT_REGION="ap-southeast-1")
        assert cfg.aws_region == "ap-southeast-1"

    def test_log_level_override(self):
        cfg = _make_config(GHOSTTYPE_LOG_LEVEL="WARNING")
        assert cfg.log_level == "WARNING"
