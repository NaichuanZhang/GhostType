"""Tests for tools/memory_tools.py."""

from __future__ import annotations

import json
from pathlib import Path
from unittest import mock

import pytest


@pytest.fixture
def memory_file(tmp_path: Path) -> Path:
    """Return a temporary memory file path (does not exist yet)."""
    return tmp_path / "memories.json"


class TestSaveMemory:
    def test_creates_file(self, memory_file: Path):
        from tools.memory_tools import _load_memories, _save_memories

        _save_memories(
            [{"id": "abc", "content": "test", "created_at": "2026-01-01T00:00:00"}],
            path=memory_file,
        )
        assert memory_file.exists()
        data = json.loads(memory_file.read_text())
        assert len(data) == 1
        assert data[0]["content"] == "test"

    def test_appends(self, memory_file: Path):
        from tools.memory_tools import _load_memories, _save_memories

        _save_memories(
            [{"id": "a", "content": "first", "created_at": "2026-01-01T00:00:00"}],
            path=memory_file,
        )
        memories = _load_memories(path=memory_file)
        memories.append({"id": "b", "content": "second", "created_at": "2026-01-02T00:00:00"})
        _save_memories(memories, path=memory_file)

        result = _load_memories(path=memory_file)
        assert len(result) == 2
        assert result[0]["content"] == "first"
        assert result[1]["content"] == "second"

    def test_caps_at_max(self, memory_file: Path):
        from tools.memory_tools import MAX_MEMORIES, _load_memories, _save_memories

        memories = [
            {"id": str(i), "content": f"memory {i}", "created_at": "2026-01-01T00:00:00"}
            for i in range(MAX_MEMORIES + 5)
        ]
        # Simulate what save_memory does: keep only newest MAX_MEMORIES
        capped = memories[-MAX_MEMORIES:]
        _save_memories(capped, path=memory_file)

        result = _load_memories(path=memory_file)
        assert len(result) == MAX_MEMORIES
        # Oldest should be trimmed, newest kept
        assert result[0]["content"] == "memory 5"
        assert result[-1]["content"] == f"memory {MAX_MEMORIES + 4}"

    def test_save_memory_tool(self, memory_file: Path):
        """Test the save_memory @tool function end-to-end."""
        from tools import memory_tools

        original = memory_tools.MEMORY_FILE
        memory_tools.MEMORY_FILE = memory_file
        try:
            result = memory_tools.save_memory(content="User likes Python")
            assert "Remembered" in result

            memories = memory_tools._load_memories(path=memory_file)
            assert len(memories) == 1
            assert memories[0]["content"] == "User likes Python"
            assert "id" in memories[0]
            assert "created_at" in memories[0]
        finally:
            memory_tools.MEMORY_FILE = original


class TestRecallMemories:
    def test_empty(self, memory_file: Path):
        from tools.memory_tools import _load_memories

        result = _load_memories(path=memory_file)
        assert result == []

    def test_returns_all(self, memory_file: Path):
        from tools import memory_tools

        original = memory_tools.MEMORY_FILE
        memory_tools.MEMORY_FILE = memory_file
        try:
            memory_tools._save_memories([
                {"id": "a1", "content": "fact one", "created_at": "2026-01-01"},
                {"id": "b2", "content": "fact two", "created_at": "2026-01-02"},
                {"id": "c3", "content": "fact three", "created_at": "2026-01-03"},
            ], path=memory_file)

            result = memory_tools.recall_memories()
            assert "[a1] fact one" in result
            assert "[b2] fact two" in result
            assert "[c3] fact three" in result
        finally:
            memory_tools.MEMORY_FILE = original

    def test_recall_empty(self, memory_file: Path):
        from tools import memory_tools

        original = memory_tools.MEMORY_FILE
        memory_tools.MEMORY_FILE = memory_file
        try:
            result = memory_tools.recall_memories()
            assert result == "No memories saved yet."
        finally:
            memory_tools.MEMORY_FILE = original


class TestForgetMemory:
    def test_removes(self, memory_file: Path):
        from tools import memory_tools

        original = memory_tools.MEMORY_FILE
        memory_tools.MEMORY_FILE = memory_file
        try:
            memory_tools._save_memories([
                {"id": "keep", "content": "stays", "created_at": "2026-01-01"},
                {"id": "gone", "content": "removed", "created_at": "2026-01-02"},
            ], path=memory_file)

            result = memory_tools.forget_memory(memory_id="gone")
            assert "Forgot memory gone" in result

            remaining = memory_tools._load_memories(path=memory_file)
            assert len(remaining) == 1
            assert remaining[0]["id"] == "keep"
        finally:
            memory_tools.MEMORY_FILE = original

    def test_nonexistent_id(self, memory_file: Path):
        from tools import memory_tools

        original = memory_tools.MEMORY_FILE
        memory_tools.MEMORY_FILE = memory_file
        try:
            memory_tools._save_memories([
                {"id": "exists", "content": "here", "created_at": "2026-01-01"},
            ], path=memory_file)

            # Should not crash
            result = memory_tools.forget_memory(memory_id="bogus")
            assert "Forgot memory bogus" in result

            remaining = memory_tools._load_memories(path=memory_file)
            assert len(remaining) == 1
        finally:
            memory_tools.MEMORY_FILE = original


class TestBuildMemoryContext:
    def test_empty(self, memory_file: Path):
        from tools.memory_tools import build_memory_context

        result = build_memory_context(path=memory_file)
        assert result == ""

    def test_formats_memories(self, memory_file: Path):
        from tools.memory_tools import _save_memories, build_memory_context

        _save_memories([
            {"id": "a", "content": "User prefers bullet points", "created_at": "2026-01-01"},
            {"id": "b", "content": "User works in Xcode", "created_at": "2026-01-02"},
        ], path=memory_file)

        result = build_memory_context(path=memory_file)
        assert "## Your Memories" in result
        assert "- User prefers bullet points" in result
        assert "- User works in Xcode" in result
        assert "save_memory" in result


class TestLoadMemoriesEdgeCases:
    def test_invalid_json(self, memory_file: Path):
        from tools.memory_tools import _load_memories

        memory_file.write_text("not json at all", encoding="utf-8")
        result = _load_memories(path=memory_file)
        assert result == []

    def test_non_list_json(self, memory_file: Path):
        from tools.memory_tools import _load_memories

        memory_file.write_text('{"key": "value"}', encoding="utf-8")
        result = _load_memories(path=memory_file)
        assert result == []
