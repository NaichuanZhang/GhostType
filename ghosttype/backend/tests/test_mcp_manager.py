"""Tests for mcp_manager.py."""

import json
from pathlib import Path
from unittest import mock

import pytest


class TestLoadConfig:
    def test_load_config_from_file(self, tmp_path):
        config_data = {
            "servers": {
                "searxng": {
                    "command": "mcp-searxng",
                    "args": ["--port", "9999"],
                    "env": {"SEARXNG_URL": "http://localhost:1234"},
                    "enabled": True,
                }
            }
        }
        config_file = tmp_path / "mcp_config.json"
        config_file.write_text(json.dumps(config_data))

        from mcp_manager import MCPManager

        manager = MCPManager(config_path=config_file)
        assert "searxng" in manager._config["servers"]
        assert manager._config["servers"]["searxng"]["command"] == "mcp-searxng"
        assert manager._config["servers"]["searxng"]["args"] == ["--port", "9999"]

    def test_load_config_missing_file(self, tmp_path):
        from mcp_manager import MCPManager

        manager = MCPManager(config_path=tmp_path / "nonexistent.json")
        assert manager._config == {"servers": {}}

    def test_load_config_invalid_json(self, tmp_path):
        config_file = tmp_path / "bad.json"
        config_file.write_text("not valid json {{{")

        from mcp_manager import MCPManager

        manager = MCPManager(config_path=config_file)
        assert manager._config == {"servers": {}}


class TestEnabledServers:
    def _make_manager(self, tmp_path, servers):
        config_file = tmp_path / "mcp_config.json"
        config_file.write_text(json.dumps({"servers": servers}))
        from mcp_manager import MCPManager
        return MCPManager(config_path=config_file)

    def test_filters_disabled_servers(self, tmp_path):
        manager = self._make_manager(tmp_path, {
            "enabled_one": {"command": "cmd1", "enabled": True},
            "disabled_one": {"command": "cmd2", "enabled": False},
            "default_enabled": {"command": "cmd3"},
        })
        enabled = manager._enabled_servers()
        assert "enabled_one" in enabled
        assert "default_enabled" in enabled
        assert "disabled_one" not in enabled

    def test_empty_servers(self, tmp_path):
        manager = self._make_manager(tmp_path, {})
        assert manager._enabled_servers() == {}


class TestGetMcpTools:
    def _make_config(self, tmp_path, servers):
        config_file = tmp_path / "mcp_config.json"
        config_file.write_text(json.dumps({"servers": servers}))
        return config_file

    def test_creates_client_for_enabled_server(self, tmp_path):
        config_file = self._make_config(tmp_path, {
            "searxng": {
                "command": "mcp-searxng",
                "args": [],
                "env": {"SEARXNG_URL": "http://localhost:1234"},
                "enabled": True,
            }
        })

        from mcp_manager import MCPManager

        manager = MCPManager(config_path=config_file)
        mock_client = mock.MagicMock()

        with mock.patch("mcp_manager.MCPClient", return_value=mock_client) as MockClient:
            tools = manager.get_mcp_tools()

        assert len(tools) == 1
        assert tools[0] is mock_client
        MockClient.assert_called_once()

    def test_skips_disabled_server(self, tmp_path):
        config_file = self._make_config(tmp_path, {
            "searxng": {
                "command": "mcp-searxng",
                "enabled": False,
            }
        })

        from mcp_manager import MCPManager

        manager = MCPManager(config_path=config_file)

        with mock.patch("mcp_manager.MCPClient") as MockClient:
            tools = manager.get_mcp_tools()

        MockClient.assert_not_called()
        assert tools == []

    def test_handles_construction_failure_gracefully(self, tmp_path):
        config_file = self._make_config(tmp_path, {
            "broken": {
                "command": "nonexistent-binary",
                "enabled": True,
            }
        })

        from mcp_manager import MCPManager

        manager = MCPManager(config_path=config_file)

        with mock.patch("mcp_manager.MCPClient", side_effect=RuntimeError("bad config")):
            tools = manager.get_mcp_tools()

        assert tools == []

    def test_partial_failure_returns_good_clients(self, tmp_path):
        config_file = self._make_config(tmp_path, {
            "good": {"command": "good-cmd", "enabled": True},
            "bad": {"command": "bad-cmd", "enabled": True},
        })

        from mcp_manager import MCPManager

        manager = MCPManager(config_path=config_file)

        good_client = mock.MagicMock()
        call_count = 0

        def make_client(factory):
            nonlocal call_count
            call_count += 1
            if call_count == 1:
                return good_client
            raise RuntimeError("crash")

        with mock.patch("mcp_manager.MCPClient", side_effect=make_client):
            tools = manager.get_mcp_tools()

        assert len(tools) == 1
        assert tools[0] is good_client

    def test_returns_empty_when_no_servers_configured(self):
        from mcp_manager import MCPManager

        manager = MCPManager(config_path=Path("/nonexistent"))
        assert manager.get_mcp_tools() == []

    def test_creates_fresh_clients_each_call(self, tmp_path):
        """Each call to get_mcp_tools() should create new MCPClient instances."""
        config_file = self._make_config(tmp_path, {
            "searxng": {"command": "mcp-searxng", "enabled": True},
        })

        from mcp_manager import MCPManager

        manager = MCPManager(config_path=config_file)

        client_a = mock.MagicMock()
        client_b = mock.MagicMock()

        with mock.patch("mcp_manager.MCPClient", side_effect=[client_a, client_b]):
            tools1 = manager.get_mcp_tools()
            tools2 = manager.get_mcp_tools()

        assert tools1[0] is client_a
        assert tools2[0] is client_b
        assert tools1[0] is not tools2[0]


class TestStartStop:
    """start() and stop() are lightweight — just logging and no-ops."""

    def test_start_logs_without_error(self, tmp_path):
        config_file = tmp_path / "mcp_config.json"
        config_file.write_text(json.dumps({
            "servers": {
                "searxng": {"command": "mcp-searxng", "enabled": True},
                "disabled": {"command": "other", "enabled": False},
            }
        }))

        from mcp_manager import MCPManager

        manager = MCPManager(config_path=config_file)
        # Should not raise
        manager.start()

    def test_start_empty_config(self):
        from mcp_manager import MCPManager

        manager = MCPManager(config_path=Path("/nonexistent"))
        manager.start()  # should not raise

    def test_stop_is_noop(self, tmp_path):
        config_file = tmp_path / "mcp_config.json"
        config_file.write_text(json.dumps({"servers": {"a": {"command": "x"}}}))

        from mcp_manager import MCPManager

        manager = MCPManager(config_path=config_file)
        manager.stop()  # should not raise
