"""Custom Strands tools for text operations."""

from strands import tool


@tool
def count_words(text: str) -> str:
    """Count words and characters in the given text.

    Args:
        text: The text to analyze.

    Returns:
        Word and character count summary.
    """
    words = len(text.split())
    chars = len(text)
    sentences = text.count('.') + text.count('!') + text.count('?')
    return f"Words: {words}, Characters: {chars}, Sentences: {sentences}"


@tool
def extract_key_points(text: str) -> str:
    """Extract key points from the given text.

    Args:
        text: The text to analyze.

    Returns:
        Key points as bullet points.
    """
    return f"Extract the key points from this text and present as bullet points:\n\n{text}"


@tool
def change_tone(text: str, tone: str) -> str:
    """Change the tone of the given text.

    Args:
        text: The text to modify.
        tone: Target tone (formal, casual, enthusiastic, empathetic, assertive).

    Returns:
        Text rewritten in the target tone.
    """
    return f"Rewrite the following text in a {tone} tone:\n\n{text}"
