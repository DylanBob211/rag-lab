from azure.cosmos.exceptions import CosmosResourceNotFoundError
from config import get_container


def upsert_header(
    docId: str, incoming_sequencer: str, chunks: list[str], deleted: bool
):
    get_container().upsert_item(
        {
            "id": docId,
            "docId": docId,
            "sequencer": incoming_sequencer,
            "deleted": deleted,
            "chunkCount": len(chunks),
        }
    )


def read_header(docId: str):
    try:
        return get_container().read_item(item=docId, partition_key=docId)
    except CosmosResourceNotFoundError:
        return None


def cleanup_orphan_chunks(docId: str, chunks: list[str]):
    container = get_container()
    orphans = container.query_items(
        """
          SELECT c.id FROM c 
          WHERE c.docId = @docId AND c.chunkIndex >= @chunksLen
      """,
        parameters=[
            {"name": "@docId", "value": docId},
            {"name": "@chunksLen", "value": len(chunks)},
        ],
        partition_key=docId,
    )
    for o in orphans:
        container.delete_item(item=o["id"], partition_key=docId)


def upsert_chunks(docId: str, chunks: list[str], embeddings: list[list[float]]):
    container = get_container()
    for i, (c, e) in enumerate(zip(chunks, embeddings)):
        container.upsert_item(
            {
                "id": f"{docId}_{i}",
                "docId": docId,
                "chunkIndex": i,
                "text": c,
                "embedding": e,
            }
        )


def delete_all(docId: str):
    container = get_container()
    items = container.query_items(
        "SELECT c.id FROM c WHERE c.docId = @docId",
        parameters=[{"name": "@docId", "value": docId}],
        partition_key=docId,
    )
    for item in items:
        container.delete_item(item=item["id"], partition_key=docId)
