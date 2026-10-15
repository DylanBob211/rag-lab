"""Tests for the DocSync orchestration: which steps run, in which order, and
when an event is skipped. Every Azure call is replaced by a fake that records
what it was asked to do."""

import json

import azure.functions as func
import pytest

import function_app

DOC = "guide.md"
URL = f"https://acct.blob.core.windows.net/docs/{DOC}"


def message(event_type: str, sequencer: str) -> func.ServiceBusMessage:
    body = {
        "eventType": f"Microsoft.Storage.{event_type}",
        "subject": f"/blobServices/default/containers/docs/blobs/{DOC}",
        "data": {"url": URL, "sequencer": sequencer},
    }
    return func.ServiceBusMessage(body=json.dumps(body).encode())


@pytest.fixture
def cosmos():
    """What read_header finds in Cosmos; a test may pre-seed a header."""
    return {"header": None}


@pytest.fixture
def calls(monkeypatch, cosmos):
    """Replaces every side effect in function_app and returns the call log."""
    log = []

    def record(name, result=None):
        def fake(*args, **kwargs):
            log.append((name, *args))
            return result

        return fake

    monkeypatch.setattr(function_app, "init_telemetry", lambda: None)
    monkeypatch.setattr(function_app, "read_header", lambda doc_id: cosmos["header"])
    monkeypatch.setattr(
        function_app, "download_text", record("download", "Para one.\n\nPara two.")
    )
    monkeypatch.setattr(
        function_app, "embed_batch", lambda chunks: [[0.0]] * len(chunks)
    )
    for name in [
        "invalidate_cache",
        "upsert_chunks",
        "cleanup_orphan_chunks",
        "upsert_header",
        "delete_all",
    ]:
        monkeypatch.setattr(function_app, name, record(name))

    return log


def names(log):
    return [entry[0] for entry in log]


def test_partition_key_is_the_blob_name():
    event = function_app.BlobEvent.model_validate_json(
        message("BlobCreated", "01").get_body()
    )
    assert function_app.get_partition_key(event) == DOC


def test_created_blob_is_indexed_and_cache_invalidated_around_the_write(calls):
    function_app.doc_sync(message("BlobCreated", "0002"))

    assert names(calls) == [
        "invalidate_cache",
        "download",
        "upsert_chunks",
        "cleanup_orphan_chunks",
        "upsert_header",
        "invalidate_cache",
    ]
    assert calls[1] == ("download", URL)
    assert calls[4][1:3] == (DOC, "0002")


def test_deleted_blob_removes_chunks_and_marks_header_deleted(calls):
    function_app.doc_sync(message("BlobDeleted", "0002"))

    assert names(calls) == [
        "invalidate_cache",
        "delete_all",
        "upsert_header",
        "invalidate_cache",
    ]
    assert calls[2] == ("upsert_header", DOC, "0002")


@pytest.mark.parametrize("stored_sequencer", ["0002", "0003"])
def test_stale_or_duplicate_event_is_ignored(calls, cosmos, stored_sequencer):
    cosmos["header"] = {"sequencer": stored_sequencer}

    function_app.doc_sync(message("BlobCreated", "0002"))

    assert calls == []


def test_newer_event_than_stored_header_is_processed(calls, cosmos):
    cosmos["header"] = {"sequencer": "0001"}

    function_app.doc_sync(message("BlobCreated", "0002"))

    assert "upsert_chunks" in names(calls)
