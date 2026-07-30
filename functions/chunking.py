from functools import lru_cache

import tiktoken


@lru_cache
def _enc():
    return tiktoken.get_encoding("cl100k_base")


def _window(tokens: list[int], max_tokens: int, overlap: int) -> list[list[int]]:
    """Finestra scorrevole su una lista di token. Serve come fallback per un
    singolo paragrafo piu' lungo del budget: li' non c'e' confine semantico da
    rispettare, quindi si taglia a lunghezza fissa con overlap."""
    step = max_tokens - overlap
    return [tokens[i : i + max_tokens] for i in range(0, len(tokens), step)]


def chunk(text: str, max_tokens: int = 256, overlap: int = 40) -> list[str]:
    """Spezza `text` in chunk, ognuno <= max_tokens, impacchettando paragrafi
    interi (split su riga vuota) e portandosi dietro ~`overlap` token di coda
    tra chunk consecutivi. L'ordine della lista E' il chunkIndex.

    Puro: testo -> lista di testi. Non sa nulla di embedding, id o Cosmos."""
    assert 0 <= overlap < max_tokens, "overlap deve stare sotto max_tokens"

    paragraphs = [p.strip() for p in text.split("\n\n") if p.strip()]
    if not paragraphs:
        return []

    chunks: list[list[int]] = []
    current: list[int] = []

    for para in paragraphs:
        ptoks = _enc().encode(para)

        # Paragrafo piu' grande del budget: chiudi cio' che hai e spezzalo da
        # solo con la finestra fissa.
        if len(ptoks) > max_tokens:
            if current:
                chunks.append(current)
                current = []
            chunks.extend(_window(ptoks, max_tokens, overlap))
            continue

        # Non ci sta: chiudi il chunk corrente e riparti portandoti dietro la
        # coda come overlap. `keep` e' limitato cosi' overlap + nuovo paragrafo
        # non sforano mai max_tokens (l'invariante di ogni chunk).
        if current and len(current) + len(ptoks) > max_tokens:
            chunks.append(current)
            keep = min(overlap, max_tokens - len(ptoks))
            current = current[-keep:] if keep > 0 else []

        current.extend(ptoks)

    if current:
        chunks.append(current)

    return [_enc().decode(c) for c in chunks]
