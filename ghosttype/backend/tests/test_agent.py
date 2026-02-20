"""Tests for agent.py."""

import importlib
import os
from pathlib import Path
from unittest import mock

import pytest


class TestLoadSystemPrompt:
    def test_loads_from_file(self):
        from agent import _load_system_prompt

        prompt = _load_system_prompt()
        assert "GhostType" in prompt
        assert "CRITICAL RULES" in prompt or "Output ONLY" in prompt

    def test_fallback_when_file_missing(self, tmp_path):
        import agent

        original = agent._PROMPTS_DIR
        agent._PROMPTS_DIR = tmp_path / "nonexistent"

        try:
            prompt = agent._load_system_prompt()
            assert "GhostType" in prompt
            assert "writing assistant" in prompt
        finally:
            agent._PROMPTS_DIR = original


class TestCreateModel:
    def test_unknown_provider_raises(self):
        import agent

        original_config = agent.config
        mock_config = mock.MagicMock()
        mock_config.model_provider = "unknown_provider"
        agent.config = mock_config

        try:
            with pytest.raises(ValueError, match="Unknown model provider"):
                agent.create_model()
        finally:
            agent.config = original_config

    def test_bedrock_provider_uses_boto_session(self):
        """Test that bedrock provider creates a boto3 session with profile."""
        import agent

        original_config = agent.config
        mock_config = mock.MagicMock()
        mock_config.model_provider = "bedrock"
        mock_config.model_id = "us.anthropic.claude-sonnet-4-20250514-v1:0"
        mock_config.max_tokens = 2048
        mock_config.aws_region = "us-west-2"
        mock_config.aws_profile = "test-profile"
        agent.config = mock_config

        try:
            with mock.patch("boto3.Session") as MockSession, \
                 mock.patch("strands.models.bedrock.BedrockModel") as MockModel:
                MockSession.return_value = mock.MagicMock()
                MockSession.return_value.region_name = "us-west-2"
                MockModel.return_value = mock.MagicMock()

                model = agent.create_model()

                MockSession.assert_called_once_with(
                    region_name="us-west-2",
                    profile_name="test-profile",
                )
                MockModel.assert_called_once()
                call_kwargs = MockModel.call_args[1]
                assert call_kwargs["boto_session"] == MockSession.return_value
                assert call_kwargs["model_id"] == "us.anthropic.claude-sonnet-4-20250514-v1:0"
                assert call_kwargs["max_tokens"] == 2048
        finally:
            agent.config = original_config

    def test_bedrock_provider_no_profile(self):
        """When aws_profile is empty, boto3.Session should not receive profile_name."""
        import agent

        original_config = agent.config
        mock_config = mock.MagicMock()
        mock_config.model_provider = "bedrock"
        mock_config.model_id = "test-model"
        mock_config.max_tokens = 1024
        mock_config.aws_region = "us-east-1"
        mock_config.aws_profile = ""
        agent.config = mock_config

        try:
            with mock.patch("boto3.Session") as MockSession, \
                 mock.patch("strands.models.bedrock.BedrockModel") as MockModel:
                MockSession.return_value = mock.MagicMock()
                MockSession.return_value.region_name = "us-east-1"
                MockModel.return_value = mock.MagicMock()

                agent.create_model()

                MockSession.assert_called_once_with(region_name="us-east-1")
        finally:
            agent.config = original_config


class TestCreateAgent:
    def _make_mock_agent(self):
        """Helper to create a mock agent and patch dependencies."""
        mock_model = mock.MagicMock()
        mock_agent_instance = mock.MagicMock()
        mock_agent_instance.tool_registry.get_all_tools_config.return_value = [{}, {}, {}]
        return mock_model, mock_agent_instance

    def test_creates_agent_with_null_handler_by_default(self):
        """When no callback_handler is given, agent should not use None."""
        import agent

        mock_model, mock_agent_instance = self._make_mock_agent()

        with mock.patch.object(agent, "create_model", return_value=mock_model), \
             mock.patch("agent.Agent", return_value=mock_agent_instance) as MockAgent:

            result = agent.create_agent()

            MockAgent.assert_called_once()
            call_kwargs = MockAgent.call_args[1]
            # Should not be None — should be the null_callback_handler
            assert call_kwargs["callback_handler"] is not None

    def test_creates_agent_with_custom_handler(self):
        """When a callback_handler is given, agent should use it."""
        import agent

        custom_handler = mock.MagicMock()
        mock_model, mock_agent_instance = self._make_mock_agent()

        with mock.patch.object(agent, "create_model", return_value=mock_model), \
             mock.patch("agent.Agent", return_value=mock_agent_instance) as MockAgent:

            result = agent.create_agent(callback_handler=custom_handler)

            MockAgent.assert_called_once()
            call_kwargs = MockAgent.call_args[1]
            assert call_kwargs["callback_handler"] is custom_handler

    def test_agent_has_three_tools(self):
        """Agent should be created with the 3 writing tools."""
        import agent

        mock_model, mock_agent_instance = self._make_mock_agent()

        with mock.patch.object(agent, "create_model", return_value=mock_model), \
             mock.patch("agent.Agent", return_value=mock_agent_instance) as MockAgent:

            agent.create_agent()

            call_kwargs = MockAgent.call_args[1]
            tools = call_kwargs["tools"]
            assert len(tools) == 3

    def test_agent_includes_mcp_tools(self):
        """When mcp_tools are provided, they are appended to the tools list."""
        import agent

        mock_model, mock_agent_instance = self._make_mock_agent()
        mock_mcp_tool = mock.MagicMock()

        with mock.patch.object(agent, "create_model", return_value=mock_model), \
             mock.patch("agent.Agent", return_value=mock_agent_instance) as MockAgent:

            agent.create_agent(mcp_tools=[mock_mcp_tool])

            call_kwargs = MockAgent.call_args[1]
            tools = call_kwargs["tools"]
            assert len(tools) == 4
            assert mock_mcp_tool in tools

    def test_agent_no_mcp_tools_by_default(self):
        """When mcp_tools is None or empty, only the 3 built-in tools are used."""
        import agent

        mock_model, mock_agent_instance = self._make_mock_agent()

        with mock.patch.object(agent, "create_model", return_value=mock_model), \
             mock.patch("agent.Agent", return_value=mock_agent_instance) as MockAgent:

            agent.create_agent(mcp_tools=None)
            assert len(MockAgent.call_args[1]["tools"]) == 3

            agent.create_agent(mcp_tools=[])
            assert len(MockAgent.call_args[1]["tools"]) == 3

    def test_agent_uses_system_prompt_from_file(self):
        """Agent should receive the system prompt loaded from prompts/system.txt."""
        import agent

        mock_model, mock_agent_instance = self._make_mock_agent()

        with mock.patch.object(agent, "create_model", return_value=mock_model), \
             mock.patch("agent.Agent", return_value=mock_agent_instance) as MockAgent:

            agent.create_agent()

            call_kwargs = MockAgent.call_args[1]
            system_prompt = call_kwargs["system_prompt"]
            assert "GhostType" in system_prompt
