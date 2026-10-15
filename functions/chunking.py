from functools import lru_cache

import tiktoken


@lru_cache
def _enc():
    return tiktoken.get_encoding("cl100k_base")


def _window(tokens: list[int], max_tokens: int, overlap: int) -> list[list[int]]:
    """Sliding window over a list of tokens. Fallback for a single paragraph
    longer than the budget: there's no semantic boundary to respect inside it,
    so it is cut at a fixed length with overlap."""
    step = max_tokens - overlap
    return [tokens[i : i + max_tokens] for i in range(0, len(tokens), step)]


def chunk(text: str, max_tokens: int = 256, overlap: int = 40) -> list[str]:
    """Split `text` into chunks of at most max_tokens each, packing whole
    paragraphs (split on blank lines) and carrying ~`overlap` trailing tokens
    over between consecutive chunks. The list order IS the chunkIndex.

    Pure: text -> list of texts. Knows nothing about embeddings, ids or Cosmos."""
    assert 0 <= overlap < max_tokens, "overlap must be below max_tokens"

    paragraphs = [p.strip() for p in text.split("\n\n") if p.strip()]
    if not paragraphs:
        return []

    chunks: list[list[int]] = []
    current: list[int] = []

    for para in paragraphs:
        ptoks = _enc().encode(para)

        # Paragraph larger than the budget: close the current chunk and split
        # this paragraph on its own with the fixed window.
        if len(ptoks) > max_tokens:
            if current:
                chunks.append(current)
                current = []
            chunks.extend(_window(ptoks, max_tokens, overlap))
            continue

        # Doesn't fit: close the current chunk and start a new one seeded with
        # its tail as overlap. `keep` is capped so overlap + new paragraph never
        # exceed max_tokens (the invariant of every chunk).
        if current and len(current) + len(ptoks) > max_tokens:
            chunks.append(current)
            keep = min(overlap, max_tokens - len(ptoks))
            current = current[-keep:] if keep > 0 else []

        current.extend(ptoks)

    if current:
        chunks.append(current)

    return [_enc().decode(c) for c in chunks]
