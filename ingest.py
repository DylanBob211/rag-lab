from embed import embed
from config import container

DOCS = [
    ("1", "Azure Container Apps scales to zero with KEDA on queue length."),
    ("2", "Key Vault stores passwords as secrets; keys are used, never exported."),
    ("3", "Service Bus dead-letters messages that repeatedly fail processing."),
]

for id, text in DOCS:
    container.upsert_item({"id": id, "text": text, "embedding": embed(text)})

print("ingested", len(DOCS), "docs")
