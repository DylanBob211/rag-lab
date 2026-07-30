"""
Live change-feed reader for the RAG lab — watch the "receipt tape" scroll.

Two terminals:
  A)  python watch_changes.py     # leave it running: it polls the feed every 2s
  B)  (write a doc — see the one-liner in chat)  → it appears in terminal A

The file .cf_token is your BOOKMARK (the checkpoint). Delete it to replay the
whole tape from the beginning. Keep it, and a restart resumes exactly where you
left off — that's the whole idea, made physical.
"""
import time
import pathlib
from config import container          # reuses your existing Cosmos connection

TOKEN_FILE = pathlib.Path(".cf_token")


def read_next_slice():
    # 1. Load the bookmark, if we have one from a previous poll.
    token = TOKEN_FILE.read_text().strip() if TOKEN_FILE.exists() else None

    # 2. Ask the feed for what changed AFTER the bookmark (or from the start).
    if token:
        it = container.query_items_change_feed(continuation=token)
    else:
        it = container.query_items_change_feed(is_start_from_beginning=True)

    # 3. Drain this slice of the tape into a list.
    docs = list(it)

    # 4. Cosmos hands back a NEW bookmark in the 'etag' response header. Save it.
    new_token = container.client_connection.last_response_headers["etag"]
    TOKEN_FILE.write_text(new_token)
    return docs


print("watching docs/chunks change feed — Ctrl-C to stop")
print("bookmark:", "resuming from saved .cf_token" if TOKEN_FILE.exists() else "from the beginning")

while True:
    for doc in read_next_slice():
        if "text" in doc:                                   # a chunk item
            print(f"  chunk   {doc['id']:>22}  _ts={doc['_ts']}  {doc['text'][:44]!r}")
        else:                                               # a header item
            state = "DELETED" if doc.get("deleted") else f"{doc['chunkCount']} chunks"
            print(f"  HEADER  {doc['id']:>22}  _ts={doc['_ts']}  {state}")
    time.sleep(2)          # empty polls = the feed is quiet. That's normal.
