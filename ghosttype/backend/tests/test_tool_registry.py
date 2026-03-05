"""Tests for tool_registry.py."""

import pytest


class TestToolRegistry:
    def test_all_builtins_registered(self):
        from tool_registry import TOOL_REGISTRY

        expected = {
            "rewrite_text", "fix_grammar", "translate_text",
            "count_words", "extract_key_points", "change_tone",
            "save_memory", "recall_memories", "forget_memory",
        }
        assert set(TOOL_REGISTRY.keys()) == expected

    def test_resolve_known_tools(self):
        from tool_registry import resolve_tools

        tools = resolve_tools(["rewrite_text", "fix_grammar"])
        assert len(tools) == 2
        # Each should be a callable @tool function
        for t in tools:
            assert callable(t)

    def test_resolve_unknown_tool_raises(self):
        from tool_registry import resolve_tools

        with pytest.raises(KeyError, match="nonexistent_tool"):
            resolve_tools(["rewrite_text", "nonexistent_tool"])

    def test_resolve_empty_list(self):
        from tool_registry import resolve_tools

        assert resolve_tools([]) == []

    def test_registry_values_are_callable(self):
        from tool_registry import TOOL_REGISTRY

        for name, func in TOOL_REGISTRY.items():
            assert callable(func), f"Tool '{name}' is not callable"
