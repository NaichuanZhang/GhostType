"""MCP (Model Context Protocol) server lifecycle management for GhostType."""

import json
import logging
from pathlib import Path

from strands.tools.mcp import MCPClient
from mcp import stdio_client, StdioServerParameters

logger = logging.getLogger("ghosttype.mcp")

_DEFAULT_CONFIG_PATH = Path(__file__).parent / "mcp_config.json"


class MCPManager:
    """Provides MCP tool providers to the Strands Agent.

    Loads server definitions from a JSON config file. On each call to
    ``get_mcp_tools()``, creates fresh ``MCPClient`` instances for every
    enabled server. The Agent's tool registry manages the MCPClient lifecycle
    (starting/stopping the subprocess) — we intentionally do NOT pre-start
    them here, because the Agent calls ``__enter__`` internally when it
    processes its tools list.

    Usage::

        manager = MCPManager()
        tools = manager.get_mcp_tools()  # pass into Agent(tools=[...])
    """

    def __init__(self, config_path: Path | None = None):
        self._config_path = config_path or _DEFAULT_CONFIG_PATH
        self._config: dict = self._load_config()

    def _load_config(self) -> dict:
        """Load MCP server definitions from the JSON config file."""
        if not self._config_path.exists():
            logger.info("MCP config not found at %s, no MCP servers will be loaded", self._config_path)
            return {"servers": {}}

        try:
            with open(self._config_path) as f:
                data = json.load(f)
            server_count = len(data.get("servers", {}))
            logger.info("Loaded MCP config: %d server(s) defined", server_count)
            return data
        except (json.JSONDecodeError, OSError) as e:
            logger.warning("Failed to load MCP config from %s: %s", self._config_path, e)
            return {"servers": {}}

    def _enabled_servers(self) -> dict[str, dict]:
        """Return only the enabled server entries from config."""
        return {
            name: cfg
            for name, cfg in self._config.get("servers", {}).items()
            if cfg.get("enabled", True)
        }

    def start(self):
        """Log configured MCP servers. Actual processes are started by the Agent."""
        servers = self._config.get("servers", {})
        if not servers:
            logger.info("No MCP servers configured")
            return

        enabled = self._enabled_servers()
        disabled = set(servers) - set(enabled)
        for name in disabled:
            logger.info("MCP server '%s' is disabled, skipping", name)
        for name, cfg in enabled.items():
            logger.info("MCP server '%s' configured (command: %s)", name, cfg["command"])

    def stop(self):
        """No-op — Agent manages MCPClient subprocess lifecycle."""
        pass

    def get_mcp_tools(self) -> list[MCPClient]:
        """Create fresh MCPClient instances for each enabled server.

        Returns a list of MCPClient objects ready to be passed into the
        Agent's tools list. The Agent will call ``__enter__`` on each one
        to start the MCP subprocess, and manages cleanup on its own.

        Servers whose MCPClient fails to construct (e.g. bad config) are
        logged and skipped — they don't crash the backend.
        """
        clients: list[MCPClient] = []
        for name, server_cfg in self._enabled_servers().items():
            try:
                client = MCPClient(
                    lambda sc=server_cfg: stdio_client(
                        StdioServerParameters(
                            command=sc["command"],
                            args=sc.get("args", []),
                            env=sc.get("env"),
                        )
                    )
                )
                clients.append(client)
                logger.debug("Created MCPClient for server '%s'", name)
            except Exception:
                logger.warning("Failed to create MCPClient for server '%s', skipping", name, exc_info=True)

        return clients
