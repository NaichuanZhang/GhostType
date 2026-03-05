"""Agent definition registry — loads agent configs from YAML."""

import logging
from dataclasses import dataclass, field, asdict
from pathlib import Path

logger = logging.getLogger("ghosttype.agent_registry")

_DEFAULT_BACKEND_DIR = Path(__file__).parent


@dataclass(frozen=True)
class AgentDefinition:
    """Immutable agent configuration."""

    id: str
    name: str
    description: str
    system_prompt_file: str
    tools: list[str] = field(default_factory=list)
    mcp_servers: list[str] = field(default_factory=list)
    supported_modes: list[str] = field(default_factory=lambda: ["draft", "chat"])
    is_default: bool = False
    app_mappings: list[str] = field(default_factory=list)


@dataclass(frozen=True)
class AgentRegistrySnapshot:
    """Immutable snapshot of all registered agents."""

    agents: dict[str, AgentDefinition]
    default_agent_id: str

    def get(self, agent_id: str) -> AgentDefinition | None:
        return self.agents.get(agent_id)

    def get_for_bundle(self, bundle_id: str | None) -> AgentDefinition | None:
        """Find the agent whose app_mappings match the given bundle ID.

        Supports both exact match and prefix match (e.g. "com.jetbrains"
        matches "com.jetbrains.intellij").
        """
        if not bundle_id:
            return None
        for defn in self.agents.values():
            for mapping in defn.app_mappings:
                if bundle_id == mapping or bundle_id.startswith(mapping + "."):
                    return defn
        return None

    def to_dicts(self) -> list[dict]:
        """Serialize all agents for the /agents API endpoint."""
        return [asdict(defn) for defn in self.agents.values()]


def _build_fallback() -> AgentRegistrySnapshot:
    """Create a minimal default registry when no YAML is available."""
    general = AgentDefinition(
        id="general",
        name="General Assistant",
        description="All-purpose writing and chat assistant",
        system_prompt_file="system.txt",
        tools=["rewrite_text", "fix_grammar", "translate_text"],
        supported_modes=["draft", "chat"],
        is_default=True,
    )
    return AgentRegistrySnapshot(
        agents={"general": general},
        default_agent_id="general",
    )


class AgentRegistry:
    """Loads agent definitions from agents/agents.yaml."""

    def __init__(self, backend_dir: Path | None = None):
        self._backend_dir = backend_dir or _DEFAULT_BACKEND_DIR
        self._snapshot = self._load()

    def snapshot(self) -> AgentRegistrySnapshot:
        return self._snapshot

    def _load(self) -> AgentRegistrySnapshot:
        yaml_path = self._backend_dir / "agents" / "agents.yaml"
        if not yaml_path.exists():
            logger.info("No agents.yaml at %s, using fallback defaults", yaml_path)
            return _build_fallback()

        try:
            import yaml
        except ImportError:
            logger.warning("PyYAML not installed, using fallback defaults")
            return _build_fallback()

        try:
            raw = yaml.safe_load(yaml_path.read_text())
        except Exception as e:
            logger.warning("Failed to parse agents.yaml: %s, using fallback", e)
            return _build_fallback()

        entries = raw.get("agents", [])
        if not entries:
            logger.warning("agents.yaml has no agents, using fallback")
            return _build_fallback()

        agents: dict[str, AgentDefinition] = {}
        default_id: str | None = None

        for entry in entries:
            defn = AgentDefinition(
                id=entry["id"],
                name=entry["name"],
                description=entry.get("description", ""),
                system_prompt_file=entry.get("system_prompt_file", "system.txt"),
                tools=entry.get("tools", []),
                mcp_servers=entry.get("mcp_servers", []),
                supported_modes=entry.get("supported_modes", ["draft", "chat"]),
                is_default=entry.get("is_default", False),
                app_mappings=entry.get("app_mappings", []),
            )
            agents[defn.id] = defn
            if defn.is_default:
                default_id = defn.id

        # Fall back to the first agent if none is marked as default
        if default_id is None:
            default_id = next(iter(agents))

        logger.info(
            "Loaded %d agent(s) from agents.yaml, default=%s",
            len(agents), default_id,
        )
        return AgentRegistrySnapshot(agents=agents, default_agent_id=default_id)
