from azure.cosmos.exceptions import CosmosResourceNotFoundError
from config import container


def upsert_header(
    docId: str, incoming_sequencer: str, chunks: list[str], deleted: bool
):
    container.upsert_item(
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
        return container.read_item(item=docId, partition_key=docId)
    except CosmosResourceNotFoundError:
        return None


def cleanup_orphan_chunks(docId: str, chunks: list[str]):
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
    container.delete_all_items_by_partition_key(partition_key=docId)
