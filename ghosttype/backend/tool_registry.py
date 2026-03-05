"""Maps tool name strings to @tool function objects."""

from agent import rewrite_text, fix_grammar, translate_text
from tools.text_tools import count_words, extract_key_points, change_tone
from tools.memory_tools import save_memory, recall_memories, forget_memory

TOOL_REGISTRY: dict[str, callable] = {
    "rewrite_text": rewrite_text,
    "fix_grammar": fix_grammar,
    "translate_text": translate_text,
    "count_words": count_words,
    "extract_key_points": extract_key_points,
    "change_tone": change_tone,
    "save_memory": save_memory,
    "recall_memories": recall_memories,
    "forget_memory": forget_memory,
}


def resolve_tools(names: list[str]) -> list:
    """Resolve a list of tool name strings into @tool function objects.

    Raises KeyError if any name is not found in the registry.
    """
    result = []
    for name in names:
        if name not in TOOL_REGISTRY:
            raise KeyError(f"Unknown tool: {name}")
        result.append(TOOL_REGISTRY[name])
    return result
