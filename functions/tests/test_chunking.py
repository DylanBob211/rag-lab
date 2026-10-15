import pytest

from chunking import _enc, chunk


def n_tokens(text: str) -> int:
    return len(_enc().encode(text))


def paragraph(word: str, n: int) -> str:
    return " ".join([word] * n)


def test_empty_text_gives_no_chunks():
    assert chunk("") == []
    assert chunk("\n\n  \n\n") == []


def test_short_text_is_a_single_chunk():
    assert chunk("Hello world.") == ["Hello world."]


def test_small_paragraphs_are_packed_together():
    text = "First paragraph.\n\nSecond paragraph."
    [only] = chunk(text, max_tokens=50, overlap=0)
    assert "First paragraph." in only
    assert "Second paragraph." in only


def test_every_chunk_respects_the_token_budget():
    text = "\n\n".join(paragraph(w, 60) for w in ["alpha", "beta", "gamma", "delta"])
    chunks = chunk(text, max_tokens=100, overlap=20)
    assert len(chunks) > 1
    assert all(n_tokens(c) <= 100 for c in chunks)


def test_consecutive_chunks_overlap():
    text = "\n\n".join(paragraph(w, 60) for w in ["alpha", "beta", "gamma"])
    first, second, *_ = chunk(text, max_tokens=100, overlap=20)
    # The second chunk starts with the tail of the first one.
    assert "alpha" in first
    assert "alpha" in second
    assert "beta" in second


def test_oversized_paragraph_is_split_with_a_fixed_window():
    text = paragraph("word", 500)
    chunks = chunk(text, max_tokens=100, overlap=10)
    assert len(chunks) > 1
    assert all(n_tokens(c) <= 100 for c in chunks)


def test_chunk_order_follows_the_text():
    text = "\n\n".join(paragraph(w, 80) for w in ["one", "two", "three"])
    chunks = chunk(text, max_tokens=100, overlap=0)
    assert ["one" in c for c in chunks].index(True) < [
        "three" in c for c in chunks
    ].index(True)


@pytest.mark.parametrize("overlap", [-1, 100, 150])
def test_invalid_overlap_is_rejected(overlap):
    with pytest.raises(AssertionError):
        chunk("some text", max_tokens=100, overlap=overlap)
