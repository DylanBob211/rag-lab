"""
Tails the Cosmos DB change feed of the chunks container.

    python watch_changes.py

Then upload or delete a document (scripts/upload_corpus.sh) and watch the
header and chunk writes made by the DocSync function appear here.

The continuation token is checkpointed to .cf_token after every poll, so a
restart resumes where it left off. Delete the file to replay the feed from
the beginning.
"""

import time
import pathlib
from config import container

TOKEN_FILE = pathlib.Path(".cf_token")


def read_next_slice():
    token = TOKEN_FILE.read_text().strip() if TOKEN_FILE.exists() else None

    if token:
        it = container.query_items_change_feed(continuation=token)
    else:
        it = container.query_items_change_feed(is_start_from_beginning=True)

    docs = list(it)

    # The new continuation token comes back in the 'etag' response header.
    new_token = container.client_connection.last_response_headers["etag"]
    TOKEN_FILE.write_text(new_token)
    return docs


print("watching the change feed - Ctrl-C to stop")
print(
    "resuming from .cf_token" if TOKEN_FILE.exists() else "starting from the beginning"
)

while True:
    for doc in read_next_slice():
        if "text" in doc:  # a chunk item
            print(f"  chunk   {doc['id']:>22}  _ts={doc['_ts']}  {doc['text'][:44]!r}")
        else:  # a header item
            state = "DELETED" if doc.get("deleted") else f"{doc['chunkCount']} chunks"
            print(f"  HEADER  {doc['id']:>22}  _ts={doc['_ts']}  {state}")
    time.sleep(2)
