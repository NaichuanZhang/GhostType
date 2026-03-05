"""Long-term memory tools for GhostType agents.

Provides save/recall/forget tools backed by a JSON file at
~/.config/ghosttype/memories.json. Memories persist across sessions
and are injected into the system prompt on agent creation.
"""

from __future__ import annotations

import json
import logging
import tempfile
from datetime import datetime, timezone
from pathlib import Path
from uuid import uuid4

from strands import tool

logger = logging.getLogger("ghosttype.memory")

MEMORY_FILE = Path("~/.config/ghosttype/memories.json").expanduser()
MAX_MEMORIES = 50


def _load_memories(path: Path | None = None) -> list[dict]:
    """Load memories from the JSON file.

    Args:
        path: Override file path (for testing). Defaults to MEMORY_FILE.
    """
    file = path or MEMORY_FILE
    if not file.exists():
        return []
    try:
        data = json.loads(file.read_text(encoding="utf-8"))
        if not isinstance(data, list):
            logger.warning("Invalid memories file format, expected list")
            return []
        return data
    except (json.JSONDecodeError, OSError) as exc:
        logger.error("Failed to load memories: %s", exc)
        return []


def _save_memories(memories: list[dict], path: Path | None = None) -> None:
    """Persist memories to the JSON file with atomic write.

    Args:
        memories: The full list of memories to write.
        path: Override file path (for testing). Defaults to MEMORY_FILE.
    """
    file = path or MEMORY_FILE
    file.parent.mkdir(parents=True, exist_ok=True)

    # Atomic write: write to temp file in same dir, then rename
    tmp_fd = tempfile.NamedTemporaryFile(
        mode="w",
        suffix=".tmp",
        dir=file.parent,
        delete=False,
        encoding="utf-8",
    )
    try:
        json.dump(memories, tmp_fd, indent=2, ensure_ascii=False)
        tmp_fd.close()
        Path(tmp_fd.name).replace(file)
    except OSError as exc:
        logger.error("Failed to save memories: %s", exc)
        Path(tmp_fd.name).unlink(missing_ok=True)
        raise


def build_memory_context(path: Path | None = None) -> str:
    """Load memories and format as a system prompt section.

    Returns an empty string when no memories exist.

    Args:
        path: Override file path (for testing). Defaults to MEMORY_FILE.
    """
    memories = _load_memories(path)
    if not memories:
        return ""
    lines = [
        "\n\n## Your Memories",
        "Things you've learned about the user from past conversations:",
    ]
    for m in memories:
        lines.append(f"- {m['content']}")
    lines.append(
        "\nUse these memories to personalize your responses. "
        "Save new learnings with save_memory when you discover "
        "something worth remembering."
    )
    return "\n".join(lines)


@tool
def save_memory(content: str) -> str:
    """Save a learning or user preference to long-term memory.

    Use this when you discover something worth remembering across conversations:
    user preferences, writing style, recurring topics, important facts about
    the user's work or environment.

    Args:
        content: A concise, factual statement to remember.

    Returns:
        Confirmation message.
    """
    memories = _load_memories()
    memory = {
        "id": uuid4().hex[:8],
        "content": content,
        "created_at": datetime.now(timezone.utc).isoformat(),
    }
    memories.append(memory)
    if len(memories) > MAX_MEMORIES:
        memories = memories[-MAX_MEMORIES:]
    _save_memories(memories)
    logger.info("Memory saved: %s", content)
    return f"Remembered: {content}"


@tool
def recall_memories() -> str:
    """Recall all saved memories.

    Use at the start of conversations or when you need to check what you
    know about the user.

    Returns:
        Formatted list of all memories, or a message if none exist.
    """
    memories = _load_memories()
    if not memories:
        return "No memories saved yet."
    return "\n".join(f"- [{m['id']}] {m['content']}" for m in memories)


@tool
def forget_memory(memory_id: str) -> str:
    """Remove an outdated or incorrect memory.

    Args:
        memory_id: The ID of the memory to forget (shown in square brackets
                   when recalling memories).

    Returns:
        Confirmation message.
    """
    memories = _load_memories()
    updated = [m for m in memories if m["id"] != memory_id]
    _save_memories(updated)
    logger.info("Memory forgotten: %s", memory_id)
    return f"Forgot memory {memory_id}"
