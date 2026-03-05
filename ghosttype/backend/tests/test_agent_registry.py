"""Tests for agent_registry.py."""

import textwrap
from pathlib import Path

import pytest


class TestAgentDefinition:
    def test_frozen_dataclass(self):
        from agent_registry import AgentDefinition

        defn = AgentDefinition(
            id="test",
            name="Test Agent",
            description="A test agent",
            system_prompt_file="system.txt",
            tools=["rewrite_text"],
            mcp_servers=[],
            supported_modes=["draft"],
            is_default=False,
            app_mappings=[],
        )
        with pytest.raises(AttributeError):
            defn.id = "changed"

    def test_fields(self):
        from agent_registry import AgentDefinition

        defn = AgentDefinition(
            id="coding",
            name="Code Assistant",
            description="Helps with code",
            system_prompt_file="coding.txt",
            tools=["count_words"],
            mcp_servers=["searxng"],
            supported_modes=["chat"],
            is_default=False,
            app_mappings=["com.microsoft.VSCode"],
        )
        assert defn.id == "coding"
        assert defn.name == "Code Assistant"
        assert defn.tools == ["count_words"]
        assert defn.app_mappings == ["com.microsoft.VSCode"]
        assert defn.is_default is False


class TestAgentRegistrySnapshot:
    def _make_snapshot(self):
        from agent_registry import AgentDefinition, AgentRegistrySnapshot

        general = AgentDefinition(
            id="general", name="General", description="General assistant",
            system_prompt_file="system.txt", tools=["rewrite_text"],
            mcp_servers=[], supported_modes=["draft", "chat"],
            is_default=True, app_mappings=[],
        )
        coding = AgentDefinition(
            id="coding", name="Code", description="Code assistant",
            system_prompt_file="coding.txt", tools=["count_words"],
            mcp_servers=[], supported_modes=["chat"],
            is_default=False, app_mappings=["com.microsoft.VSCode", "com.apple.dt.Xcode"],
        )
        email = AgentDefinition(
            id="email", name="Email", description="Email assistant",
            system_prompt_file="email.txt", tools=["rewrite_text", "change_tone"],
            mcp_servers=[], supported_modes=["draft", "chat"],
            is_default=False, app_mappings=["com.tinyspeck.slackmacgap"],
        )
        return AgentRegistrySnapshot(
            agents={"general": general, "coding": coding, "email": email},
            default_agent_id="general",
        )

    def test_get_existing_agent(self):
        snapshot = self._make_snapshot()
        defn = snapshot.get("coding")
        assert defn is not None
        assert defn.id == "coding"

    def test_get_nonexistent_returns_none(self):
        snapshot = self._make_snapshot()
        assert snapshot.get("nonexistent") is None

    def test_get_for_bundle_exact_match(self):
        snapshot = self._make_snapshot()
        defn = snapshot.get_for_bundle("com.microsoft.VSCode")
        assert defn is not None
        assert defn.id == "coding"

    def test_get_for_bundle_prefix_match(self):
        snapshot = self._make_snapshot()
        # "com.jetbrains" could be a prefix — but in this test data we
        # only have exact entries. Let's test with an exact match.
        defn = snapshot.get_for_bundle("com.tinyspeck.slackmacgap")
        assert defn is not None
        assert defn.id == "email"

    def test_get_for_bundle_no_match(self):
        snapshot = self._make_snapshot()
        assert snapshot.get_for_bundle("com.unknown.App") is None

    def test_get_for_bundle_none(self):
        snapshot = self._make_snapshot()
        assert snapshot.get_for_bundle(None) is None

    def test_to_dicts(self):
        snapshot = self._make_snapshot()
        result = snapshot.to_dicts()
        assert isinstance(result, list)
        assert len(result) == 3
        ids = {d["id"] for d in result}
        assert ids == {"general", "coding", "email"}
        # Verify structure of one entry
        general = next(d for d in result if d["id"] == "general")
        assert general["name"] == "General"
        assert general["is_default"] is True
        assert general["supported_modes"] == ["draft", "chat"]

    def test_default_agent_id(self):
        snapshot = self._make_snapshot()
        assert snapshot.default_agent_id == "general"


