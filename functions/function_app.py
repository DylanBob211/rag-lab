import azure.functions as func
from config import sbus_queue, download_text, embed_batch
from models import BlobEvent
from chunking import chunk
from db import (
    upsert_header,
    upsert_chunks,
    cleanup_orphan_chunks,
    read_header,
    delete_all,
)

app = func.FunctionApp()


@app.function_name("DocSync")
@app.service_bus_queue_trigger(
    arg_name="msg",
    is_sessions_enabled=True,
    connection="SERVICEBUS_CONNECTION",
    queue_name=sbus_queue,
)
def doc_sync(msg: func.ServiceBusMessage):

    body = msg.get_body().decode("utf-8")
    event = BlobEvent.model_validate_json(body)

    docId = get_partition_key(event)
    incoming_sequencer = event.data.sequencer
    header = read_header(docId)

    if header and header["sequencer"] >= incoming_sequencer:
        return

    if event.eventType == "Microsoft.Storage.BlobCreated":
        text = download_text(event.data.url)
        chunks = chunk(text)
        embeddings = embed_batch(chunks)
        upsert_chunks(docId, chunks, embeddings)
        cleanup_orphan_chunks(docId, chunks)
        upsert_header(docId, incoming_sequencer, chunks, deleted=False)
    elif event.eventType == "Microsoft.Storage.BlobDeleted":
        delete_all(docId)
        upsert_header(docId, incoming_sequencer, chunks=[], deleted=True)


def get_partition_key(event: BlobEvent):
    return event.subject.split("/blobs/").pop()
