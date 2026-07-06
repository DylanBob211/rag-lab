from os import environ
from azure.identity import DefaultAzureCredential, get_bearer_token_provider, AzureCliCredential
from openai import AzureOpenAI
from azure.cosmos import CosmosClient, PartitionKey

aoai_endpoint = environ["AOAI_ENDPOINT"]

cred = DefaultAzureCredential()
token_provider = get_bearer_token_provider(cred, "https://cognitiveservices.azure.com/.default")

aoai = AzureOpenAI(azure_endpoint=aoai_endpoint, azure_ad_token_provider=token_provider, api_version="2024-10-21")
embedding_dimensions = 1536

def embed(text: str):
  response = aoai.embeddings.create(input=text, model="embedder", dimensions=embedding_dimensions)
  return response.data[0].embedding

cosmosdb_endpoint = environ["COSMOSDB_ENDPOINT"]

cosmos_client = CosmosClient(cosmosdb_endpoint, cred)

db = cosmos_client.get_database_client("ragdb")
container = db.get_container_client("docs")


DOCS = [
    ("1", "Azure Container Apps scales to zero with KEDA on queue length."),
    ("2", "Key Vault stores passwords as secrets; keys are used, never exported."),
    ("3", "Service Bus dead-letters messages that repeatedly fail processing."),
]


for id, text in DOCS:
  container.upsert_item({ "id": id, "text": text, "embedding": embed(text)})

print("ingested", len(DOCS), "docs")