class TestAgentRegistryPrefix:
    """Test prefix matching for bundle IDs."""

    def test_prefix_matching(self):
        from agent_registry import AgentDefinition, AgentRegistrySnapshot

        coding = AgentDefinition(
            id="coding", name="Code", description="Code assistant",
            system_prompt_file="coding.txt", tools=[],
            mcp_servers=[], supported_modes=["chat"],
            is_default=False, app_mappings=["com.jetbrains"],
        )
        snapshot = AgentRegistrySnapshot(
            agents={"coding": coding},
            default_agent_id="coding",
        )
        # "com.jetbrains.intellij" starts with "com.jetbrains"
        defn = snapshot.get_for_bundle("com.jetbrains.intellij")
        assert defn is not None
        assert defn.id == "coding"


class TestAgentRegistryYAML:
    def _write_yaml(self, tmp_path, content):
        agents_dir = tmp_path / "agents"
        agents_dir.mkdir()
        yaml_file = agents_dir / "agents.yaml"
        yaml_file.write_text(content)
        return tmp_path

    def test_loads_from_yaml(self, tmp_path):
        yaml_content = textwrap.dedent("""\
            agents:
              - id: "general"
                name: "General Assistant"
                description: "All-purpose assistant"
                system_prompt_file: "system.txt"
                tools: [rewrite_text, fix_grammar]
                mcp_servers: []
                supported_modes: [draft, chat]
                is_default: true
              - id: "coding"
                name: "Code Assistant"
                description: "Helps with code"
                system_prompt_file: "coding.txt"
                tools: [count_words]
                mcp_servers: []
                supported_modes: [chat]
                is_default: false
                app_mappings: ["com.microsoft.VSCode"]
        """)
        backend_dir = self._write_yaml(tmp_path, yaml_content)

        from agent_registry import AgentRegistry

        registry = AgentRegistry(backend_dir=backend_dir)
        snapshot = registry.snapshot()

        assert snapshot.get("general") is not None
        assert snapshot.get("coding") is not None
        assert snapshot.default_agent_id == "general"
        assert snapshot.get("general").tools == ["rewrite_text", "fix_grammar"]
        assert snapshot.get("coding").app_mappings == ["com.microsoft.VSCode"]

    def test_fallback_when_no_yaml(self, tmp_path):
        """When agents.yaml doesn't exist, a default 'general' agent is created."""
        from agent_registry import AgentRegistry

        registry = AgentRegistry(backend_dir=tmp_path)
        snapshot = registry.snapshot()

        assert snapshot.default_agent_id == "general"
        defn = snapshot.get("general")
        assert defn is not None
        assert defn.name == "General Assistant"
        assert defn.is_default is True

    def test_invalid_yaml_falls_back(self, tmp_path):
        agents_dir = tmp_path / "agents"
        agents_dir.mkdir()
        yaml_file = agents_dir / "agents.yaml"
        yaml_file.write_text("not: valid: yaml: [[[")

        from agent_registry import AgentRegistry

        registry = AgentRegistry(backend_dir=tmp_path)
        snapshot = registry.snapshot()
        assert snapshot.default_agent_id == "general"

    def test_no_default_agent_uses_first(self, tmp_path):
        yaml_content = textwrap.dedent("""\
            agents:
              - id: "alpha"
                name: "Alpha"
                description: "First agent"
                system_prompt_file: "system.txt"
                tools: []
                supported_modes: [draft]
              - id: "beta"
                name: "Beta"
                description: "Second agent"
                system_prompt_file: "system.txt"
                tools: []
                supported_modes: [chat]
        """)
        backend_dir = self._write_yaml(tmp_path, yaml_content)

        from agent_registry import AgentRegistry

        registry = AgentRegistry(backend_dir=backend_dir)
        snapshot = registry.snapshot()
        # When no agent has is_default: true, the first one is used
        assert snapshot.default_agent_id == "alpha"
